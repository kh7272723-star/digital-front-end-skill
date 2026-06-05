# Claude Code Development Memory

This workspace develops `digital-front-end-skill`.

## Current Priority

Latest 2026-06-04 storage-project review iteration:

- Pending observation for the next iteration after all current projects return:
  agents do not reliably execute long skill workflows end-to-end. The recurring
  failure mode is not random hallucination; it is "compliance theatre":
  writing the right process words (`Delegate: yes`, `PASS`, `Verified`,
  "TB checks backpressure") without executable evidence. Treat long workflow
  adherence as an unreliable model behavior that must be enforced by external
  state files and fail-closed gates.
- Candidate workflow simplification: keep `SKILL.md` as a thin mandatory state
  machine and move long explanations into references. Convert as many
  mandatory steps as possible into scripts that check real artifacts. The main
  path should say: create skeleton -> freeze contracts -> run preflight ->
  module evidence -> integration -> final delivery gate. Anything not backed by
  a file/log/marker should not count as PASS evidence.
- Candidate evidence-first rule: final summaries, dev-log claims, and matrix
  rows are not evidence. Evidence must be bound to actual project files:
  `docs/module_verification_matrix.md`, `docs/subagents/*.md` with provenance,
  standard compile/sim `.log` files, and TB/sim markers that match matrix test
  IDs or names. A project summary must be treated as report text only.
- Candidate checks from the latest NAND review:
  pre-integration gate should detect extensionless Icarus outputs such as
  `sim/tb_nand_page_ctrl`; verification matrix closure should compare planned
  "Test N: name" rows against `TEST_START/PASS N: name` markers; sim log gate
  should allow expected timeout test names while still rejecting wrapper
  `RUN_SIM_GUARDED: TIMEOUT`; TB requirements must include completion
  backpressure (`cmp_valid_o && !cmp_ready_i`) and FIFO full/empty stall tests.
- Candidate checks from the latest DMA review:
  final gates must reject planned-but-unexecuted matrix rows (for example
  T3/T4/T5/T6/T8/T10 only in docs), hardwired WSTRB in movers that claim
  unaligned support, disconnected RRESP/RD error propagation, completion byte
  counters sourced from addresses, and single-entry B tracking hidden behind an
  outstanding-depth parameter. For DMA/NVMe-like movers, shape scoreboard must
  check ARADDR/ARLEN/AWADDR/AWLEN/WSTRB/WLAST/BRESP/RRESP/cpl_bytes, not only
  completion tag/status.
- Candidate checks from the latest NVMe review:
  require invalid-command completion tests (for example invalid NSID must produce
  a completion instead of an unlatched error pulse), PRP1 non-zero offset tests
  that check AWADDR/WSTRB/byte count, public PRP-list load interface tests
  instead of hierarchical `dut.*.list_buf_q` writes, real external error
  injection instead of TB `force/release`, and protocol claim ledgers with
  non-TBD evidence. Reject docs that claim T10/T11/WSTRB coverage when those
  markers/checks are absent from TB/sim logs.
- Network/API recovery note: the attempted Claude execution for the second
  storage hardening iteration exited with `API Error: Unable to connect to API
  (ConnectionRefused)`. Codex completed the deterministic patch and audit
  directly. Do not record this iteration as a completed Claude execution unless
  a later Claude run actually edits and passes gates.
- Pre-integration gate should ignore ordinary compile/build logs when deciding
  whether integration simulation has started. Treat integration TBs, `.vvp`
  run targets, and simulation logs as integration evidence; do not flag
  `compile.log` by itself.
- PRP list support evidence must be real RTL behavior: list memory declaration
  or reads are not enough. Require a list-memory write, list load/write/fetch
  interface, or AR fetch channel. PRP1 non-zero offset claims must have usable
  offset handling, not just alignment rejection.
- Keep level inference consistent across preflight, artifact, pre-integration,
  and final-delivery gates. Artifact-based L2 evidence includes rtl >=3,
  top module instantiating >=2 distinct leaf modules, or storage protocol +
  AXI multi-protocol signals.
- L2 projects require per-module simulation/proof before integration. Create
  `docs/module_verification_matrix.md` and list every `rtl/*.v` module with
  passing in-project evidence logs or a narrow waiver. Top-level simulation
  does not replace module-level evidence.
- `project_artifact_gate.py` must reject L2 final PASS if the module
  verification matrix is missing, incomplete, points outside the project, or
  references logs without PASS evidence.
- `sim_log_gate.py` may ignore guarded-wrapper command metadata such as
  `RUN_SIM_GUARDED: command=... timeout=30s`, but must reject real
  `RUN_SIM_GUARDED: TIMEOUT` or `RUN_SIM_GUARDED: FAIL`.
- `rtl_style_check.py` separates TB and RTL concerns: TB false-pass checks still
  run on testbenches; RSP FSM/datapath purity applies only to synthesizable RTL.
- After Claude edits, always run automatic gates and let Codex audit key diffs
  before sync/global install. Do not treat Claude's textual success summary as
  acceptance evidence.

The latest iteration is driven by the `nvme-io-path` review on 2026-06-02.
The review found two recurring skill failures:

- RTL generation still drifts into mixed FSM/datapath code.
- NVMe/DMA verification can false-pass when only payload data is checked.

Treat these as top-priority gates for future skill edits and evals.

- L2 projects MUST pass through the Delegation Decision Gate (Step 1.1) AND Release Gate (Step 1.6).
  Decision record required: delegate yes/no, roles or waiver, contract-freeze status.
  Release Gate: per-module contracts frozen, roles assigned, acceptance commands defined,
  integration reviewer assigned, prompt includes RSP1-RSP7 + protocol authority labels.
  Sub-agent execution must not start before both gates are cleared.
  See `references/architecture/sub-agent-delegation.md` for the decision matrix and templates.

- Maintain SKILL.md headroom. Current target: <=460 lines. Move details to references,
  never cram everything into the main file. Use `references/workflow/task-mode-routing.md`
  to route review/debug/protocol-audit requests away from the full RTL pipeline.

- SKILL.md must remain English-only and encoding-stable. No Chinese CJK characters,
  no mojibake, no non-ASCII technical glyphs (arrows, checkmarks, em dashes, curly
  quotes, Unicode inequality operators). Use ASCII equivalents: ->, <=, >=, PASS, --.

- `SKILL_CHANGELOG.md` 作为人类开发日志应保持中文为主，技术 token（文件路径、脚本名、规则 ID、PASS/FAIL 等）保留英文。

- SPEC Consistency Gate (Step 1.7): verify formulas (NLB+1, PRP1 offset, PRP2 boundary,
  AWLEN=beats-1, byte-to-beat conversion) before any timing contract. See
  `references/workflow/spec-consistency-gate.md`.

- Executor output still needs independent audit. The 2026-06-02 SPEC/TB iteration
  initially missed `tb_nvme_io.v:247` (`while (!_done) begin`) and introduced a
  bad reference note (`16'h0F` incorrectly described as 21). Always run the
  agreed gate commands and inspect high-risk diff before declaring completion.

## Hard Rules Added

- Read `references/rtl/rtl-structural-purity.md` before RTL generation or RTL review.
- Enforce RSP1-RSP7:
  - FSM sequential block updates only `cstate`.
  - FSM combinational block emits only `nstate` and single-bit controls.
  - Datapath sequential blocks must not reference `cstate`, `nstate`, or `S_*`.
  - Datapath updates use named accepted-operation controls.
  - Bytes, beats, entries, and AxLEN units are named explicitly.
  - Parameterized capacity must not be locally hardcoded without waiver.
- For NVMe/DMA, require payload scoreboard plus transaction-shape scoreboard.
- Do not treat `ALL_TESTS_PASS` as proof until the log is audited for false-pass evidence.
- Protocol hard claims (`must`, `shall`, `protocol violation`) need a source label:
  Normative, Project policy, Conservative pattern, Heuristic, or Unverified.

## 2026-06-03 Low-Constraint NVMe Regression Memory

- Low-prompt/no-SPEC NVMe runs must still create canonical artifacts under
  `docs/`: `docs/dev_log.md`, `docs/SPEC.md`, `docs/interface-contracts.md`,
  `docs/timing-contract.md`, `docs/protocol_claim_ledger.md`,
  `docs/verification_matrix.md`, and `docs/contract_implementation_matrix.md`.
  `docs/dev_log.md` is evidence chain only.
- PRP2 role is mutually exclusive: direct data page OR PRP list pointer. In list
  mode PRP2 is not a data page. A 16KB/4-page test needs PRP1 plus three PRP
  list data entries and AWADDR checks for every page.
- Treat multiple procedural drivers as a hard RTL error. The regression example
  is `axi_wr_engine.b_error_q` assigned in two `always` blocks.
- Display-only `FALSE-PASS AUDIT` sections are fake audits. Require conditions,
  assertions, `$fatal`, check tasks, or error-count updates in the audit region.
- `ALL_TESTS_PASS` is not credible with compile warnings, unwaived checker
  findings, missing X/Z checks, or unchecked sidebands such as `busy` and
  `cpl_bytes_written`.
- `TIMEOUT` + `$finish` (no `$fatal`) = false pass. Process exit code is 0.
  `scripts/sim_log_gate.py` rejects this. `TB_TIMEOUT_FATAL1` flags it.
- Claim ledger evidence (T3, T10, etc.) must cross-check against actual TB files.
  `scripts/project_artifact_gate.py` automates this.
- `docs/verification_matrix.md` is mandatory for L1/L2 No-SPEC projects.
- Comment-only RSP3 compliance is invalid. Checker upgrades to E-level if file
  claims compliance but code violates.
- Simulation logs may be UTF-16/NUL-interleaved when captured by PowerShell.
  `sim_log_gate.py` reads bytes and normalizes before scanning.
- Phrases such as "No user spec provided" mean No-SPEC. Do not treat them as
  affirmative evidence that an external user SPEC exists.

## 2026-06-03 Delegation Evidence + Contract-Implementation + Residual Risk Hardening

- L2 Delegate: yes must produce `docs/delegation_plan.md` and subagent role reports
  under `docs/subagents/`. Without these, `project_artifact_gate.py` rejects PASS.
- L1/L2 No-SPEC must produce `docs/contract_implementation_matrix.md` mapping every
  contract item to RTL producer/consumer, TB check, and waiver. For NVMe/DMA, matrix
  must cover PRP, SLBA source, destination AWADDR, AWLEN/WLAST/WSTRB/BRESP,
  completion, and response propagation.
- All residual risks in dev_log must be classified as Blocking Gap / Accepted
  Limitation / Residual Risk. `Status: PASS` with unwaivered blocking gaps is
  rejected by `project_artifact_gate.py`.
- Completion-only TB (status/bytes without AWADDR, AWLEN, WLAST, WSTRB, BRESP)
  is not acceptable for DMA/NVMe PASS. TB_COMPLETION_ONLY1 flags as E-level.
- `rtl_style_check.py` RTL_MULTI_DRIVER1 fixed: relational <= inside conditions
  no longer false-positive. C17_ARR1 detects unpacked reg arrays. PRP_STUB1
  detects PRP AR channel tied off. ERR_STUB1 detects error outputs always 0.
- No-SPEC artifact paths are canonical under `docs/`.

## 2026-06-03 Empty-Docs + Stubbed PRP + Width-Bound Compile-Warning Hardening

- `docs/` empty with no dev_log is a hard failure. `project_artifact_gate.py` now infers
  L2 from project complexity (>=3 rtl/*.v, NVMe+AXI signals, tb/ + rtl/ directories)
  when dev_log is missing, ensuring multi-module projects don't default to L1.
- PRP walker comments/logic containing "Simplified", "would fetch from PRP2 list",
  or PAGE_SIZE stepping are detected by `rtl_style_check.py` PRP_STUB2/PRP_LIST_FAKE1
  (E-level). Stubbed PRP logic that claims PRP support is a Blocking Gap.
- AXI W data paths must prove FIFO/data availability before presenting WVALID.
  `rtl_style_check.py` AXI_WDATA_SOURCE1 flags FIFO-backed WDATA without
  !empty/count/have-data/full-burst contract as E-level.
- Datapath/output logic must not directly decode `cstate`/`S_*`. RSP3 is E-level
  for cstate in non-state sequential datapath blocks; RSP4 is E-level for direct
  cstate-decoded output/datapath assignments.
- Part-select on narrow parameters (e.g. `PAGE_SIZE[63:0]` when PAGE_SIZE is 32-bit)
  is detected by `rtl_style_check.py` WIDTH_BOUND1 (W-level). Icarus replaces
  out-of-bound bits with `'bx` — this is a compile warning that must be a hard failure.
- `compile_log_gate.py` rejects hard compile/elaboration warnings/errors. Inherited
  timescale warnings alone are non-blocking.
- `final_delivery_gate.py` aggregates project artifacts, RTL style, compile logs,
  and simulation logs. Code-only delivery and textual success summaries are not PASS.
- `final_delivery_gate.py` Step 5 runtime guard: rejects VCD>50MB, log>20MB,
  excessive VCD count, missing sim log. VCD off by default, enable only for debug.
- `compile_log_gate.py`: rejects numeric truncation (24'd16777216->0), out-of-bound
  part-select with 'bx injection. Encoding-safe output on Windows.
- `project_artifact_gate.py`: delegation parsing handles **Delegate:** markdown bold;
  evidence token search covers sim/tb_*.v; rejects TBD/blank docs with Status: PASS.
- `rtl_style_check.py` RSP2: single-bit enables with _cnt_ in name (e.g.
  byte_cnt_ld_en_o) no longer false-positive as multi-bit datapath.
- PRP_STUB/PRP_LIST_FAKE restricted to RTL files only (skip testbench files).
- `project_preflight_gate.py`: pre-RTL skeleton check (docs/, rtl/, tb/, sim/).
  Fail-closed. Complements final `project_artifact_gate.py`.
- `run_sim_guarded.py`: guarded vvp wrapper (timeout, VCD/log size limits, UTF-8-safe
  output). Use instead of bare vvp in Step 9. It must not forge `ALL_TESTS_PASS`;
  PASS markers come from the testbench log only. VCD/log size overflow returns
  nonzero (RC=3) and writes `RUN_SIM_GUARDED_FAIL` into the log so sim_log_gate
  rejects even if the child testbench already printed PASS markers.
- Task mode routing is now Step 0 (before Standard Workflow). Review/Debug/
  Protocol-Audit modes do not enter the full RTL design pipeline.
- Review mode is gate-first: artifact/style/compile/sim/runtime evidence first,
  then manual hotspot review.
- Contract implementation matrix skeleton is created at Step 3 (contract freeze),
  not reconstructed at finalization.
- Evals 97-99 cover workflow routing gate-first review, No-SPEC skeleton
  preflight, and guarded simulation timeout/size behavior.

## Verification Commands

Use these before reporting the skill as updated:

```powershell
python scripts\skill_static_check.py
python -m py_compile scripts\rtl_style_check.py
python -m py_compile scripts\sim_log_gate.py
python -m py_compile scripts\project_artifact_gate.py
python -m json.tool evals\evals.json
python -m json.tool evals\benchmark.json
python scripts\eval_benchmark_check.py
python scripts\rtl_style_check.py <rtl-file-under-review>
python scripts\sim_log_gate.py <sim_log_file>
python scripts\compile_log_gate.py <compile_log_file>
python scripts\project_preflight_gate.py <project_dir>
python scripts\project_artifact_gate.py <project_dir>
python scripts\final_delivery_gate.py <project_dir>
python scripts\run_sim_guarded.py --timeout-sec 30 --log sim\sim.log -- vvp sim\top.vvp
```

Known regression check:

```powershell
python scripts\rtl_style_check.py D:\skill管理\ic-design-skill\nvme-io-path\rtl\prp_walker.v
```

Expected result: nonzero exit with warnings including `RTL_PRP1`,
`RTL_STRUCTURAL_PURITY_RSP2`, and `RTL_STRUCTURAL_PURITY_RSP3`.

## 2026-06-04 Recovery Note

The previous Claude execution was interrupted by machine power loss/API
connection failure after partially writing the runtime-guard iteration. Codex
audited the partial diff and completed two follow-up fixes:

- Gate scripts now force UTF-8-safe stdout/stderr. `final_delivery_gate.py`
  also runs child gate scripts with `PYTHONIOENCODING=utf-8`, so Chinese
  workspace paths remain readable in aggregated output.
- `rtl_style_check.py` reports `RTL_STRUCTURAL_PURITY_RSP1` as E-level, not
  W-level. Any sequential block that assigns `cstate` plus datapath/output
  registers is a hard FSM/datapath purity failure.
- `final_delivery_gate.py` style discovery scans `sim/tb_*.v` as well as
  canonical `tb/`, so completion-only false-pass checks still run when a
  project places TBs under `sim/`.

Regression evidence after recovery:

- `python -m py_compile` on modified gate scripts: PASS
- `python scripts\skill_static_check.py`: PASS
- `python scripts\compile_log_gate.py` smoke test: PASS
- `python scripts\eval_benchmark_check.py`: PASS
- DMA artifact gate now parses `**Delegate:** no`; it fails only on missing
  compensation-gate evidence, as intended.
- NAND compile log gate rejects the `24'd16777216` truncation warning.
- NVMe final delivery gate rejects missing docs, non-canonical `sim/tb_*.v`,
  RSP1/RSP4 violations, compile x injection, missing sim log, and 102MB VCD.

- Executor output still needs independent audit. The 2026-06-02 SPEC/TB iteration
  initially missed `tb_nvme_io.v:247` (`while (!_done) begin`) and introduced a
  bad reference note (`16'h0F` incorrectly described as 21). Always run the
  agreed gate commands and inspect high-risk diff before declaring completion.

## 2026-06-04 L2 Storage Project Review — Second Iteration: Five P0 + Five P1 Hardening

Codex reviewed three L2 storage projects and found agents still bypassing gates:

1. **Pre-integration simulation lock.** Agents run integration TB before per-module evidence.
   Fix: `scripts/pre_integration_gate.py` (new), integrated into `final_delivery_gate.py` Step 1b.
   Detects integration TBs and sim artifacts before per-module evidence exists.

2. **False delegation provenance.** `Delegate: yes` role reports exist as empty shells.
   Fix: `project_artifact_gate.py` `_check_role_report_provenance()` validates six provenance
   fields: Role, Scope, Input contract, Evidence source, Acceptance commands, Findings/decision.

3. **L2 auto-classification hardening.** DMA incorrectly classified as L1 when dev_log omits Level.
   Fix: artifact-based L2 inference (rtl >=3, top+>=2 leaf, multi-protocol) runs always and
   overrides silent dev_log. Applied to both `project_artifact_gate.py` and `project_preflight_gate.py`.

4. **RSP2 L2 hard error.** FSM combinational block assigning multi-bit datapath signals was W-level
   even for L2 projects. Fix: `rtl_style_check.py` `--level L2` escalates RSP2 to E-level.
   `final_delivery_gate.py` detects level and passes `--level` to rtl_style_check.

5. **Verification matrix evidence closure.** Matrix entries only checked for doc mentions, not
   TB/sim execution evidence. Fix: `project_artifact_gate.py` checks TB source and sim logs
   separately; doc-only mentions are not evidence; planned-only needs NOT_RUN/WAIVED.

6. **Empty compile log gate.** `compile_log_gate.py` now fails on empty/whitespace-only logs.

7. **Expected timeout allowance.** `sim_log_gate.py` distinguishes expected timeout-protection
   test text (TEST_PASS.*timeout, status=TIMEOUT) from real RUN_SIM_GUARDED: TIMEOUT.

8. **Standard log artifact requirement.** `final_delivery_gate.py` rejects .vvp without .log.

9. **Scoreboard substance gate.** `project_artifact_gate.py` rejects signal-name mentions as
   scoreboard evidence for DMA/NVMe AWADDR/AWLEN/WLAST/WSTRB/BRESP.

10. **PRP feature claim gate.** `project_artifact_gate.py` rejects list_mem without load/fetch
    interface and PRP1 non-zero offset claim without RTL logic.

## Recent Files Changed

- `scripts/project_artifact_gate.py`
- `scripts/pre_integration_gate.py`
- `scripts/run_sim_guarded.py`
- `SKILL_CHANGELOG.md`
- `CLAUDE.md`

## 2026-06-04 Storage Evidence Binding + Gate Hardening (Third Iteration)

Codex reviewed NAND/DMA/NVMe storage projects and found agents still bypassing
evidence requirements through empty claim ledger entries, missing storage-specific
TB checks, and extensionless Icarus artifacts slipping past pre-integration gates.

1. **Protocol Claim Ledger Evidence Gate.** `project_artifact_gate.py`
   `check_protocol_claim_ledger_evidence()` rejects protocol_claim_ledger.md rows
   with blank/TBD/placeholder Evidence when project claims PASS. Evidence must bind
   to real TB files or sim logs.

2. **Storage Mover Evidence Gate.** `project_artifact_gate.py`
   `check_storage_mover_evidence()` requires specific TB evidence for DMA/NVMe features:
   - WSTRB/unaligned claims need TB comparing expected_wstrb.
   - RRESP/RD error propagation needs TB check, not just BRESP.
   - Completion bytes (cpl_bytes) need comparison check.
   - PRP list support needs public interface exercise (list_buf_wr_en/list_buf_idx/
     list_buf_data), not hierarchical dut.* writes.
   - T10/T11/WSTRB/shape coverage claims need corresponding TB markers.

3. **Extensionless Icarus Artifact Detection.** `pre_integration_gate.py`
   `_find_integration_sim_artifacts()` now detects extensionless Icarus outputs
   (e.g. sim/tb_nand_page_ctrl) as integration artifacts when they match tb_*/top_*
   naming patterns. Ordinary compile/build logs still excluded.

4. **Windows .vvp Execution Fix.** `run_sim_guarded.py` prepends `vvp` to .vvp
   commands on Windows. Linux behavior unchanged.

5. **Codex audit补漏.** After Claude's first pass, Codex tightened
   `project_artifact_gate.py` so PASS-claim detection also reads
   `verification_matrix.md`, project summaries, and sim logs; PRP list public
   interface evidence requires active write/fetch stimulus and explicitly flags
   hierarchical `dut.*.list_buf_q` writes; invalid NSID/invalid-command handling
   now requires completion/status TB evidence.

### Files modified in this iteration

- `scripts/project_artifact_gate.py` — check_protocol_claim_ledger_evidence + check_storage_mover_evidence
- `scripts/pre_integration_gate.py` — extensionless Icarus artifact detection
- `scripts/run_sim_guarded.py` — Windows .vvp fix
- `SKILL_CHANGELOG.md` — iteration entry
- `CLAUDE.md` — this section

## 2026-06-04 L2 Storage Project Review — Five Fixes

Codex reviewed two L2 storage projects and found five recurring failures:

1. **No per-module simulation.** Both projects jumped to top-level integration
   simulation. Per-module bugs became integration bugs that were harder to triage.
   Fix: SKILL.md Step 7 now mandates per-module simulation for L2 before
   integration. simulation-loop.md has a new "Per-Module Simulation" section.
   Step 10 finalization gates include per-module evidence check.

2. **Delegation artifacts missing.** Gate already catches `Delegate: yes` without
   `docs/delegation_plan.md` and `docs/subagents/*.md`. Kept as-is.

3. **FSM/datapath purity violations at integration.** Datapath sequential blocks
   directly read cstate/S_*. rtl_style_check.py RSP3/RSP4 checkers exist but
   need to be run per-module BEFORE integration, not only at final review.
   SKILL.md Step 7b and Step 9 now emphasize per-module rtl_style_check.

4. **Weak contract/test evidence.** Two sub-issues:
   - DMA verification_matrix promised transaction-shape tests but TB only had
     integration tests. (Existing TB_COMPLETION_ONLY1 checker catches this.)
   - NAND verification_matrix used T1-T8 but TB used descriptive names like
     test_reset/test_page_read. project_artifact_gate.py now cross-checks
     verification_matrix.md test-name references against TB files.

5. **Tooling false positives/negatives:**
   - sim_log_gate.py rejected `RUN_SIM_GUARDED: ... timeout=30s` metadata as
     TIMEOUT. Fixed: benign line prefix filter skips wrapper metadata.
   - rtl_style_check.py MULTI_DRIVER1 false-positive on `$display("data=%h")`
     because the `=` in the format string matched the LHS assignment regex.
     Fixed: `_strip_string_contents()` helper removes string literals before
     LHS regex matching.
   - rtl_style_check.py TB_FPASS1 false-positive on `$display("exp=%h")`
     because "exp" in format string triggered the false-pass pattern.
     Fixed: regex narrowed to match only "mismatch" (strong false-pass
     indicator), not "exp"/"expected" (benign format labels).

### Files modified in this iteration

- `scripts/sim_log_gate.py` — benign prefix filter for FAIL_PATTERNS
- `scripts/rtl_style_check.py` — _strip_string_contents helper, TB_FPASS1 regex narrowed
- `scripts/project_artifact_gate.py` — check_verification_matrix_evidence + _collect_tb_content refactor
- `SKILL.md` — per-module simulation gate (Steps 7, 9, 10), compressed to 456 lines
- `references/verification/simulation-loop.md` — Per-Module Simulation section
- `references/workflow/contract-to-test-trace-gate.md` — verification matrix test-name cross-check
- `CLAUDE.md` — this section
- `SKILL_CHANGELOG.md` — iteration entry
