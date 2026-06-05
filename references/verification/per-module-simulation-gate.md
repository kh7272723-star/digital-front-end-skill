# Per-Module Simulation Gate

## Purpose

For L2 multi-module RTL projects, top-level simulation is not enough for a PASS claim. Each RTL module needs isolated compile/simulation/proof evidence before integration simulation starts.

This gate exists because integration-only tests hide module bugs behind interfaces, FIFOs, pipelines, and protocol handshakes. Debug should first prove each module's local contract, then prove module interaction.

## Mandatory Order

Use this order for L2 designs:

1. Freeze per-module interface contracts.
2. Run standalone compile for each RTL module.
3. Write one focused TB per non-trivial module.
4. Run guarded per-module simulation.
5. Run `scripts/sim_log_gate.py` on each module log.
6. Record every module in `docs/module_verification_matrix.md`.
7. Only then write and run the integration TB.

Do not claim final PASS if integration simulation passed but per-module evidence is missing.

## Minimum Per-Module TB Scope

Each non-trivial module TB must cover:

- reset release and known output state
- one normal transaction or operation
- one boundary condition
- one stall, backpressure, retry, or error case when applicable
- observable pass/fail output using the standard simulation protocol

The module TB can be narrower than the integration TB, but it must directly check the module's local contract. A TB that only waits for `done` without checking payload, sideband, status, or timing is not enough.

## Required Commands

Use guarded execution and log gates:

```bash
python scripts/rtl_style_check.py rtl/<module>.v tb/tb_<module>.v
iverilog -g2012 -o sim/tb_<module>.vvp rtl/<module>.v tb/tb_<module>.v
python scripts/run_sim_guarded.py --timeout-sec 30 --log sim/tb_<module>.log -- vvp sim/tb_<module>.vvp
python scripts/sim_log_gate.py sim/tb_<module>.log
```

For modules with formal-only evidence, record the formal command and passing log path in the matrix.

## `docs/module_verification_matrix.md`

Create this file for every L2 project.

Recommended format:

```markdown
# Module Verification Matrix

| Module | Contract | TB/Formal | Evidence log | Status | Waiver |
|--------|----------|-----------|--------------|--------|--------|
| desc_fetch | docs/interface-contracts.md#desc_fetch | tb/tb_desc_fetch.v | sim/tb_desc_fetch.log | PASS | none |
| axi_writer | docs/interface-contracts.md#axi_writer | tb/tb_axi_writer.v | sim/tb_axi_writer.log | PASS | none |
| top_wrapper | docs/interface-contracts.md#top | integration-only | sim/tb_top.log | PASS | trivial top-level wiring wrapper |
```

Rules:

- Every `module` declared under `rtl/*.v` must appear in the matrix.
- Every non-waived row must include an evidence log path.
- Evidence logs must be inside the project directory.
- A passing simulation log must include `ALL_TESTS_PASS` and `SIMULATION_DONE`, or the relevant compile/formal/assertion gate PASS marker.
- `Status: Pending`, `TBD`, blank evidence, or placeholder rows are incompatible with final `Status: PASS`.

## Waiver Rules

Waivers are allowed only when they are explicit and narrow:

- trivial top-level wiring wrapper covered by integration TB
- pure package/include file with no executable behavior
- formal-only proof replaces simulation and has a passing proof log
- external hard IP wrapper with documented integration checks

A waiver must name the residual risk and the compensating integration check. "Integration simulation passed" alone is not a waiver for a non-trivial module.

## Final Gate

`scripts/project_artifact_gate.py <project_dir>` checks L2 projects for `docs/module_verification_matrix.md`, module coverage, evidence paths, and pass markers. Missing or placeholder module evidence must block final PASS.

## Pre-Integration Lock

`scripts/pre_integration_gate.py <project_dir>` enforces the integration prohibition:

- For L2 projects with >=2 RTL modules, integration simulation must NOT start until every module has per-module evidence.
- The gate detects integration TBs (files instantiating multiple RTL modules or a top-level module).
- The gate detects integration sim artifacts (logs/vvp) existing without per-module evidence.
- Integration TB existence before per-module evidence = FAIL.

This gate runs as part of `scripts/final_delivery_gate.py` Step 1b. It catches the anti-pattern of writing an integration TB and running integration sim before per-module evidence exists.

**Prohibition:** Integration simulation is prohibited until the module verification matrix passes. Do not write integration TBs, do not run integration sim, do not create integration logs until per-module evidence is complete.
