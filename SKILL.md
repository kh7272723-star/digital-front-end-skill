---
name: digital-front-end-skill
description: >
  Digital front-end RTL design assistant for Verilog/SystemVerilog. MUST use this skill for ANY RTL coding task,
  module interface design, FSM design, ready/valid or req/ack handshakes, FIFO/pipeline/arbiter/counter patterns,
  testbench generation, timing explanation, lint/code review, simulation debug, or bug triage. Even if the user
  doesn't mention "skill" or "RTL" explicitly, trigger this for any digital hardware design work including
  synthesis-aware coding, CDC handling, protocol implementation (AXI/APB/AHB/AXI-Stream), clock gating,
  interrupt controllers, DMA engines, and multi-module subsystem design.
---

# Digital Front-End Skill

Use this skill to turn a rough digital design request into a reviewable RTL deliverable with clear assumptions, a stable coding style, and a verification plan.

The core method is:

1. Start from authoritative RTL, language, reset, CDC, and verification guidance.
2. Distill that material into compact internal design rules.
3. Select the closest local pattern or example.
4. Write the cycle-level contract and trace before code.
5. Generate conservative RTL and verification checks that match the contract and trace.

## What this skill is good for

- Translate feature requests into RTL-ready requirements with module boundaries, ports, widths, reset behavior, and handshake rules.
- Generate synthesizable Verilog RTL for FSMs, FIFOs, pipelines, arbiters, counters, and protocol glue.
- Plan subsystem and full-system designs with hierarchy, interface contracts, integration invariants, and staged bring-up.
- Produce testbench scaffolding, verification matrices, and directed test plans.
- Adapt to existing project conventions before changing integrated RTL.
- Explain timing behavior cycle by cycle, review code for RTL issues, and triage simulation failures.

## Limitations

No correctness claims without verification. No invented interface semantics when requirements are underspecified. No replacement for CDC review, formal signoff, or engineering judgment. Plain templates over 'clever' RTL. Cycle-level contracts over generic timing prose. No monolithic full-system RTL from an underspecified prompt. Directed simulation is not signoff.

## Operating principles

1. Extract the design contract first. If critical details are missing, ask before writing code.
2. Prefer explicit structure over compactness. Separate combinational and sequential logic.
3. Make timing visible: what changes this cycle vs. what registers to the next cycle.
4. When generating RTL, also generate a verification plan with directed tests.
5. Debug from evidence: compiler/lint errors, sim logs, wave behavior, assertions.

## Authority-to-rule synthesis

Treat standards and methodology documents as source material, not as answer text. Hierarchy: (1) user-provided spec, (2) Verilog/SystemVerilog standards, (3) vendor/methodology guidance, (4) established synchronous design practice, (5) this skill's local examples. See `references/timing/authority-synthesis.md`.

For protocol-specific rules, also read `references/timing/protocol-authority-map.md` before making or applying a hard claim. Mark each protocol constraint as **Normative**, **Project policy**, **Conservative pattern**, **Heuristic**, or **Unverified**. Do not say a design "violates AXI/APB/AHB/NVMe" unless the violated behavior is traced to a normative rule in the selected protocol version or to the user's project spec.

## Reference materials

Read `references/reference-index.md` for a task-to-reference mapping. Key directories:

- **Timing/protocol**: `references/timing/` -- timing semantics, contracts, naming, protocol rules, cycle traces, clock/reset
- **Architecture**: `references/architecture/` -- hierarchy, system contracts, integration invariants, tradeoffs, staged bring-up, pipeline design patterns, memory hierarchy & buffer strategy, performance analysis
- **AXI/DMA**: `references/axi-dma/` -- AXI full/Lite/Stream, DMA channel guidelines, CDMA examples, outstanding rules
- **Bus protocols**: `references/bus/` -- APB, AHB-Lite
- **RTL patterns**: `references/rtl/` -- coding guidelines, FSM examples, FIFO examples, handshake examples, pipeline examples, naming conventions, correctness rules (multi-driven, latch, width, blocking/nonblocking, reset, loops, implicit wires)
- **Specialized patterns**: `references/patterns/` -- arbiters, credit-based, rate-limiter, retry buffer, CRC, ECC, width converter, frame assembler, multi-bank memory, CAM
- **Verification**: `references/verification/` -- verification guidance, TB examples, assertion examples, coverage models, formal properties, UVM templates, AXI verification (BFM, scoreboard, coverage), simulation loop (lint->compile->simulate->fix), engineering review checklist
- **Debug**: `references/debug/` -- debug cases, bug pattern library
- **Existing project**: `references/project/` -- project adaptation, brownfield guidance, large module guidance
- **CDC/synthesis**: `references/synthesis/` -- CDC guidelines, constraint guidance, synthesis guidance, toolchain closure, formal verification
- **Advanced**: `references/advanced/` -- low-power, DFT, UVM, physical awareness
- **Design intuition**: `references/design/` -- design heuristics, tool-driven workflow, power/timing/area rules (low-power RTL, timing closure, resource optimization)

## Coding rules (mandatory)

**Primary coding standard:** All RTL code must follow `references/rtl/rtl-coding-standards.md`. That document combines project coding rules (M/S/R grades) with skill best practices, covering naming, code structure, FSM templates, reset strategy, and timing optimization. Read it before writing any RTL.

Hard rules summary (full list in `rtl-coding-standards.md`):

- **Naming**: all lowercase for signals/modules, all UPPERCASE for parameters. Port suffix `_i`/`_o`. Active-low adds `_n`. Pipeline delay uses `_r`/`_r0`/`_r1`. Instance names get `inst_` prefix.
- **FSM**: two-process style, `cstate`/`nstate`, state names `S_` UPPERCASE prefix. FSM outputs single-bit enables only (M); multi-bit arithmetic stays in datapath. (C5/C6/C9/C10)
- **Datapath vs FSM separation**: no datapath inside FSM blocks; no `case(state)` inside datapath blocks. (C5/C6/C7)
- **No array encoding**: `reg [W] arr[N]` is forbidden. Use BRAM primitives for deep storage. (C17)
- **Control symmetry**: if reset controls some registers in an `always` block, all registers on the same timing chain must be equally controlled. (C14)
- **Code quality**: `` `default_nettype none`` (C3), explicit bit widths (C16), check latches (C15), FSM defaults first (C10).
- **AXI channel separation**: AW/W/B independent valid/ready control. Read/write command paths independent. See `references/axi-dma/axi-dma-channel-guidelines.md`.

## Timing and protocol discipline

See `references/timing/timing-discipline.md` for full rules. Key points:

- Write the cycle contract before code. See `references/timing/timing-contract-template.md`.
- For FSM/FIFO/pipeline/handshake logic, include a cycle trace before RTL. See `references/timing/cycle-trace-guidelines.md`.
- For ready/valid logic, define exactly when data is accepted, held, and released.
- For CDC or multi-clock logic, require an explicit safe crossing pattern.

## Example-driven learning

Prefer example-first reasoning for RTL tasks:

1. Find the closest verified pattern in `references/rtl/` or `references/patterns/`.
2. Extract the cycle-level rule from the example.
3. Generalize only after the contract is clear.
4. Reject examples that are syntactically valid but semantically unclear.

Before reusing an example, check: reset style match, handshake naming match, boundary behavior defined, data/control alignment under stall, verification note checks the same contract.

## Step 0 -- Workflow Entry Routing

Not every request goes through the full RTL design pipeline. Route first, then execute:

| Mode | Trigger | Entry point | Mandatory gates |
|------|---------|-------------|-----------------|
| **design** | "write/implement/generate RTL" | Step 1 -> full pipeline | All level-appropriate gates |
| **review** | "review/audit/check RTL" | Gate-first: rtl_style -> manual review | RSP1-RSP7, claim ledger, false-pass |
| **debug** | "fix/debug sim failure" | simulation-loop.md Phase 4 | Principle diagnosis, bug pattern, fix discipline |
| **protocol-audit** | "audit protocol claims" | protocol-claim-ledger.md | Label must/shall; verify against source |
| **skill-maintenance** | "modify/improve skill" | Read CLAUDE.md first | skill_static_check, eval_benchmark, json.tool |
| **L2-orchestration** | "plan multi-module" | Steps 1->1.1->1.5->1.6 | Delegation + Release Gates; contracts frozen |

Full details: `references/workflow/task-mode-routing.md`. Design Mode follows the pipeline below. Review/Debug/Protocol-Audit modes do NOT enter the full RTL generation pipeline.

## Standard workflow

### 1. Parse the request

Summarize the requested block and list open questions. If working in an existing project, inspect local conventions first. Classify the design using the three-tier complexity gate:

| Level | Criteria | Principle review | Agent strategy |
|:-----:|----------|:----------------:|----------------|
| **L0: Trivial** | <=200 lines, <=8 FSM states, linear flow (no branches other than counter completion), single protocol | **Skip 2a/5a. Only P3 at 8c** (register audit). Inline in dev log. | **No delegation.** Single executor unless user explicitly requests parallel review. |
| **L1: Leaf** | 200-500 lines, or nonlinear FSM, or dual protocol (e.g. APB + UART) | **FAST: 1-2 questions/principle** at 2a/5a/8c. Separate .md files. | **Single executor** unless TB/review lane is fully independent or user explicitly requests parallel. |
| **L2: Subsystem** | >500 lines, or multi-module, or multi-clock, or 3+ protocols | **FULL: 3-5 questions/principle** at 2a/5a/8c. Signal tracing required. | **Mandatory delegation decision** -> Step 1.1 gate. Delegate or write waiver. |

**L0 note:** R5-R8: modules <=200 lines with linear FSMs had ZERO bugs found at distributed checkpoints (2a/5a). Separate review docs are wasted effort at L0. Keep P3 register audit at 8c -- catches naming/init gaps even in simple modules.

**L2 note:** R8b: projects >500 lines / >10 FSM states exceed single-agent completion window (~600s).

### 1.1 Delegation Decision Gate (mandatory after classification)

After L0/L1/L2 classification, make an explicit delegation decision before any RTL work:

**L0:** No delegation by default. Single executor.
**L1:** Single executor by default. Only delegate when TB/review are per-module independent or user requests parallel.
**L2:** Mandatory decision record in dev log:

```
Delegation Decision:
- Level: L2
- Delegate: yes / no
- If yes: assign roles (list)
- Contracts frozen: yes / pending
- If no: waiver reason + compensation gates
```

**Hard triggers (any one -> yes):** estimated RTL >800 lines; sub-modules >3; any module >400 lines; naturally separable protocols (AXI+NVMe+CDC/FIFO); independent verification lane; authority audit separable; user requests parallel.

**L2 waiver (if no delegation):** reason, residual risk, compensation gates: per-module compile, RSP1-RSP7, boundary review, false-pass audit.

Execution waits on frozen per-module contracts. **L2 Delegate: yes requires execution evidence** -- `docs/delegation_plan.md` and subagent role reports under `docs/subagents/` (architect, protocol_reviewer, axi_transaction_reviewer, rtl_structural_reviewer, verification_reviewer, integration_reviewer). Without all artifacts, `project_artifact_gate.py` rejects PASS. See `references/architecture/sub-agent-delegation.md` for full artifact schema.

### 1.2 Project Skeleton / Preflight Gate (mandatory for L1/L2 No-SPEC)

Before any RTL, create the canonical project skeleton. Run `scripts/project_preflight_gate.py <project_dir>` to verify:

- `docs/` directory with skeleton files: `dev_log.md`, `SPEC.md`, `interface-contracts.md`, `timing-contract.md`, `protocol_claim_ledger.md`, `verification_matrix.md`, `contract_implementation_matrix.md`
- `rtl/` directory (L1+L2), `tb/` directory (L2), `sim/` directory
- Skeleton files may be empty placeholders initially; they are filled progressively
- `dev_log.md` is the evidence chain -- start it at Step 1 and fill as you go

This gate is fail-closed: missing skeleton -> BLOCKED. It complements `project_artifact_gate.py` (final) by preventing code-only delivery from the start.

### 1.5 L2 fork -- subsystem decomposition (mandatory for L2, skip for L0/L1)

**L0/L1 modules proceed directly to Step 2.** L2 subsystems MUST fork here before writing any RTL:

1. **Produce submodule decomposition.** List every module, its purpose, estimated lines, and dependencies. For modules estimated >400 lines, must either split further OR assign dedicated owner OR write waiver.

2. **Write a per-module interface contract for each submodule.** Use `references/architecture/interface-contract-template.md`. Minimum: port list, signal widths, handshake protocol, completion signal type (pulse vs level). Cross-check producer-consumer port widths.

3. **Per-module contract freeze before RTL.** Every submodule's interface contract must be frozen before ANY module's RTL is generated. Prevents the NVMe Phase 1 bug: interfaces matched, data-path routing undefined.

```
L0/L1: Step 1 -> Step 2 -> Step 3 -> ... -> Step 10
L2:    Step 1 -> 1.1 -> 1.5 (decompose + contracts frozen)
              -> 1.6 (release gate, if delegated)
              -> Steps 2-9 per module -> Step 10
```

### 1.6 L2 Sub-Agent Release Gate (mandatory before starting sub-agents)

If Step 1.1 decided yes (delegate), do NOT start sub-agents until EVERY item is checked:

- [ ] Per-module interface contracts frozen (all modules)
- [ ] Roles/owners assigned (architect, RTL executor per module, verification executor, protocol reviewer, integration reviewer)
- [ ] Per-module acceptance commands defined: `iverilog -g2012 -o /dev/null <module>.v`
- [ ] Integration reviewer assigned and briefed on boundary cross-check (P6)
- [ ] Sub-agent prompt includes: skill path + module interface contract + RSP1-RSP7 + protocol authority labels + acceptance commands
- [ ] Contract-freeze status recorded in delegation record

If any item is unchecked, do NOT start sub-agents. See `references/architecture/sub-agent-delegation.md` for release record template.

**No-SPEC L1/L2 deliverables:** If no project SPEC is provided, create canonical artifacts under `docs/` before RTL: `dev_log.md`, `SPEC.md`, `interface-contracts.md`, `timing-contract.md`, `protocol_claim_ledger.md`, `verification_matrix.md`, `contract_implementation_matrix.md`. `dev_log.md` is evidence chain only.

If the spec is underspecified, run `references/architecture/requirement-extraction-template.md` before Step 2. If more than 3 Required dimensions are unanswered, pause and ask.

For NVMe/DMA: define a global source byte cursor (never per-page reset), separate PRP cursors, non-uniform multi-page continuity test. See `references/bus/nvme-guidelines.md` section 14. For full systems (>3 sub-modules), produce system contract + decomposition + integration invariants before any RTL.

### 1.7 SPEC Consistency Gate (mandatory for L1/L2, before Step 2)

Read `references/workflow/spec-consistency-gate.md`. Before any timing contract, verify the spec is internally self-consistent. For NVMe/DMA, hard-check at minimum: `transfer_bytes = (NLB+1)*LBA_SIZE`, PRP1 offset + first-page capacity, PRP2 page/list boundary, PRP list entries/chaining, AWLEN=beats-1, BRESP/RRESP propagation, expected beat count. If the spec contradicts a formula or protocol claim, fix the SPEC first -- do not write RTL against a self-contradictory spec.

### 2. Build the timing contract first

Before writing code, produce a short timing contract using `references/timing/timing-contract-template.md`. Include: module purpose, clock domains, reset style, input/output handshake, data latency, stall/flush behavior, boundary behavior, illegal cases.

### 2a. Principle check -- Independence and Boundaries (P4, P6)

**SKIP if Level 0 (Trivial).** For L1/L2, continue below.

**Why now:** Architecture-level coupling and boundary mismatches are cheapest to fix at contract time -- before any RTL exists.

Read `references/design/design-principles.md` P4 and P6. Before asking questions, check the "When to skip" section in each principle -- some principles may not apply to your design type. For L1: ask 1-2 questions. For L2: ask 3-5 questions.

**For L2 multi-module designs, also consult:**
- `references/architecture/pipeline-design-patterns.md` -- identify the pipeline topology, check backpressure propagation, flag any multi-rate or split-merge structures
- `references/architecture/memory-hierarchy.md` -- compute FIFO depths, check buffer placement, audit arbitration strategy
- `references/architecture/performance-analysis.md` -- calculate throughput, identify bottleneck, check for deadlock cycles in the backpressure graph

**P4 (Independence):** Are there independent channels/paths/domains in this design? Does the contract specify that they are decoupled? Can a transaction on one interface accidentally consume or corrupt data on another? Can one channel's backpressure block another's progress?

**P6 (Boundaries):** Does every module boundary have matching port widths? Are error signals propagated from sub-modules to top-level outputs? Is the completion signal style (pulse vs level) consistent across the integration chain?

**P4 -- Intra-Module Independence (L1/L2 mandatory):** Beyond inter-module channel separation, check independence WITHIN each module: (1) protocol control path must not depend on unrelated data-path state unless the contract says so; (2) AXI W data must choose continuous or elastic mode explicitly (`rtl_style_check.py` AXI_WDATA_SOURCE1); (3) beat counters/FIFOs advance only on `valid && ready`; (4) FSM must not read multi-bit datapath registers directly (SM1). Fix contract-level issues now.

### 3. Freeze the contract

Turn the timing contract into a short design spec with: ports and signal widths, naming conventions, reset and idle behavior, handshake or protocol rules, corner cases. **Also create `docs/contract_implementation_matrix.md` skeleton now** -- list every contract item with blank producer/consumer/TB evidence/waiver columns. Fill progressively during RTL/TB development; do not reconstruct at finalization.

### 4. Identify state elements

List registers or memories that carry state: state registers, FIFO storage, accepted-operation conditions, data/control fields that must move together.

### 5. Write the cycle trace

Use `references/timing/cycle-trace-guidelines.md`. Include pre-edge state, combinational condition, active-edge update, next visible state, and invariant.

### 5a. Principle check -- Timing Contracts and FSM Safety (P1, P2)

**SKIP if Level 0 (Trivial).** For L1/L2, continue below.

**Why now:** Verify signal timing and FSM behavior before RTL exists -- redesign is free at the trace level.

Read `references/design/design-principles.md` P1 and P2. Before asking questions, check the "When to skip/lite" section in each principle. For L1 linear FSMs: use P2 LITE (1-2 questions, no abort-path analysis needed). For L2: full P2 (3-5 questions with abort/recovery analysis).

**P1 (Timing Contract):** For every output in the trace: is it pulse (1-cycle), level (sustained), or registered (delayed)? Are pulse outputs guaranteed exactly 1 cycle wide in every trace path? For valid/ready handshakes: does valid hold until ready? Is data stable during backpressure?

**P2 (FSM Safety):** From every non-IDLE state, trace the path back to IDLE. What happens if a waited-on signal never arrives? For states entered by a request: if the request deasserts while in an intermediate state, is there an abort path? After reset, does the FSM start in IDLE with all outputs safe?

Fix any issue found in the cycle trace. Only then freeze the trace and proceed to pattern selection.

### 6. Choose a pattern

**Before choosing a pattern, read the relevant reference.** This is a hard requirement (not optional), same as Step 7's coding standards read. Do not rely on memory or training data. For protocol patterns, read `references/timing/protocol-authority-map.md` first and distinguish normative protocol semantics from local conservative implementation policy.

Pick the safest known template from `references/rtl/` or `references/patterns/`. Explain why it fits. If multiple patterns are plausible, state the tradeoff using `references/architecture/tradeoff-guidance.md`.

For L2 subsystems: each submodule selects its own pattern. Document which pattern each module uses, and verify that the patterns are compatible at integration boundaries (e.g., one module's FWFT FIFO output feeding another's registered input -- the latency contract must match).

### 6a. RTL Structural Purity Gate (mandatory for ALL levels, before Step 7)

Read `references/rtl/rtl-structural-purity.md` before writing RTL. Hard design-plan gates (RSP1-RSP7):

- RSP1: FSM sequential = `cstate <= nstate` only. RSP2: FSM combinational = `nstate` + single-bit controls. RSP3: Datapath = no `cstate`/`nstate`/`S_*`. RSP4: Datapath owns counters/addresses/cursors/FIFO/payload/sideband. RSP5: Use named `*_fire`/`*_accept`/`*_en`. RSP6: Explicit unit naming (`_bytes`/`_beats`/`_entries`/`_len`). RSP7: No fake parameterization.
- Waiver required for RSP1-RSP4 exceptions: signal, reason, risk, verification coverage.

### 7. Generate RTL

**Before writing ANY code, read `references/rtl/rtl-coding-standards.md` and `references/rtl/rtl-structural-purity.md`.** This is a hard requirement (not optional). Pay particular attention to M-graded rules: C3 (`default_nettype none`), C5/C6/C7 (FSM/datapath separation), C9/C10 (two-process FSM), C14 (control symmetry), C16 (explicit bit widths), C19 (explicit else), C20 (group registers), and RSP1-RSP7 (structural purity).

Before writing code, read the relevant pattern reference: FSM -> `fsm-examples.md`, FIFO -> `fifo-examples.md` (FWFT for data-path), Pipeline -> `pipeline-examples.md`, Handshake -> `handshake-examples.md`, AXI -> `axi-dma-channel-guidelines.md`, DMA -> `dma-cdma-examples.md`. All under `references/rtl/` or `references/axi-dma/`. Do not rely on memory or training data. If a protocol reference uses "must"/"shall"/"violation", verify whether it is **Normative** or **Conservative pattern** before turning it into RTL.

Before writing RTL, scan `references/debug/bug-pattern-library.md` for the module type and pattern category.

Write synthesizable code following `references/rtl/rtl-coding-standards.md` and `references/rtl/fsm-examples.md`: clear signal names, explicit reset, one driver per signal, no latches, Verilog-first style, two-process FSM, `cstate`/`nstate` naming.

Apply power/timing/area rules from `references/design/power-timing-area.md`: clock-enable over gating (P1), memory access qualification (P5), bit-width discipline (A3), balanced operator trees (A1). For FPGA targets: DSP/BRAM/SRL inference patterns (A4, A5, P6).

**Per-module standalone compile check (mandatory for L2):** Before integrating modules, each .v file must compile standalone as a top-level module:

```bash
for f in <module1>.v <module2>.v ...; do
    iverilog -g2012 -o /dev/null $f || echo "FAIL: $f"
done
```

A module that fails standalone compilation has undeclared dependencies, missing signal definitions, or incomplete logic (NVMe Phase 3 B14: FSM states declared but no state register). Fix before integration. Only after ALL modules pass standalone compilation, proceed to integration.

**Per-module simulation (mandatory for L2):** After standalone compile passes, each module must have its own testbench and pass simulation BEFORE top-level integration. Jumping directly to integration simulation hides per-module bugs and makes debug exponentially harder. For each module: write a focused TB covering reset, normal operation, boundary, and backpressure; run `scripts/run_sim_guarded.py`; run `scripts/sim_log_gate.py` on the log; run `scripts/rtl_style_check.py` on both RTL and TB. Only after ALL per-module simulations pass, proceed to integration TB. Document evidence in `docs/module_verification_matrix.md` and `docs/dev_log.md`. See `references/verification/per-module-simulation-gate.md`.

**Module boundary discipline (PH1):** Prefer registered outputs at module boundaries. Combinational outputs cause glitches during FSM transitions and complicate TB sampling. See `references/advanced/physical-awareness-guidelines.md` PH1.

**Development log (mandatory for L1/L2):** Use `references/project/development-log-template.md`. Start at Step 1, fill as you go. Bug Tracking Table is the single most valuable artifact: record symptom (verbatim FAIL), found-at checkpoint, violated principle, root cause, fix. The "Found at" column tells us which checkpoints catch bugs and which miss them.

**NBA ordering pre-check (mandatory for ALL levels):** Read `references/timing/nba-ordering-guide.md` before writing each `always @(posedge clk_i)` block. Three questions must be answered:
1. **Who reads my output?** If another `always @(posedge clk)` reads it -> cross-block NBA hazard (IEEE 1364 section 5.5).
2. **What am I reading?** Same-block RHS reads old value of a register just `<=` assigned. Correct for counters; wrong for pointer-indexed memory (Trap 1, 2).
3. **Who consumes this combinationally?** `assign`/`always @(*)` readers see pre-NBA value (IEEE 1364 section 5.3).

Fix hazards per `nba-ordering-guide.md` Layer 3 before writing another line.

### 7b. Pre-synthesis check (mandatory for L1/L2)

Run before self-review: `bash scripts/pre_sim_check.sh --all --top <top_module> <files>.v`

Three checks must pass: **yosys** (latch, loop, width), **rtl_style_check** (C3/C19/C21/NBA/N1/RSP/FSM/TB), **iverilog standalone compile** per module. Reject on: `$_DLATCH_*`, combinational loop, rtl_style_check E-level, standalone compile fail. Review and fix W-level warnings. Proceed only after clean exit.

### 8. RTL self-review against skill constraints

Before simulation, review the generated RTL against the full self-review checklist in `references/verification/self-review-checklist.md`. Each item must be explicitly checked and marked pass/fail. For each FAIL item, fix before proceeding and state what was changed. For each [PASS] item, cite the specific line numbers or signal names that satisfy the check -- do not mark items as passed without evidence.

The checklist covers the following categories. Read the reference for the full item list:

| Category | Items | Key References |
|----------|:-----:|----------------|
| **FSM-Datapath Purity** | **7** | **rtl-structural-purity.md RSP1-RSP7** |
| Handshake | 4 | bug-pattern-library.md H1-H8 |
| Data Path | 4 | DP1-DP5, F1 |
| Naming | 4 | naming-guidelines.md |
| RTL Correctness | 9 | correctness-rules.md E1-E8, E1b |
| FSM | 6 | fsm-examples.md, C2-C3, SM1-SM2 |
| Protocol (AXI) | 11 | P4-P13, IHI0022E A3.3 |
| APB | 6 | apb-guidelines.md |
| AXI-Stream | 6 | axi-stream-guidelines.md |
| CDC | 4 | cdc-guidelines.md |
| Integration | 7 | integration-invariants.md, P4 |
| Engineering Intuition | 7 | engineering-intuition-checklist.md |
| Low-Power | 9 | low-power-guidelines.md |
| Physical Awareness | 4 | physical-awareness-guidelines.md |

State the review result: PASS (all items checked) or FAIL (list items fixed).

**Protocol claim ledger (mandatory for AXI/APB/AHB/AXI-Stream/NVMe work):** Every must/shall/violation in contract, RTL comments, assertions, and testbenches must be recorded in the project dev log or a project-local `protocol_claim_ledger.md` using the template at `references/timing/protocol-claim-ledger.md` (that file is a reference template -- do not edit it for project-specific claims). Format: claim text, label (Normative/Project policy/Conservative pattern/Heuristic/Unverified), source doc, section, applied-in file:line, verification evidence. Unlabeled hard claims are unreviewed. See also `references/timing/protocol-authority-audit.md`.

**Signal type cross-check (L1/L2):** Cross-check timing contract signal types (pulse/level/registered) against RTL implementation. Mismatch -> fix trace or RTL before simulation.

**NBA ordering hazard check (L1/L2):** Read `references/timing/nba-ordering-guide.md`. Audit: same-block old-value reads, cross-block sequential dependencies, counter-driven registered outputs, pointer-indexed memory reads, counter advances not gated by valid+ready. Fix hazards -> re-run Step 8.

**Critical limitation:** This checklist verifies STRUCTURAL correctness only. It does NOT verify FUNCTIONAL correctness. Always follow with Step 8b and Step 9.

### 8b. Functional verification plan (mandatory)

**Structural review (Step 8) does NOT guarantee functional correctness.** Before generating TB (Step 9), produce the verification PLAN:

**Golden reference strategy** (see `references/verification/golden-reference-guide.md`): Computation -> known I/O pairs. Algorithm -> software reference model. Register block -> write-readback. Data movement -> end-to-end scoreboard. Control -> invariant checking. Pipeline -> latency verification.

**Scoreboard and audit plan:**
- **Contract-to-test trace**: for L1/L2 and protocol work, read `references/workflow/contract-to-test-trace-gate.md`. Every visible sideband or response field in the contract must map to RTL producer/consumer logic and at least one TB check or documented waiver.
- **Payload scoreboard** for data movers. **Transaction-shape scoreboard** (AWADDR/AWLEN/WLAST/WSTRB/BRESP/completion ordering) for DMA/NVMe. A completion-only TB that checks status/bytes without asserting AWADDR, AWLEN, W beat count, WLAST exact cycle, WSTRB, and BRESP per burst is not acceptable for PASS -- `rtl_style_check.py` TB_COMPLETION_ONLY1 flags this as E-level.
- **Global error counter**: `total_error_cnt` gates `ALL_TESTS_PASS`. Per-test local counters that can be zero while others show errors -> false-pass.
- **False-pass audit plan**: define what evidence in the sim log would reclassify PASS as FAIL (see `references/verification/simulation-loop.md` false-pass detection).

**Minimum test plan:** (1) golden reference per module type, (2) one complete protocol transaction, (3) boundary conditions (empty/full/zero/max), (4) at least one stall test (WREADY=0 >=2 cycles), (5) NVMe/DMA: multi-page transfer with non-uniform data.

**If functional tests fail after structural PASS:**
- Do NOT claim the design is correct
- Debug using golden reference comparison (golden-reference-guide.md) then first-divergent-cycle reasoning (simulation-loop.md Phase 4)
- Re-run Step 8 self-review after each fix (debug-driven fixes often introduce new structural violations)

### 8c. Principle check -- Known Values and Output Discipline (P3, P5a, P5b)

**Note:** P1/P2 were reviewed at Step 5a. P4/P6 were reviewed at Step 2a. Step 8c covers the principles that require actual RTL code to review.

Read `references/design/design-principles.md` P3, P5a, P5b.

**Complexity gate (same three-tier as Step 1):**

| Level | Review scope | Format |
|:-----:|-------------|--------|
| **L0: Trivial** | **P3 only** (register audit). Skip P5a/P5b. | 1 paragraph in dev log, no separate file |
| **L1: Leaf** | P3 + **P5a** (Output Discipline). Skip P5b. | 1-2 questions each. `principle_review_8c.md` |
| **L2: Subsystem** | P3 + P5a + **P5b** (Physical Implementation). | 3-5 questions each. Signal tracing required. `principle_review_8c.md` |

**Why P5 was split:** R5-R8 found ZERO P5 issues -- the principle mixed output discipline (always applicable) with physical implementation (ASIC-only). Agents marked NA. Split ensures every module gets the applicable part.

**P3 (Known Values):** Generate design-specific questions about register initialization. Scan your `always @(posedge clk)` blocks. Does every register have an explicit reset? Any unreset arrays or memories? Can any register reach an unexpected state (seed=0, counter wrap, shift register all-zeros)? Are all combinational signals driven by exactly one source?

**P5a (Output Discipline -- always applicable for L1/L2):** Generate design-specific questions about output quality:
1. Are all module boundary outputs driven from registers (not combinational `case(cstate)`)? Combinational outputs cause glitches during FSM transitions and complicate testbench sampling. See PH1.
2. Are internal counters gated by state (not free-running when idle)? Free-running counters burn power and can wrap unexpectedly.
3. Are bit widths derived from `$clog2` (not hardcoded)? Hardcoded widths create silent bugs when parameters change.
4. Is the baud/divider counter's terminal count correct (counts DIVIDER cycles, not DIVIDER+1)?

**P5b (Physical Implementation -- L2/ASIC only):** Power gating sequences, DVFS timing, isolation/retention, fanout, placement. See `references/design/design-principles.md` P5b for active-search questions. Skip for FPGA targets and L0/L1 modules.

**Output format:** Design-specific questions citing YOUR signal names and line numbers. See Step 5a for the good/bad example.

**Fix discipline** (applies to all findings at any checkpoint):

| Priority | Strategy | What to try |
|:--:|------|-------------|
| **1** | **Delete** | Remove redundant registers, unused states, dead code |
| **2** | **Retime** | Move signal earlier/later, reorder state transitions |
| **3** | **Constrain** | FSM guard (`!busy`, gating), enable qualification |
| **4** | **Add** | Hardware as last resort -- document why 1-3 don't work |

### 9. Generate testbench, run simulation, execute audit

**1. Generate testbench and assertions.** Provide: testbench skeleton, directed test list, assertions, waveform checkpoints. For AXI: use `references/verification/axi-verification.md`. Before writing TB: read `references/verification/icarus-common-pitfalls.md` (15 Icarus-specific pitfalls) and use `references/verification/tb-examples.md` standard skeleton. TB must follow output protocol: `RESET_RELEASED`, `TEST_START/PASS/FAIL <id>`, `ALL_TESTS_PASS`, `SIMULATION_DONE`.

**2. Run simulation loop.** Use `scripts/run_sim_guarded.py` as the recommended vvp wrapper (timeout, VCD/log size limits, UTF-8-safe output). Follow `references/verification/simulation-loop.md`: compile -> simulate -> analyze -> fix -> re-sim, max 3 iterations. Do NOT run bare `vvp` -- use the guarded wrapper.

**L2 per-module simulation gate:** Do NOT proceed to integration TB until each submodule has its own TB that passes `scripts/sim_log_gate.py` and `scripts/rtl_style_check.py`. Integration-only simulation is a verification blind spot -- per-module bugs become integration bugs that are harder to triage. Document each module's pass status in `docs/module_verification_matrix.md` and `docs/dev_log.md` before writing the integration TB. `scripts/pre_integration_gate.py` enforces this: integration TB or sim artifact before per-module evidence = FAIL. See `references/verification/per-module-simulation-gate.md`.

- Compile fail -> fix Verilog syntax/connectivity -> re-run Step 7b -> return to Step 9.
- Sim fail -> Phase 4 (principle-driven debug): categorize failure, map symptom to P1-P5a, match bug pattern, minimal fix -> re-run Step 8 on changed code -> re-run 7b -> return.
- Max 3 iterations. 4th failure -> stop and request human review.

**3. Execute false-pass audit before claiming PASS.** `ALL_TESTS_PASS` present -> do NOT accept. Run Step 8b audit: scan entire log for undetected `exp`/`mismatch`/`xxxx` without `error_cnt++`. If found -> classify as FALSE_PASS, fix TB, re-sim. Only report PASS after audit confirms no hidden evidence. See simulation-loop.md false-pass detection.

**Phase 4 -- Principle-driven debug:** Categorize failure (compile/infrastructure/functional). Map to principle: P1 (timing), P2 (FSM), P3 (register), P4 (independence), P5a (output). Match `references/debug/bug-pattern-library.md`. Apply fix discipline: Delete -> Retime -> Constrain -> Add. Re-run Step 8 on changed code.

### 10. Finalize

After simulation passes AND false-pass audit is clean, state maturity level and residual risks via `references/verification/engineering-review-checklist.md`.

**Finalization gates (all must pass before claiming PASS):**
- [ ] `scripts/rtl_style_check.py` clean or all findings have written waivers
- [ ] `scripts/compile_log_gate.py` exits 0 on the compile log (rejects empty logs)
- [ ] `scripts/sim_log_gate.py` exits 0 on the actual simulation log
- [ ] `scripts/project_artifact_gate.py` exits 0 on the project directory
- [ ] `scripts/project_preflight_gate.py` exits 0 (skeleton created at Step 1.2 and maintained)
- [ ] `scripts/pre_integration_gate.py` exits 0 (L2: no integration sim before per-module evidence)
- [ ] `scripts/final_delivery_gate.py` exits 0 on the project directory (includes pre-integration, runtime/runaway guard)
- [ ] **L2: per-module simulation evidence.** Each submodule has its own TB pass recorded in `docs/module_verification_matrix.md` before integration TB was written
- [ ] **L2: delegation provenance.** Delegate: yes requires role reports with provenance fields (Role, Scope, Input contract, Evidence source, Acceptance commands, Findings/decision)
- [ ] **L2: RSP2 E-level.** FSM combinational block assigning multi-bit datapath/sideband is hard error for L2 projects
- [ ] No runaway VCD (>50MB) or missing sim log; VCD off by default, enabled only during debug; use `scripts/run_sim_guarded.py`; L1/L2 code-only delivery rejected
- [ ] **Standard log artifact required:** .log files from run_sim_guarded.py for compile and sim evidence; bare vvp without log capture is not acceptable
- [ ] **Contract-implementation matrix done:** `docs/contract_implementation_matrix.md` maps every contract item to RTL producer/consumer, TB check, and waiver if unverified. For NVMe/DMA/AXI, matrix must cover: PRP role/list, SLBA->NVM source address, host destination AWADDR, AWLEN/WLAST/WSTRB/BRESP, completion status/bytes, response propagation. See `references/workflow/contract-implementation-gate.md`.
- [ ] **Scoreboard substance:** DMA/NVMe TBs that mention AWADDR/AWLEN/WLAST/WSTRB/BRESP must compare against expected values; signal-name mention alone is not scoreboard evidence
- [ ] NVMe PRP-list support claimed only if PRP2 list entries are actually fetched, or explicitly documented as an Accepted Limitation with no PASS claim
- [ ] AXI W data source contract checked: WVALID may present FIFO-backed data only after empty/count/have-data/full-burst availability is proven
- [ ] **Transaction-shape scoreboard** for DMA/NVMe: TB must assert AWADDR, AWLEN, W beat count, WLAST exact cycle, WSTRB, BRESP per burst. Completion-only TB is not acceptable for PASS.
- [ ] **Dev log residual risks classified:** Blocking Gap / Accepted Limitation / Residual Risk. No unwaivered blocking gaps when Status: PASS. No unchecked compensation-gate boxes.
- [ ] Simulation log audited -- no undetected `exp`/`mismatch`/`xxxx`
- [ ] DMA/NVMe: multi-page continuity verified, protocol response inputs used in completion status
- [ ] RSP1-RSP7 re-checked on all changed files; waivers still valid
- [ ] Debug anti-patterns checked: WVALID gating, FIFO output mode, `_d` shadow datapath, read/write coupling, dead ports

## Debugging rules

Failure -> match against `references/debug/bug-pattern-library.md` patterns first. Cite pattern ID + root cause + minimal fix. No match -> first-divergent-cycle reasoning.

## Testbench guidance

Generate small but targeted TB: reset, one normal transaction, one backpressure, one boundary, one corner case. Prefer `$fatal`/error counters over waveform-only stimulus. Combinational outputs (PSLVERR, HRDATA, PREADY) valid only DURING transaction -- check with `#delay` after enabling signal, not after completion. See `references/bus/apb-guidelines.md`.

## Underspecified requests

Use `references/architecture/requirement-extraction-template.md`. Classify dimensions as Required/Implied/Assumed/Unknown. Ask only questions that block correct RTL. No full design from guesswork for complex protocols.

## Skill success

Readable synthesizable RTL for standard patterns. Cycle-level timing without hand-waving. Missing requirements surfaced early. Code paired with verification plan.
