---
name: digital-front-end-skill
description: >
  Help with digital front-end RTL design and timing reasoning for Verilog/SystemVerilog.
  Use this skill whenever the user asks for RTL coding, module interface design, FSM design,
  ready/valid or req/ack handshakes, FIFO/pipeline/arbiter/counter patterns, testbench or
  assertion generation, timing-behavior explanation, lint/code-review help, simulation debug,
  or bug triage for digital chip front-end work, even if they do not explicitly mention a skill.
---

# Digital Front-End Skill

Use this skill to turn a rough digital design request into a reviewable RTL deliverable with clear assumptions, a stable coding style, and a verification plan.

The core method is:

1. Start from authoritative RTL, language, reset, CDC, and verification guidance.
2. Distill that material into compact internal design rules.
3. Select the closest local pattern or example.
4. Write the cycle-level contract and trace before code.
5. Generate conservative RTL and verification checks that match the contract and trace.

This skill already contains distilled guidance from the authority classes listed in `references/authority-synthesis.md`. Do not browse standards or methodology documents during normal use unless the user asks for exact citations, the local project requires a specific version, or a rule conflict must be resolved.

## What this skill is good for

- Translate a feature request into RTL-ready requirements.
- Propose module boundaries, ports, widths, reset behavior, and handshake rules.
- Generate synthesizable Verilog RTL for common front-end structures.
- Draft FSMs, FIFOs, pipelines, arbiters, counters, and simple protocol glue.
- Plan subsystem and full-system front-end designs with hierarchy, interface contracts, and integration invariants.
- Produce module-level testbench scaffolding and sanity checks.
- Build verification matrices and staged bring-up plans for nontrivial blocks.
- Adapt to existing project conventions before changing integrated RTL.
- Explain timing behavior cycle by cycle.
- Review code for common RTL issues and suggest fixes.
- Triage simple simulation failures from logs or wave descriptions.
- Enforce a timing-first, spec-first way of thinking before code is written.

## What this skill should not pretend to do

- Do not claim correctness for complex protocol logic without verification.
- Do not silently invent interface semantics when the requirements are underspecified.
- Do not replace CDC review, formal signoff, or engineering judgment.
- Do not produce 'clever' RTL if a plain, readable template is safer.
- Do not answer timing questions with generic prose when a cycle-level contract is required.
- Do not quote standards as decoration; convert them into concrete RTL decisions.
- Do not generate a monolithic full-system RTL implementation from an underspecified subsystem prompt.
- Do not present directed simulation as signoff or proof of correctness.

## Operating principles

1. Start by extracting the design contract.
  - Identify inputs, outputs, clocks, resets, latency, throughput, backpressure, and corner cases.
  - If anything critical is missing, ask for it before writing code.
2. Prefer explicit structure over compactness.
  - Separate combinational and sequential logic clearly.
  - Use defaults to avoid latches and X-propagation surprises.
  - Keep naming consistent and readable.
3. Make timing visible.
  - Describe what changes on the current cycle and what is registered to the next cycle.
  - State any assumptions about handshake ordering, reset release, or pipeline latency.
  - For any temporal behavior, give a cycle-by-cycle explanation before giving code.
4. Verify the design path.
  - When generating RTL, also generate a small verification plan.
  - Include a minimal testbench skeleton or directed test ideas.
  - Call out what should be checked in simulation, lint, and assertions.
  - Treat simulation evidence as necessary for nontrivial protocol or stateful logic.
5. When debugging, work from evidence.
  - Use compiler/lint errors, sim logs, wave behavior, and assertions as the source of truth.
  - Suggest the smallest fix that preserves the intended behavior.
  - If the failure is ambiguous, ask for the missing waveform or log evidence instead of guessing.

## Authority-to-rule synthesis

The skill should treat standards and methodology documents as source material, not as answer text. Use this hierarchy:

1. User-provided project spec, interface spec, style guide, and failing evidence.
2. Language and simulation semantics from Verilog/SystemVerilog standards.
3. Vendor or methodology guidance for synthesis, reset, CDC, lint, and verification.
4. Established synchronous design practice for FSMs, FIFOs, pipelines, arbiters, counters, and handshakes.
5. This skill's local examples and templates.

When converting source material into guidance:

- Extract the rule that affects an RTL decision.
- State the cycle-level consequence of the rule.
- Tie the rule to a code structure or verification check.
- Prefer short normative instructions over literature review.
- If local project rules conflict with this skill, follow the local project rules and call out the conflict.
- If the source material is missing or ambiguous, state the assumption rather than implying authority.
- During normal RTL work, use the distilled rules in this skill as the operating standard instead of re-reading the original documents.

Useful translation pattern:

- Source concept: nonblocking assignments model clocked state updates.
- Internal rule: use nonblocking assignments for registers and explain when the new value becomes visible.
- Code consequence: keep registered state in `always @(posedge clk)` blocks.
- Verification consequence: check behavior on the cycle after the active clock edge.

## Timing and protocol discipline

- Always explain stateful behavior in cycle terms before implementation.
- For every nontrivial block, write the cycle contract first: what changes now, what changes next, and what must stay stable.
- For FSM, FIFO, pipeline, or handshake logic, include a cycle trace before RTL.
- For complete subsystems, decompose first and trace only risky local boundaries.
- Prefer explicit two-process FSMs for multi-stage control; use implicit flag/counter control only for small single-path trackers and state the equivalent states.
- For ready/valid logic, define exactly when data is accepted, held, and released.
- For FSMs, list legal states and the reset state before coding.
- For FIFOs and pipelines, define boundary behavior and alignment rules.
- For CDC or multi-clock logic, do not improvise; require an explicit safe crossing pattern or additional review.
- If the timing story is unclear, stop and ask before generating code.

## Reference materials

Use these curated references as the primary knowledge base for timing and pattern decisions:

- `references/timing-semantics.md`
- `references/authority-synthesis.md`
- `references/timing-contract-template.md`
- `references/naming-guidelines.md`
- `references/cycle-trace-guidelines.md`
- `references/protocol-authority-map.md`
- `references/hierarchical-design-guidelines.md`
- `references/system-contract-template.md`
- `references/interface-contract-template.md`
- `references/integration-invariants.md`
- `references/axi-dma-planning-example.md`
- `references/engineering-review-checklist.md`
- `references/verification-matrix-template.md`
- `references/tradeoff-guidance.md`
- `references/staged-bringup-guidelines.md`
- `references/advanced-patterns.md`
- `references/arbiter-examples.md`
- `references/axi-full-guidelines.md`
- `references/axi-multi-outstanding-guidelines.md`
- `references/axi-lite-guidelines.md`
- `references/axi-dma-channel-guidelines.md`
- `references/dma-descriptor-burst-guidelines.md`
- `references/apb-guidelines.md`
- `references/ahb-lite-guidelines.md`
- `references/axi-stream-guidelines.md`
- `references/subsystem-rtl-slicing-guidelines.md`
- `references/project-adaptation-guidelines.md`
- `references/toolchain-closure-guidelines.md`
- `references/protocol-edge-case-checklist.md`
- `references/clock-reset-guidelines.md`
- `references/cdc-guidelines.md`
- `references/constraint-guidance.md`
- `references/synthesis-guidance.md`
- `references/micro-arch-decisions.md`
- `references/assertion-quality-checklist.md`
- `references/brownfield-guidance.md`
- `references/large-module-guidance.md`
- `references/protocol-semantics.md`
- `references/rtl-writing-guidelines.md`
- `references/rtl-patterns.md`
- `references/full-module-examples.md`
- `references/verilog-examples.md`
- `references/fsm-examples.md`
- `references/handshake-examples.md`
- `references/fifo-examples.md`
- `references/pipeline-examples.md`
- `references/tb-examples.md`
- `references/assertion-examples.md`
- `references/debug-cases.md`
- `references/verification-guidance.md`
Read them when the task involves timing, protocol behavior, pattern selection, debug, or verification. They are intentionally written as a curated synthesis of authoritative engineering practice, not as a dump of mixed-quality examples.

Reference selection:

- Timing semantics, assignment ordering, or cycle explanation: read `references/timing-semantics.md`, `references/timing-contract-template.md`, and `references/cycle-trace-guidelines.md`.
- Source-to-rule conversion or methodology grounding: read `references/authority-synthesis.md`.
- Protocol-specific AXI, AXI-Lite, AXI-Stream, APB, AHB, ACE, or CHI rules: read `references/protocol-authority-map.md` before adding or changing rules.
- Naming or interface style: read `references/naming-guidelines.md`.
- Complete DMA, AXI subsystem, cache, NoC, bus bridge, multi-channel engine, or full top integration: read `references/hierarchical-design-guidelines.md`, `references/system-contract-template.md`, `references/interface-contract-template.md`, and `references/integration-invariants.md`.
- AXI DMA architecture or implementation slicing: also read `references/axi-dma-planning-example.md`, `references/axi-dma-channel-guidelines.md`, and `references/subsystem-rtl-slicing-guidelines.md`.
- AXI full masters, slaves, bridges, or memory engines: read `references/axi-full-guidelines.md`.
- AXI multi-ID, multi-outstanding, or ordering work: also read `references/axi-multi-outstanding-guidelines.md`.
- DMA descriptor parsing or burst command generation: also read `references/dma-descriptor-burst-guidelines.md`.
- AXI-Lite register blocks or small slaves: read `references/axi-lite-guidelines.md`.
- APB, AHB-Lite, or AXI-Stream blocks: read the matching `references/apb-guidelines.md`, `references/ahb-lite-guidelines.md`, or `references/axi-stream-guidelines.md`.
- Architecture or microarchitecture tradeoffs: read `references/tradeoff-guidance.md` and `references/micro-arch-decisions.md`.
- Nontrivial verification planning: read `references/verification-matrix-template.md`.
- Large-system staged implementation: read `references/staged-bringup-guidelines.md`.
- Arbiters: read `references/advanced-patterns.md` and `references/arbiter-examples.md`.
- Specialized RTL/IP patterns: read `references/credit-based-examples.md`, `references/rate-limiter-examples.md`, `references/retry-buffer-examples.md`, `references/utility-examples.md`, `references/crc-examples.md`, `references/ecc-examples.md`, `references/width-converter-examples.md`, `references/frame-assembler-examples.md`, `references/multi-bank-memory-examples.md`, or `references/cam-examples.md`.
- Req/ack adapters and counters: read `references/advanced-patterns.md`; CDC planning: read `references/cdc-guidelines.md`.
- Final review of nontrivial RTL or architecture: read `references/engineering-review-checklist.md`.
- Existing project or codebase work: read `references/project-adaptation-guidelines.md`, `references/brownfield-guidance.md`, and for large modules `references/large-module-guidance.md`.
- Claims about readiness, signoff, lint, CDC, synthesis, timing, or formal: read `references/toolchain-closure-guidelines.md`, `references/synthesis-guidance.md`, and `references/constraint-guidance.md`.
- Protocol completeness review: read `references/protocol-edge-case-checklist.md`.
- Clock/reset questions: read `references/clock-reset-guidelines.md`; CDC or async reset crossing: also read `references/cdc-guidelines.md`.
- Ready/valid, req/ack, FIFO boundaries, pipeline handoff: read `references/protocol-semantics.md`, then `references/cycle-trace-guidelines.md`.
- RTL generation or review: read `references/rtl-writing-guidelines.md`, then `references/full-module-examples.md` or the closest example file.
- Pattern selection: read `references/rtl-patterns.md`.
- Debug requests: read `references/debug-cases.md` and the protocol or pattern file closest to the failure.
- Verification requests: read `references/verification-guidance.md`, `references/tb-examples.md`, `references/assertion-examples.md`, and for SVA `references/assertion-quality-checklist.md`.
- If an RTL fixture is provided, use `scripts/rtl_check.py --case <fixture_dir>` when Icarus Verilog is available.
- For skill package maintenance, run `scripts/skill_static_check.py`.
- For eval benchmark coverage maintenance, run `scripts/eval_benchmark_check.py`; for task benchmark runs, use `scripts/init_task_benchmark.py` and `scripts/grade_task_benchmark.py`.

## Curated example policy

- Prefer plain Verilog examples over SystemVerilog unless the user asks otherwise.
- Keep the library small enough to review by eye.
- Prefer examples that are easy to simulate and reason about cycle by cycle.
- If an example is not clearly synthesizable or clearly testable, do not promote it into the library.
- Treat the example library as the canonical source for style, not a loose collection of snippets.
- Bias the library toward patterns that recur in real RTL work: FSM, FIFO, handshake, pipeline, testbench, and assertions.

## Skill internal rule synthesis

Use the timing and guideline references to synthesize the skill's own operating rules:

- turn source material into compact writing rules
- state cycle-level semantics in agent-facing language
- prefer normative instructions over raw quotations
- keep the skill body focused on action, not literature review
- let examples reinforce rules, not replace them
- bias the skill toward conservative, verifiable RTL rather than clever but fragile constructions
- prefer Verilog-first patterns and only use SystemVerilog when the user asks or the task truly needs it
- keep the skill opinionated about safe defaults so the agent does not improvise style

## Example-driven learning rule

Prefer example-first reasoning for RTL tasks:

1. Find the closest verified pattern.
2. Extract the cycle-level rule from the example.
3. Generalize only after the contract is clear.
4. Reject examples that are syntactically valid but semantically unclear.
5. Prefer plain Verilog-style RTL unless the user explicitly asks for SystemVerilog features.

Examples are not proof of correctness. Before reusing an example, check:

- Does its reset style match the request?
- Does its handshake naming match producer/consumer direction?
- Does it define boundary behavior?
- Does it preserve data/control alignment under stall?
- Does the verification note check the same contract?

## Standard workflow

### 1. Parse the request

Summarize the requested block in your own words and list the open questions.
If working in an existing project, inspect local conventions before proposing edits.

Classify the request as:

- leaf module: one FSM, FIFO, pipeline stage, register slice, counter, arbiter, or adapter
- subsystem: multiple modules with one primary data or control path
- full system: multiple protocols, multiple channels, descriptor/status/error handling, or top-level integration

For trivial one-register, one-counter, or simple explanation requests, keep the answer short. Still state reset, enable, and visible-cycle behavior, but do not force the full five-section output if it would add noise.

For full systems, do not start with RTL. Produce a system contract, submodule decomposition, interface contracts, integration invariants, risky local traces, implementation sequence, and verification strategy. Generate RTL only for one selected leaf module or integration slice unless the user explicitly asks for staged implementation.

### 2. Build the timing contract first

Before writing code, produce a short timing contract using the template in `references/timing-contract-template.md`.
It should include:

- module purpose
- clock domain(s)
- reset style
- input handshake
- output handshake
- data latency
- stall behavior
- flush behavior
- boundary behavior
- illegal or unsupported cases

If any of these fields are irrelevant, mark them as `not applicable` instead of inventing behavior.

### 3. Freeze the contract

Turn the timing contract into a short design spec with:

- ports and signal widths
- naming conventions
- reset and idle behavior
- handshake or protocol rules
- corner cases

### 4. Identify state elements

Before writing RTL, list the registers or memories that carry state:

- state registers such as `state_q`, `valid_o`, `count_q`, and pointers
- memories such as FIFO storage
- accepted-operation conditions such as `accept_input`, `accept_output`, `wr_do`, `rd_do`, or `advance`
- data/control fields that must move or hold together

### 5. Write the cycle trace

For FSM, FIFO, pipeline, ready/valid, or other stateful behavior, write a cycle trace using `references/cycle-trace-guidelines.md`.
The trace must include pre-edge state, combinational condition, active-edge update, next visible state, and invariant.
If the trace exposes an unspecified reset, stall, flush, or boundary case, ask or state a conservative assumption before RTL.

### 6. Choose a pattern

Pick the safest known template:

- counter / register slice / pulse logic
- FSM
- FIFO / skid buffer / pipeline stage
- ready-valid adapter
- arbiter
- req/ack adapter
- counter / event detector
- CDC synchronizer wrapper

Explain why the pattern fits. If more than one pattern is plausible, state the tradeoff using `references/tradeoff-guidance.md`.

### 7. Generate RTL

Write synthesizable code with:

- clear signal names
- explicit reset behavior
- one driver per signal
- no inferred latches
- simple control flow
- Verilog-first style unless the user asks for SystemVerilog
- one explicit `accept_input`, `accept_output`, `wr_do`, `rd_do`, or `advance` condition for each protocol movement
- comments only where they clarify timing, boundary, or protocol intent

### 8. Generate verification help

Provide at least one of:

- a testbench skeleton
- directed test list
- assertions to add
- waveform checkpoints
- expected cycle-by-cycle behavior

For nontrivial stateful logic, include at least one pass/fail check that protects the contract, not only a prose test idea.
For queues, arbiters, adapters, multi-stage pipelines, or subsystems, include a compact verification matrix.
When a fixture or testbench is available, prefer running `scripts/rtl_check.py` and use the failing signature as debug evidence.

### 9. Review and iterate

If the user provides errors or waveforms, identify the likely cause, propose the minimal correction, and restate what must be rechecked.

### 10. Verify timing against the contract and trace

Before finalizing, check the RTL against the timing contract and cycle trace:

- current-cycle behavior
- next-cycle behavior
- stall or hold behavior
- reset release behavior
- boundary behavior
- trace invariants and verification checks

If the implementation does not match the contract or trace, fix the contract, trace, or RTL before answering.
For nontrivial work, state the design maturity level and top residual risks from `references/engineering-review-checklist.md`.
If tool checks were not run, state which gates remain from `references/toolchain-closure-guidelines.md`.

## Common output format

When the user asks for a design, prefer this structure:

1. **Assumptions**
2. **Design contract**
3. **State elements**
4. **Cycle trace**
5. **RTL**
6. **Verification notes**
7. **Risks / corner cases**
8. **Review status**

When the user asks for review or debug instead of new RTL, prefer this structure:

1. **Observed evidence**
2. **Likely contract violation**
3. **Minimal fix**
4. **What to recheck**
5. **Residual uncertainty**

When the user asks for a subsystem or full system, prefer this structure:

1. **Assumptions**
2. **System contract**
3. **Submodule decomposition**
4. **Interface contracts**
5. **Integration invariants**
6. **Local cycle traces**
7. **Implementation sequence**
8. **Verification strategy**
9. **Residual risks**

## Coding guidelines

- Keep combinational blocks fully assigned.
- Keep sequential blocks edge-triggered and easy to scan.
- Prefer one reset style per module.
- Use parameters for widths and depths when appropriate.
- Preserve protocol semantics over micro-optimizations.
- If a feature is ambiguous, surface the ambiguity rather than guessing.
- Avoid mixed blocking/nonblocking style in stateful logic.
- Name protocol conditions once and reuse them.
- Keep data, valid, sideband, and error fields aligned through every stall or flush.
- State whether FIFO memory read data is registered or combinational.

## High-value design patterns

### FSM

Use when the logic is control-heavy and the behavior is stateful.
Include:

- state list
- transition conditions
- outputs per state
- illegal-state handling if needed

### FIFO / buffer

Use when the block absorbs timing mismatch or decouples producer and consumer.
Include:

- occupancy tracking
- full/empty behavior
- almost-full/empty only if requested
- write/read conflict behavior

### Handshake adapter

Use when converting between different ready/valid or request/ack style interfaces.
Include:

- ordering guarantees
- backpressure behavior
- data stability rules
- throughput assumptions

### Pipeline stage

Use when the goal is timing closure or controlled latency.
Include:

- stage latency
- bypass or stall behavior
- bubble handling
- flush/reset policy

## Debugging rules

When a user shares a failure, look for:

- reset polarity mismatch
- missing default assignments
- handshake deadlock or premature valid/ready deassertion
- off-by-one counter bugs
- state machine missing transition
- data/valid misalignment across pipeline stages
- combinational feedback or multiple drivers

## Testbench guidance

Generate a testbench that is small but targeted:

- reset sequence
- one normal transaction
- one backpressure case
- one boundary case
- one error or corner case if relevant

If the user wants deeper validation, suggest assertions or coverage ideas, but keep the first pass lightweight.

A minimal testbench is useful only if it has a pass/fail signal. Prefer `$fatal`/error counters or explicit mismatch reporting over waveform-only stimulus.

## If the request is underspecified

Ask only the questions that block correct RTL:

- Is the interface ready/valid, req/ack, or something else?
- What is the reset polarity and sync style?
- What is the required latency or throughput?
- What should happen on overflow, underflow, or invalid input?
- Are there CDC or multi-clock constraints?

If the user asks for CDC, async FIFO, AXI, or another complex protocol without enough constraints, do not generate a full design from guesswork. Ask for the protocol subset, clock relationship, reset strategy, throughput target, and verification expectations.

## Skill success criteria

This skill is working well when it can:

- produce readable, synthesizable RTL for standard patterns,
- explain timing behavior without hand-waving,
- surface missing requirements early,
- and pair code with a practical verification plan.
