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
- **Architecture**: `references/architecture/` — hierarchy, system contracts, integration invariants, tradeoffs, staged bring-up
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

All detailed rules are in `references/rtl/coding-guidelines.md`. Key mandatory rules:

- **Naming**: Read `references/timing/naming-guidelines.md` before writing any port list. Use `*_i`/`*_o` suffixes, `*_q`/`*_d` for registered state, `wr_do`/`rd_do` for FIFO operations.
- **FSM style**: Use two-process style for >3 states. See `references/rtl/fsm-examples.md`.
- **FSM single-bit control**: All FSM I/O must be single-bit enables. Multi-bit register assignments happen outside the FSM. See `references/rtl/fsm-examples.md` pattern 5.
- **AXI channel separation**: AW/W/B must have independent valid/ready control. Read/write command paths must be independent. See `references/axi-dma/axi-dma-channel-guidelines.md`.

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

Summarize the requested block and list open questions. If working in an existing project, inspect local conventions first. Classify as leaf module, subsystem, or full system.

If the specification is underspecified or vague (missing protocol details, data widths, error handling, throughput targets, CRC parameters, etc.), run the requirement extraction framework from `references/architecture/requirement-extraction-template.md` before proceeding to Step 2. Classify every design dimension as Required/Implied/Assumed/Unknown. Attach the filled checklist + design decision log to the timing contract. If more than 3 Required dimensions are unanswered, pause and ask the user before writing any RTL.

For full systems, do not start with RTL. Produce a system contract, submodule decomposition, interface contracts, integration invariants, risky local traces, implementation sequence, and verification strategy.

### 2. Build the timing contract first

Before writing code, produce a short timing contract using `references/timing/timing-contract-template.md`. Include: module purpose, clock domains, reset style, input/output handshake, data latency, stall/flush behavior, boundary behavior, illegal cases.

### 3. Freeze the contract

Turn the timing contract into a short design spec with: ports and signal widths, naming conventions, reset and idle behavior, handshake or protocol rules, corner cases.

### 4. Identify state elements

List registers or memories that carry state: state registers, FIFO storage, accepted-operation conditions, data/control fields that must move together.

### 5. Write the cycle trace

Use `references/timing/cycle-trace-guidelines.md`. Include pre-edge state, combinational condition, active-edge update, next visible state, and invariant.

### 6. Choose a pattern

Pick the safest known template from `references/rtl/` or `references/patterns/`. Explain why it fits. If multiple patterns are plausible, state the tradeoff using `references/architecture/tradeoff-guidance.md`.

### 7. Generate RTL

Before writing code, read the relevant pattern reference:
- FSM → `references/rtl/fsm-examples.md`
- FIFO → `references/rtl/fifo-examples.md` (use FWFT pattern for data-path FIFOs)
- Pipeline → `references/rtl/pipeline-examples.md`
- Handshake → `references/rtl/handshake-examples.md`
- AXI → `references/axi-dma/axi-dma-channel-guidelines.md` or `references/axi-dma/axi-full-guidelines.md`
- DMA → `references/axi-dma/dma-cdma-examples.md`

Do not rely on memory or training data for style decisions. Read the reference, extract the rule, then write code that follows it.

Before writing RTL, scan against `references/debug/bug-pattern-library.md`: match the module type and pattern category, state the risk and prevention before coding.

Write synthesizable code following `references/rtl/coding-guidelines.md`: clear signal names, explicit reset, one driver per signal, no latches, Verilog-first style, two-process FSM, `*_q`/`*_d` suffixes.

Apply power/timing/area rules from `references/design/power-timing-area.md`: clock-enable over gating (P1), memory access qualification (P5), bit-width discipline (A3), balanced operator trees (A1). For FPGA targets: DSP/BRAM/SRL inference patterns (A4, A5, P6).

### 8. RTL self-review against skill constraints

Before simulation, review the generated RTL against this checklist. Each item must be explicitly checked and marked pass/fail. For each FAIL item, fix before proceeding and state what was changed. For each ✅ item, cite the specific line numbers or signal names that satisfy the check — do not mark items as passed without evidence.

**Handshake (cite `references/debug/bug-pattern-library.md` H1-H8):**
- [ ] VALID holds until READY (no premature deassertion) — H1, H8
- [ ] VALID not gated by non-protocol conditions (outstanding count, FIFO status, flow control) — H8
- [ ] Payload stable while VALID high — H1
- [ ] No combinational ready loop across modules — H2

**Data path (cite DP1-DP5, F1):**
- [ ] All error capture points traced to completion output — DP5, `references/architecture/integration-invariants.md`
- [ ] Bit-slicing avoided when value can equal 2^n (use if/else) — DP4
- [ ] WSTRB correctly computed for unaligned addresses — `references/axi-dma/axi-dma-channel-guidelines.md`
- [ ] Data-path FIFOs use FWFT (combinational) output, NOT registered output — F1, `references/rtl/fifo-examples.md`

**Naming (cite `references/timing/naming-guidelines.md`):**
- [ ] All ports use `*_i`/`*_o` suffixes
- [ ] All registered state uses `*_q` suffix
- [ ] Combinational signals do NOT use `*_q` suffix
- [ ] FIFO ops use `wr_do`/`rd_do` naming

**RTL correctness (cite `references/rtl/correctness-rules.md`):**
- [ ] Every reg/wire has exactly one driving source — E1
- [ ] Every combinational block assigns defaults before conditional branches — E2
- [ ] No implicit truncation — explicit part-selects on width mismatches — E3
- [ ] `<=` in sequential blocks, `=` in combinational blocks, never mixed — E4
- [ ] All combinational blocks use `always @(*)` — E5
- [ ] All registers have explicit reset (or documented justification) — E6
- [ ] No combinational feedback loops — E7
- [ ] Every `.v` file starts with `` `default_nettype none `` — E8

**FSM (cite C2, C3, SM1, SM2):**
- [ ] All combinational blocks have default assignments — C3
- [ ] FSM has default case → IDLE — C2
- [ ] Two-process style for >3 states — `references/rtl/fsm-examples.md`
- [ ] No multi-bit datapath `_d` assignments inside the FSM combinational block (`state_d` is exempt) — SM1
- [ ] No second `always @(*)` block computing multi-bit `_d` values gated on state — SM2
- [ ] All multi-bit register updates use synchronous `always @(posedge clk)` gated by single-bit enables from the FSM — `references/rtl/fsm-examples.md` pattern 5

**Protocol (cite P4, P5, P9, P11, P12, P13, IHI0022E A3.3):**
- [ ] Completion on B response, not last W beat — P4
- [ ] WVALID holds until WREADY — P11
- [ ] WVALID holds for entire burst (no mid-burst deassertion) — P12, IHI0022E A3.3.1
- [ ] ARVALID/AWVALID hold until corresponding READY — P11, IHI0022E A3.3.1
- [ ] VALID not dependent on READY (no combinational path) — IHI0022E A3.3.2
- [ ] Write engine does NOT use sequential AW→W→B FSM — P13, use independent AW/W/B controllers
- [ ] AW/W/B channels have independent valid/ready control — `references/axi-dma/axi-dma-channel-guidelines.md`
- [ ] Data FIFO depth >= max burst length, or burst-ready gate on WVALID — P12
- [ ] WVALID does NOT depend on FIFO empty/full state mid-burst — P12, `references/axi-dma/axi-dma-channel-guidelines.md` burst-ready gate pattern
- [ ] 4KB boundary: `12'h1000`, not `12'h800` — `references/axi-dma/axi-dma-channel-guidelines.md`
- [ ] WSTRB last beat: handle `last_offset == 0` (all bytes valid) — `references/axi-dma/axi-dma-channel-guidelines.md`

**APB (if APB interface present, cite `references/bus/apb-guidelines.md`):**
- [ ] PSEL asserted only in SETUP and ACCESS phases
- [ ] PENABLE asserted only in ACCESS phase
- [ ] PADDR/PWDATA/PWRITE latched in SETUP, held through ACCESS
- [ ] PSLVERR mapped to upstream error response
- [ ] PSEL deasserted between transactions
- [ ] If APB slave uses registered PRDATA: bridge samples one cycle after PREADY=1

**AXI-Stream (if AXI-Stream interface present, cite `references/axi-dma/axi-stream-guidelines.md`):**
- [ ] TLAST propagated exactly on every beat
- [ ] TKEEP propagated exactly on every beat
- [ ] Payload stable while TVALID=1 and TREADY=0 — H1
- [ ] TVALID not dependent on TREADY — A3.3.2
- [ ] Backpressure propagation documented (combinational or registered)
- [ ] Packet boundary behavior defined (state at TLAST)

**CDC (if multiple clock domains, cite `references/synthesis/cdc-guidelines.md`):**
- [ ] Multi-bit CDC uses gray code or handshake (not independent bit synchronization)
- [ ] Synchronizer flip-flops marked with `(* ASYNC_REG = "TRUE" *)` attribute
- [ ] Reset: async assertion, sync deassertion per destination domain
- [ ] No combinational paths across clock domains

**Integration:**
- [ ] All per-channel errors OR'd into completion tracker — DP5
- [ ] Outstanding counter saturation doesn't block drain — `references/architecture/integration-invariants.md`
- [ ] Reset clears all valid-like outputs — R2
- [ ] All module ports are referenced in the module body (no dead ports)
- [ ] No dead modules (all instantiated modules are used; unused modules are deleted or documented as reference-only)
- [ ] Completion signal style matches spec: pulse (1-cycle) for per-command done, level (sticky) for status — `references/timing/timing-contract-template.md`

State the review result: PASS (all items checked) or FAIL (list items fixed).

**Critical limitation:** This checklist verifies STRUCTURAL correctness only (naming, FSM style, protocol compliance, reset). It does NOT verify FUNCTIONAL correctness (output values, computation results). A design can pass all items and still produce wrong results. See bug-pattern P18 (CRC pipeline latency) and Crossbar project (routing logic bug) — both passed structural review but failed functional tests.

### 8b. Functional verification (mandatory)

**Structural review (Step 8) does NOT guarantee functional correctness.** After Step 8, always run at least one functional test with known inputs and expected outputs.

**Minimum functional test requirements:**
1. **Golden reference**: for computation modules (CRC, ECC, ALU), provide known input→output pairs from authoritative sources or manual calculation
2. **Protocol compliance**: for bus interfaces, verify at least one complete transaction (write + read-back)
3. **Boundary conditions**: test at least one edge case (empty, full, zero, max)
4. **Determinism**: same input must produce same output across multiple runs

**If functional tests fail after structural PASS:**
- Do NOT claim the design is correct
- Debug using first-divergent-cycle reasoning (simulation-loop.md Phase 4)
- Re-run Step 8 self-review after each fix (debug-driven fixes often introduce new structural violations)

### 9. Generate verification and run simulation loop

Provide at least one of: testbench skeleton, directed test list, assertions, waveform checkpoints, expected cycle-by-cycle behavior. For nontrivial stateful logic, include at least one pass/fail check. For queues, arbiters, adapters, multi-stage pipelines, or subsystems, include a compact verification matrix.

For AXI designs, use `references/verification/axi-verification.md`: BFM tasks for driving/monitoring transactions, scoreboard for DMA data integrity, and AXI-specific functional coverage points. At minimum, provide the 10-test coverage-driven plan from that file.

**Simulation loop (when tools are available):** Follow `references/verification/simulation-loop.md`:
1. **Lint first:** `verilator --lint-only -Wall` — fix all errors before simulation
2. **Compile:** `iverilog -g2012 -o sim.vvp <sources> <testbench>`
3. **Simulate:** `timeout <sec> vvp sim.vvp` — parse output for PASS/FAIL/HANG
4. **Analyze failures:** match against `references/debug/bug-pattern-library.md`, apply minimal fix
5. **Re-review fix against Step 8 checklist:** before re-simulating, verify the fix does not violate skill constraints. Common violations during debug: adding `data_available` to WVALID (P12), using registered FIFO output to "fix" timing (F1), adding `_d` combinational signals (SM2), coupling read/write paths. If the fix violates a constraint, find an alternative fix that stays within the rules.
6. **Re-simulate:** maximum 3 fix-and-rerun iterations
7. **Report:** quote tool output, show what changed at each iteration, state residual issues

The testbench must follow the output protocol: `RESET_RELEASED`, `TEST_START/PASS/FAIL <id>`, `ALL_TESTS_PASS`, `SIMULATION_DONE`. This enables automated result parsing.

If simulation tools are unavailable, state this explicitly and fall back to static self-review only. Do not claim simulation correctness without running a tool.

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

When delegating RTL work to sub-agents (parallel module generation, testbench writing, etc.), the sub-agent does not automatically load this skill. Without explicit rules, the sub-agent falls back to its training data — which produces the exact anti-patterns this skill exists to prevent (single-process FSMs, multi-bit values in FSM combinational blocks, mixed AW/W/B channels, wrong naming conventions).

**Rule:** When spawning a sub-agent for RTL tasks, the prompt must include one of:

1. **Skill loading directive:** Tell the sub-agent to load this skill first (e.g., "Before writing any code, read and follow the rules in `<path>/SKILL.md` and the references it points to").

2. **Inline critical rules:** If the sub-agent cannot load the skill, include the key constraints directly in the prompt. At minimum, these rules must be present:
   - Two-process FSM style (state register in `always @(posedge clk)`, next-state + outputs in `always @(*)`)
   - Single-bit control rule: FSM combinational block assigns only single-bit enables and `state_d`. Multi-bit registers (addr, counter, len, data, wstrb) updated in synchronous blocks gated by those enables
   - Naming: `*_i`/`*_o` ports, `*_q`/`*_d` registered state, `wr_do`/`rd_do` for FIFO ops
   - AXI channel separation: AW/W/B independent valid/ready, RD/WR command paths independent
   - No `always @(*)` block computing multi-bit `_d` values gated on state (the "shadow datapath" anti-pattern)

3. **Post-generation review:** After the sub-agent delivers RTL, run the self-review checklist (step 8) against its output before accepting it. Fix violations before integrating.

The prompt template for sub-agents:
```
You are writing RTL for module `<module_name>`. Before writing code:
1. Read `<skill_path>/SKILL.md` and follow its workflow.
2. Read the interface contract at `<contract_path>` — pay special attention to port widths, signal semantics, and inter-module handshake rules.
3. Read the relevant pattern reference from `references/rtl/` or `references/axi-dma/`.
4. Read `references/debug/bug-pattern-library.md` SM1, SM2 for the single-bit control rule.
5. After writing RTL, self-review against the checklist in SKILL.md step 8.
6. Verify that your module's port widths and signal semantics MATCH the interface contract exactly.
```

**Critical additions for multi-module projects:**
- Sub-agents MUST read the interface contract file — not just the skill
- Port widths must be derived from the SAME parameters as the driving module
- Byte-to-beats conversions must use the ceiling division formula, not bit extraction
- Document whether `cmd_len_i` (or similar) is in bytes or beats — ambiguity causes integration bugs

**Design request:** Assumptions → Design contract → State elements → Cycle trace → RTL → Verification notes → Risks/corner cases → Review status.

**Review/debug request:** Observed evidence → Likely contract violation → Minimal fix → What to recheck → Residual uncertainty.

**Subsystem/full system:** Assumptions → System contract → Submodule decomposition → Interface contracts → Integration invariants → Local cycle traces → Implementation sequence → Verification strategy → Residual risks.

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
