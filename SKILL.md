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

## What this skill should not pretend to do

- Do not claim correctness for complex protocol logic without verification.
- Do not silently invent interface semantics when requirements are underspecified.
- Do not replace CDC review, formal signoff, or engineering judgment.
- Do not produce 'clever' RTL if a plain, readable template is safer.
- Do not answer timing questions with generic prose when a cycle-level contract is required.
- Do not generate monolithic full-system RTL from an underspecified subsystem prompt.
- Do not present directed simulation as signoff or proof of correctness.

## Operating principles

1. Start by extracting the design contract. If anything critical is missing, ask before writing code.
2. Prefer explicit structure over compactness. Separate combinational and sequential logic. Use defaults to avoid latches.
3. Make timing visible. Describe what changes on the current cycle and what is registered to the next cycle.
4. Verify the design path. When generating RTL, also generate a verification plan with directed tests.
5. When debugging, work from evidence. Use compiler/lint errors, sim logs, wave behavior, and assertions as the source of truth.

## Authority-to-rule synthesis

Treat standards and methodology documents as source material, not as answer text. Hierarchy: (1) user-provided spec, (2) Verilog/SystemVerilog standards, (3) vendor/methodology guidance, (4) established synchronous design practice, (5) this skill's local examples. See `references/timing/authority-synthesis.md`.

## Reference materials

Read `references/reference-index.md` for a task-to-reference mapping. Key directories:

- **Timing/protocol**: `references/timing/` — timing semantics, contracts, naming, protocol rules, cycle traces, clock/reset
- **Architecture**: `references/architecture/` — hierarchy, system contracts, integration invariants, tradeoffs, staged bring-up, pipeline design patterns, memory hierarchy & buffer strategy, performance analysis
- **AXI/DMA**: `references/axi-dma/` — AXI full/Lite/Stream, DMA channel guidelines, CDMA examples, outstanding rules
- **Bus protocols**: `references/bus/` — APB, AHB-Lite
- **RTL patterns**: `references/rtl/` — coding guidelines, FSM examples, FIFO examples, handshake examples, pipeline examples, naming conventions, correctness rules (multi-driven, latch, width, blocking/nonblocking, reset, loops, implicit wires)
- **Specialized patterns**: `references/patterns/` — arbiters, credit-based, rate-limiter, retry buffer, CRC, ECC, width converter, frame assembler, multi-bank memory, CAM
- **Verification**: `references/verification/` — verification guidance, TB examples, assertion examples, coverage models, formal properties, UVM templates, AXI verification (BFM, scoreboard, coverage), simulation loop (lint→compile→simulate→fix), engineering review checklist
- **Debug**: `references/debug/` — debug cases, bug pattern library
- **Existing project**: `references/project/` — project adaptation, brownfield guidance, large module guidance
- **CDC/synthesis**: `references/synthesis/` — CDC guidelines, constraint guidance, synthesis guidance, toolchain closure, formal verification
- **Advanced**: `references/advanced/` — low-power, DFT, UVM, physical awareness
- **Design intuition**: `references/design/` — design heuristics, tool-driven workflow, power/timing/area rules (low-power RTL, timing closure, resource optimization)

## Coding rules (mandatory)

**首要编码规范：** 所有 RTL 代码必须遵守 `references/rtl/rtl-coding-standards.md`。该文档整合了项目编码规范（M/S/R 三级）与 skill 最佳实践，包含命名规则、代码结构、状态机模板、复位策略、时序优化等全部约束。任何 RTL 编写前必须阅读。

关键硬规则速查（完整列表见 `rtl-coding-standards.md`）：

- **命名**：全部小写（信号/模块），全部大写（参数）。端口后缀 `_i`/`_o`。低有效加 `_n`。打拍用 `_r`/`_r0`/`_r1`。实例名 `inst_` 前缀。
- **状态机**：两段式，`cstate`/`nstate`，状态名 `S_` 前缀大写。状态机只输出单比特使能（M），多比特运算在数据通路。（C5/C6/C9/C10）
- **数据流 vs 状态机分离**：不允许在状态机中写数据流，不允许在数据流中嵌入 `case(state)`。（C5/C6/C7）
- **禁止数组编码**：不允许 `reg [W] arr[N]`。深存储用 BRAM 原语。（C17）
- **控制条件对等**：同一 `always` 块中若复位控制部分寄存器，同链上所有寄存器必须同等受控。（C14）
- **代码质量**：`` `default_nettype none ``（C3）、位宽写全（C16）、检查 latch（C15）、FSM 默认值在前（C10）。
- **AXI 通道分离**：AW/W/B 独立 valid/ready 控制。读写命令路径独立。参见 `references/axi-dma/axi-dma-channel-guidelines.md`。

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

## Standard workflow

### 1. Parse the request

Summarize the requested block and list open questions. If working in an existing project, inspect local conventions first. Classify the design using the three-tier complexity gate:

| Level | Criteria | Principle review | Agent strategy |
|:-----:|----------|:----------------:|----------------|
| **L0: Trivial** | ≤200 lines, ≤8 FSM states, linear flow (no branches other than counter completion), single protocol | **Skip 2a/5a. Only P3 at 8c** (register audit). Inline in dev log. | Single agent |
| **L1: Leaf** | 200-500 lines, or nonlinear FSM, or dual protocol (e.g. APB + UART) | **FAST: 1-2 questions/principle** at 2a/5a/8c. Separate .md files. | Single agent |
| **L2: Subsystem** | >500 lines, or multi-module, or multi-clock, or 3+ protocols | **FULL: 3-5 questions/principle** at 2a/5a/8c. Signal tracing required. | **Consider decomposing into 2-3 sub-agents with interface contracts** if estimated >400 lines. Multi-agent coordination via Step 12. |

**L0 note:** Four rounds of A/B experiments (R5-R8) showed that for modules ≤200 lines with linear FSMs, the distributed principle checkpoints (2a/5a) found ZERO bugs. The overhead of writing separate review documents is wasted effort. However, the P3 register audit at 8c consistently catches naming mismatches and initialization gaps even in simple modules — keep that.

**L2 decomposition note:** R8b experiment showed that projects >500 lines / >10 FSM states exceed a single sub-agent's reliable completion window (~600s). The distributed workflow's documentation overhead (~30%) pushes near-limit projects over the edge. When classifying as L2, produce a submodule decomposition plan with interface contracts BEFORE any RTL.

If the specification is underspecified or vague (missing protocol details, data widths, error handling, throughput targets, CRC parameters, etc.), run the requirement extraction framework from `references/architecture/requirement-extraction-template.md` before proceeding to Step 2. Classify every design dimension as Required/Implied/Assumed/Unknown. Attach the filled checklist + design decision log to the timing contract. If more than 3 Required dimensions are unanswered, pause and ask the user before writing any RTL.

For full systems (L2 with >3 sub-modules), do not start with RTL. Produce a system contract, submodule decomposition, interface contracts, integration invariants, risky local traces, implementation sequence, and verification strategy.

### 2. Build the timing contract first

Before writing code, produce a short timing contract using `references/timing/timing-contract-template.md`. Include: module purpose, clock domains, reset style, input/output handshake, data latency, stall/flush behavior, boundary behavior, illegal cases.

### 2a. Principle check — Independence and Boundaries (P4, P6)

**SKIP if Level 0 (Trivial).** For L1/L2, continue below.

**Why now:** Architecture-level coupling and boundary mismatches are cheapest to fix before any RTL exists. R1 experiment: Agent A's tready isolation bug (APB corrupted AXI-Stream data) would have been prevented by a 2-minute P4 check at contract time.

Read `references/design/design-principles.md` P4 and P6. Before asking questions, check the "When to skip" section in each principle — some principles may not apply to your design type. For L1: ask 1-2 questions. For L2: ask 3-5 questions.

**For L2 multi-module designs, also consult:**
- `references/architecture/pipeline-design-patterns.md` — identify the pipeline topology, check backpressure propagation, flag any multi-rate or split-merge structures
- `references/architecture/memory-hierarchy.md` — compute FIFO depths, check buffer placement, audit arbitration strategy
- `references/architecture/performance-analysis.md` — calculate throughput, identify bottleneck, check for deadlock cycles in the backpressure graph

**P4 (Independence):** Are there independent channels/paths/domains in this design? Does the contract specify that they are decoupled? Can a transaction on one interface accidentally consume or corrupt data on another? Can one channel's backpressure block another's progress?

**P6 (Boundaries):** Does every module boundary have matching port widths? Are error signals propagated from sub-modules to top-level outputs? Is the completion signal style (pulse vs level) consistent across the integration chain?

**P4 — Intra-Module Independence (L1/L2 mandatory):** Beyond inter-module channel separation, check independence WITHIN each module:

- [ ] Does the protocol control path (AW/AR issue conditions) depend on data-path state (FIFO count, buffer occupancy)? If yes → **coupling.** Control should check only protocol legality (page boundaries, burst length). Data pacing belongs on the data channel (WVALID gated by `!fifo_empty`).
- [ ] Does WVALID/RVALID gating include `data_available` / `fifo_count > N`? If yes → **P12 violation + coupling.** WVALID should depend only on `w_active_q`. Data pacing is `!fifo_empty`.
- [ ] Does the control FSM read multi-bit data-path registers directly? If yes → move to single-bit enable signals from FSM to datapath (SM1).

Fix contract-level issues now. Document any architectural decisions changed.

### 3. Freeze the contract

Turn the timing contract into a short design spec with: ports and signal widths, naming conventions, reset and idle behavior, handshake or protocol rules, corner cases.

### 4. Identify state elements

List registers or memories that carry state: state registers, FIFO storage, accepted-operation conditions, data/control fields that must move together.

### 5. Write the cycle trace

Use `references/timing/cycle-trace-guidelines.md`. Include pre-edge state, combinational condition, active-edge update, next visible state, and invariant.

### 5a. Principle check — Timing Contracts and FSM Safety (P1, P2)

**SKIP if Level 0 (Trivial).** For L1/L2, continue below.

**Why now:** The cycle trace is the best place to verify signal timing and FSM behavior — before RTL is written, when you can still redesign without rewriting code.

Read `references/design/design-principles.md` P1 and P2. Before asking questions, check the "When to skip/lite" section in each principle. For L1 linear FSMs: use P2 LITE (1-2 questions, no abort-path analysis needed). For L2: full P2 (3-5 questions with abort/recovery analysis).

**P1 (Timing Contract):** For every output in the trace: is it pulse (1-cycle), level (sustained), or registered (delayed)? Are pulse outputs guaranteed exactly 1 cycle wide in every trace path? For valid/ready handshakes: does valid hold until ready? Is data stable during backpressure?

**P2 (FSM Safety):** From every non-IDLE state, trace the path back to IDLE. What happens if a waited-on signal never arrives? For states entered by a request: if the request deasserts while in an intermediate state, is there an abort path? After reset, does the FSM start in IDLE with all outputs safe?

Fix any issue found in the cycle trace. Only then freeze the trace and proceed to pattern selection.

### 6. Choose a pattern

Pick the safest known template from `references/rtl/` or `references/patterns/`. Explain why it fits. If multiple patterns are plausible, state the tradeoff using `references/architecture/tradeoff-guidance.md`.

### 7. Generate RTL

**Before writing ANY code, read `references/rtl/rtl-coding-standards.md`.** This is a hard requirement (not optional). Pay particular attention to M-graded rules: C3 (`default_nettype none`), C5/C6/C7 (FSM/datapath separation), C9/C10 (two-process FSM), C14 (control symmetry), C16 (explicit bit widths), C19 (explicit else in sequential blocks), C20 (group registers by function).

Before writing code, read the relevant pattern reference:
- FSM → `references/rtl/fsm-examples.md`
- FIFO → `references/rtl/fifo-examples.md` (use FWFT pattern for data-path FIFOs)
- Pipeline → `references/rtl/pipeline-examples.md`
- Handshake → `references/rtl/handshake-examples.md`
- AXI → `references/axi-dma/axi-dma-channel-guidelines.md` or `references/axi-dma/axi-full-guidelines.md`
- DMA → `references/axi-dma/dma-cdma-examples.md`

Do not rely on memory or training data for style decisions. Read the reference, extract the rule, then write code that follows it.

Before writing RTL, scan against `references/debug/bug-pattern-library.md`: match the module type and pattern category, state the risk and prevention before coding.

Write synthesizable code following `references/rtl/rtl-coding-standards.md` and `references/rtl/fsm-examples.md`: clear signal names, explicit reset, one driver per signal, no latches, Verilog-first style, two-process FSM, `cstate`/`nstate` naming.

Apply power/timing/area rules from `references/design/power-timing-area.md`: clock-enable over gating (P1), memory access qualification (P5), bit-width discipline (A3), balanced operator trees (A1). For FPGA targets: DSP/BRAM/SRL inference patterns (A4, A5, P6).

**Module boundary discipline (PH1):** Prefer registered outputs when signals cross module hierarchy boundaries. Combinational outputs from sub-modules (via `assign` or combinational `always @(*)`) create timing closure difficulties, complicate testbench sampling, and risk glitches during state transitions. If a module drives AXI-Stream tvalid/tdata/tlast or APB prdata through purely combinational paths from its sub-modules, the testbench must account for combinational propagation delay, and any state change in the driving FSM creates a window where outputs may glitch before settling. Registered outputs avoid all of these issues at the cost of one cycle of latency. See `references/advanced/physical-awareness-guidelines.md` PH1 and the A/B experiment results in SKILL_CHANGELOG.md.

### 7b. Pre-synthesis check (mandatory for L1/L2)

**Before self-review, run Yosys synthesis.** This catches issues that Step 8's manual review often misses, in under 60 seconds:

```tcl
read_verilog <all_rtl_files>.v
hierarchy -check -top <top_module>
proc; flatten; opt
select -count t:$_DLATCH_* -list latch_cells
stat
```

**Reject-on-sight:**
- Any latch cell (`$_DLATCH_*`) → fix before proceeding
- Combinational loop → fix before proceeding  
- Blocking assignments (`=`) inside `always @(posedge clk)` → some tools warn, Yosys errors on local `reg` declarations in unnamed blocks

**Check and fix:**
- Implicit wire warnings
- Width mismatch warnings
- Unused signal warnings (dead code)

All warnings must be reviewed. Any warning related to your own code must be fixed. Only after synthesis is clean, proceed to Step 8.

### 8. RTL self-review against skill constraints

Before simulation, review the generated RTL against the full self-review checklist in `references/verification/self-review-checklist.md`. Each item must be explicitly checked and marked pass/fail. For each FAIL item, fix before proceeding and state what was changed. For each ✅ item, cite the specific line numbers or signal names that satisfy the check — do not mark items as passed without evidence.

The checklist covers the following categories. Read the reference for the full item list:

| Category | Items | Key References |
|----------|:-----:|----------------|
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

**Signal type cross-check (mandatory for L1/L2):** Before leaving Step 8, cross-check the timing contract's signal classification (from Step 2 and Step 5a) against the actual RTL implementation. This bridges the gap between contract-level P1 review and RTL-level review — and prevents the most common contract-implementation mismatch: a signal classified as "level" in the contract but implemented as a 1-cycle pulse in the RTL.

For every output port classified in the timing contract as **pulse / level / registered**, trace the RTL and verify the implementation produces that behavior:

| Contract classification | RTL check | If mismatch found |
|-------------------------|-----------|-------------------|
| **Pulse** (1-cycle) | Does the output deassert after exactly 1 cycle? Uses transition detection (`prev != cstate`), not state comparison (`cstate == TARGET`)? | Revisit Step 5a P1 — the cycle trace was wrong, or the RTL diverged from the trace |
| **Level** (sustained) | Does the output sustain until a clear condition (W1C, next-packet-start, FSM exit)? Can the testbench safely poll it at any time? | Add a registered flag or FSM state that holds the level until the documented clear condition |
| **Registered** (delayed 1 cycle) | Is the output driven from a flip-flop (not combinational `assign` or `always @(*) cstate`)? Does the timing contract document the +1 cycle latency? | Either reclassify the signal in the contract, or add a pipeline register |

**Example (from split-merge pipeline validation):** The contract classified `pkt_done_o` as a level flag. The RTL implemented it as `assign pkt_done_o = (cstate == S_DONE)` — a 1-cycle pulse. This mismatch caused test T3 (back-to-back packets) to fail because the testbench sampled `pkt_done_o` too late. The fix was to convert `pkt_done_o` to a sticky registered flag that persists until cleared by the next packet start.

Do NOT skip this check for signals that appear in the interface contract but are generated deep in the RTL. Each output must be cross-checked individually.

**NBA ordering hazard check (mandatory for L1/L2):** Before leaving Step 8, read `references/timing/nba-ordering-guide.md`. NVMe Phase 3 found that 6 of 13 bugs were NBA ordering hazards — and all 6 passed the structural self-review checklist. The structural checklist checks THAT `<=` is used; it does not check whether the NBA ordering is correct.

For every `always @(posedge clk_i)` block in your RTL, answer:

1. **Same-block dependency:** List all `<= ` assignment targets. For each target whose RHS references ANOTHER register updated in the same block: flag it. The RHS uses the OLD value of that register (NBA Trap 1, 2).

2. **Cross-block dependency:** Are there two different `always @(posedge clk_i)` blocks where block B's condition depends on block A's output? If yes: the execution order is non-deterministic (IEEE 1364 §5.5). Merge into one block or use a combinational intermediate signal (NBA Trap 6).

3. **Registered output from counter:** For any output that depends on a counter (`beat_cnt_q`, `burst_cnt_q`, `offset_q`) — is the output combinational (`assign` or `always @(*)`) or registered (`<=`)? Registered outputs lag by 1 cycle (NBA Trap 1). Use combinational.

4. **Data from pointer-indexed memory:** For any data read from `fifo_mem[rd_ptr_q]` (or similar) — is the data output combinational or pre-fetched? If registered in the same block as the pointer advance, data shifts by 1 beat (NBA Trap 2).

5. **Counter gating:** For every counter advance condition — is it gated by BOTH the advance signal AND the valid signal? `if (valid && ready)` not `if (ready)` (NBA Trap 4).

If any hazard is found: apply the fix pattern from `references/timing/nba-ordering-guide.md` layer 3. Then re-run Step 8 on the changed code.

**Critical limitation:** This checklist verifies STRUCTURAL correctness only. It does NOT verify FUNCTIONAL correctness. Always follow with Step 8b and Step 9.

### 8b. Functional verification (mandatory)

**Structural review (Step 8) does NOT guarantee functional correctness.** After Step 8, always run at least one functional test with known inputs and expected outputs. See bug pattern V1 — "Structural PASS but functional FAIL."

**Golden reference methodology** (see `references/verification/golden-reference-guide.md`):

| Module type | Golden reference strategy | Example |
|-------------|--------------------------|---------|
| Computation (CRC, ECC, ALU) | Known I/O pairs from authoritative source | CRC-32 of `0x00000000` = `0x2144DF1C` |
| Algorithm (variable input) | Software reference model (independent function) | LFSR iteration in testbench function |
| Register block | Write-readback scoreboard | Write `0xDEADBEEF` to offset `0x10`, read back |
| Data movement (DMA, FIFO, converter) | End-to-end data integrity scoreboard | Send pattern, verify output matches input |
| Stateful control (arbiter, counter) | Invariant checking | `$onehot0(grant_o)`, credit count bounds |
| Pipeline/latency | Output latency verification | Input cycle vs output cycle comparison |

**Minimum functional test requirements:**
1. **Golden reference**: at least one test per module type from the table above
2. **Protocol compliance**: for bus interfaces, verify at least one complete transaction (write + read-back)
3. **Boundary conditions**: test at least one edge case (empty, full, zero, max)
4. **Determinism**: same input must produce same output across multiple runs

**If functional tests fail after structural PASS:**
- Do NOT claim the design is correct
- Debug using golden reference comparison (golden-reference-guide.md) then first-divergent-cycle reasoning (simulation-loop.md Phase 4)
- Re-run Step 8 self-review after each fix (debug-driven fixes often introduce new structural violations)

### 8c. Principle check — Known Values and Output Discipline (P3, P5a, P5b)

**Note:** P1/P2 were reviewed at Step 5a. P4/P6 were reviewed at Step 2a. Step 8c covers the principles that require actual RTL code to review.

Read `references/design/design-principles.md` P3, P5a, P5b.

**Complexity gate (same three-tier as Step 1):**

| Level | Review scope | Format |
|:-----:|-------------|--------|
| **L0: Trivial** | **P3 only** (register audit). Skip P5a/P5b. | 1 paragraph in dev log, no separate file |
| **L1: Leaf** | P3 + **P5a** (Output Discipline). Skip P5b. | 1-2 questions each. `principle_review_8c.md` |
| **L2: Subsystem** | P3 + P5a + **P5b** (Physical Implementation). | 3-5 questions each. Signal tracing required. `principle_review_8c.md` |

**Why P5 was split:** Four rounds of A/B experiments (R5-R8) found ZERO P5 issues — because the principle mixed output discipline (always applicable) with physical implementation (ASIC-only). Agents saw LP/PH questions and marked NA. The split ensures every module gets the applicable part.

**P3 (Known Values):** Generate design-specific questions about register initialization. Scan your `always @(posedge clk)` blocks. Does every register have an explicit reset? Any unreset arrays or memories? Can any register reach an unexpected state (seed=0, counter wrap, shift register all-zeros)? Are all combinational signals driven by exactly one source?

**P5a (Output Discipline — always applicable for L1/L2):** Generate design-specific questions about output quality:
1. Are all module boundary outputs driven from registers (not combinational `case(cstate)`)? Combinational outputs cause glitches during FSM transitions and complicate testbench sampling. See PH1.
2. Are internal counters gated by state (not free-running when idle)? Free-running counters burn power and can wrap unexpectedly.
3. Are bit widths derived from `$clog2` (not hardcoded)? Hardcoded widths create silent bugs when parameters change.
4. Is the baud/divider counter's terminal count correct (counts DIVIDER cycles, not DIVIDER+1)?

**P5b (Physical Implementation — L2/ASIC only):** Power gating sequences, DVFS timing, isolation/retention, fanout, placement. See `references/design/design-principles.md` P5b for active-search questions. Skip for FPGA targets and L0/L1 modules.

**Output format:** Design-specific questions citing YOUR signal names and line numbers. See Step 5a for the good/bad example.

**Fix discipline** (applies to all findings at any checkpoint):

| Priority | Strategy | What to try |
|:--:|------|-------------|
| **1** | **Delete** | Remove redundant registers, unused states, dead code |
| **2** | **Retime** | Move signal earlier/later, reorder state transitions |
| **3** | **Constrain** | FSM guard (`!busy`, gating), enable qualification |
| **4** | **Add** | Hardware as last resort — document why 1-3 don't work |

### 9. Generate verification and run simulation loop

Provide at least one of: testbench skeleton, directed test list, assertions, waveform checkpoints. For AXI designs, use `references/verification/axi-verification.md`.

**Before writing the testbench, read `references/verification/icarus-common-pitfalls.md`.** It documents 15 Icarus-specific pitfalls discovered across R5-R8 experiments — `return`/`break` syntax, APB delta-cycle races, combinational output timing, address aliasing, and more. Most are 2-line fixes that save 1-2 simulation iterations. Also use `references/verification/tb-examples.md` section 0 (standard skeleton) as your starting template.

**Simulation loop:** Follow `references/verification/simulation-loop.md` (lint→compile→simulate→analyze→fix→re-simulate, max 3 iterations). Testbench must follow output protocol: `RESET_RELEASED`, `TEST_START/PASS/FAIL <id>`, `ALL_TESTS_PASS`, `SIMULATION_DONE`.

**During Phase 4 (Failure Analysis) — Principle-driven debug (was Step 8d):** Before guessing at a fix, re-read your principle review documents (2a/5a/8c). They contain a signal-level map of your design:

1. **Categorize the failure:** compile error / testbench infrastructure / RTL functional bug
2. **For RTL functional bugs:** map the failure signal/symptom to the relevant principle doc:
   - Wrong signal timing / pulse width? → re-read P1 review
   - FSM stuck / wrong state / missing transition? → re-read P2 review
   - Wrong register value / 'x' propagation / uninitialized? → re-read P3 review
   - One channel blocking another / APB corrupting data? → re-read P4 review
   - Combinational output glitch / timing closure issue? → re-read P5a review
3. **Match** the symptom against `references/debug/bug-pattern-library.md`. Cite pattern ID if found.
4. **Fix** minimally. Re-run Step 8 checklist on the changed code (debug fixes are the #1 source of constraint violations).

The principle review documents let you locate root causes faster than adding `$display` statements — they already trace every signal's timing contract, every FSM state's exit path, and every register's initialization.

**Synthesis feedback:** After simulation passes, run yosys to check for latches, combinational loops, and critical path. See `references/verification/synthesis-feedback-guide.md` and `scripts/yosys_extract.py`.

### 10. Review and iterate

If the user provides errors or waveforms, identify the likely cause, propose the minimal correction, and restate what must be rechecked.

**After any RTL modification (simulation fix, user-requested change, optimization):** re-run the Step 8 self-review checklist on the changed files. Debug-driven fixes are the most common source of constraint violations — the pressure to "make it work" overrides the discipline to "make it correct." Common debug anti-patterns:
- Adding `data_available` to WVALID to "fix" a hang (P12 violation)
- Switching to registered FIFO output to "fix" data timing (F1 violation)
- Adding a combinational `_d` block to "fix" counter logic (SM2 violation)
- Coupling read/write burst-ready to "fix" ordering (anti-pattern)
- Adding dead ports/modules "for future use" (integration violation)

### 11. Verify timing against the contract and trace

Before finalizing, check RTL against the timing contract and cycle trace: current/next cycle behavior, stall/hold behavior, reset release, boundary behavior, trace invariants. If mismatch, fix before answering. State design maturity level and top residual risks from `references/verification/engineering-review-checklist.md`.

### 12. Sub-agent delegation

Sub-agents do not automatically load this skill and will fall back to training-data anti-patterns. The prompt must include either: (1) a skill loading directive, or (2) inlined critical rules. After delivery, run Step 8 review before accepting. Full prompt template and multi-module rules: see `references/architecture/sub-agent-delegation.md`.

## Debugging rules

When a user shares a failure:
1. Match the symptom against `references/debug/bug-pattern-library.md` patterns.
2. If a pattern matches, cite the pattern ID, root cause, and minimal fix.
3. If no pattern matches, fall back to first-divergent-cycle reasoning.

## Testbench guidance

Generate a testbench that is small but targeted: reset sequence, one normal transaction, one backpressure case, one boundary case, one error or corner case if relevant. A minimal testbench needs a pass/fail signal. Prefer `$fatal`/error counters over waveform-only stimulus.

**Combinational output timing:** Bus protocol combinational outputs (PSLVERR, HRDATA, PREADY) are only valid DURING the transaction, not after. Check with `#delay` after the enabling signal takes effect (e.g., after `penable<=1` for APB), NOT after the transaction completes. See `references/bus/apb-guidelines.md` for the correct test pattern.

## If the request is underspecified

Use `references/architecture/requirement-extraction-template.md` to structure the ambiguity: classify every design dimension, document assumptions, and present concrete choices to the user. Ask only the questions that block correct RTL: interface style, reset polarity, latency/throughput, overflow/underflow behavior, CDC constraints. Do not generate a full design from guesswork for complex protocols.

## Skill success criteria

This skill is working well when it can produce readable, synthesizable RTL for standard patterns, explain timing behavior without hand-waving, surface missing requirements early, and pair code with a practical verification plan.
