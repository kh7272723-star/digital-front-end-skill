# Reference Index

Task-to-reference mapping. Read this file when you need the right reference for a specific design task.

## Timing and protocol

- Timing semantics, assignment ordering, or cycle explanation: `references/timing/timing-semantics.md`, `references/timing/timing-contract-template.md`, `references/timing/cycle-trace-guidelines.md`
- Source-to-rule conversion or methodology grounding: `references/timing/authority-synthesis.md`
- Protocol-specific AXI, AXI-Lite, AXI-Stream, APB, AHB, ACE, or CHI rules: `references/timing/protocol-authority-map.md` before adding or changing rules
- Naming or interface style: `references/timing/naming-guidelines.md`
- Ready/valid, req/ack, FIFO, pipeline handoff: `references/timing/protocol-semantics.md`, then `references/timing/cycle-trace-guidelines.md`
- Protocol completeness: `references/timing/protocol-edge-case-checklist.md`
- Clock/reset: `references/timing/clock-reset-guidelines.md`; CDC crossing and async FIFO: `references/synthesis/cdc-guidelines.md` (includes complete async FIFO template with gray-coded pointers, dual 2FF synchronizers, SDC constraint syntax, and MTBF guidance)

## Architecture and hierarchy

- Complete DMA, AXI subsystem, cache, NoC, bus bridge, multi-channel engine, or full top integration: `references/architecture/hierarchical-design-guidelines.md`, `references/architecture/system-contract-template.md`, `references/architecture/interface-contract-template.md`, `references/architecture/integration-invariants.md`
- AXI DMA architecture or slicing: also `references/axi-dma/axi-dma-planning-example.md`, `references/axi-dma/axi-dma-channel-guidelines.md`, `references/architecture/subsystem-rtl-slicing-guidelines.md`
- AXI full masters/slaves/bridges: `references/axi-dma/axi-full-guidelines.md`. Multi-ID/outstanding: also `references/axi-dma/axi-multi-outstanding-guidelines.md`
- DMA descriptor parsing or burst command generation: also `references/axi-dma/dma-descriptor-burst-guidelines.md`
- AXI-Lite register blocks or small slaves: `references/axi-dma/axi-lite-guidelines.md`
- APB, AHB-Lite, or AXI-Stream blocks: `references/bus/apb-guidelines.md`, `references/bus/ahb-lite-guidelines.md`, `references/axi-dma/axi-stream-guidelines.md`
- Architecture tradeoffs: `references/architecture/tradeoff-guidance.md` and `references/architecture/micro-arch-decisions.md`
- Staged implementation: `references/architecture/staged-bringup-guidelines.md`
- Arbiters: `references/patterns/advanced-patterns.md` and `references/patterns/arbiter-examples.md`
- **Underspecified or vague requirements → structured contract:** `references/architecture/requirement-extraction-template.md` — use BEFORE writing any timing contract; classifies dimensions as Required/Implied/Assumed/Unknown, documents design decisions
- **Sub-agent delegation:** `references/architecture/sub-agent-delegation.md` — prompt template, inline critical rules, multi-module integration rules
- **Pipeline design patterns:** `references/architecture/pipeline-design-patterns.md` — feed-forward, feedback, multi-rate, split-merge, cut-through vs store-forward; RTL templates + common errors + backpressure propagation rules
- **Memory hierarchy & buffer strategy:** `references/architecture/memory-hierarchy.md` — FIFO depth formulas, SKID buffer, ping-pong, arbitration comparison, prefetch strategies, WSTRB alignment
- **Performance analysis:** `references/architecture/performance-analysis.md` — throughput calculation, latency budgeting, backpressure deadlock detection, utilization analysis, Little's Law for hardware

## Specialized patterns

- Specialized RTL/IP patterns: `references/patterns/credit-based-examples.md`, `references/patterns/rate-limiter-examples.md`, `references/patterns/retry-buffer-examples.md`, `references/patterns/utility-examples.md`, `references/patterns/crc-examples.md`, `references/patterns/ecc-examples.md`, `references/patterns/width-converter-examples.md`, `references/patterns/frame-assembler-examples.md`, `references/patterns/multi-bank-memory-examples.md`, `references/patterns/cam-examples.md`
- Req/ack adapters and counters: `references/patterns/advanced-patterns.md`; CDC planning: `references/synthesis/cdc-guidelines.md`

## RTL generation and review

- RTL generation or review: `references/rtl/rtl-writing-guidelines.md`, then `references/rtl/full-module-examples.md` or the closest example file
- Pattern selection: `references/rtl/rtl-patterns.md`
- FSM rules and examples: `references/rtl/fsm-examples.md`
- FIFO naming and patterns: `references/rtl/fifo-examples.md`, `references/timing/naming-guidelines.md`
- Bug pattern matching: `references/debug/bug-pattern-library.md` and match the module type to known patterns
- Final review: `references/verification/engineering-review-checklist.md`
- Existing project: `references/project/project-adaptation-guidelines.md`, `references/project/brownfield-guidance.md`. Large modules: `references/project/large-module-guidance.md`

## Verification

- Verification requests: `references/verification/verification-guidance.md`, `references/verification/tb-examples.md`, `references/verification/assertion-examples.md`, and for SVA `references/verification/assertion-quality-checklist.md`
- **Testbench pitfalls (mandatory):** `references/verification/icarus-common-pitfalls.md` — 15 Icarus-specific pitfalls that wasted simulation iterations across R5-R8 experiments. Read BEFORE writing any testbench.
- Verification planning: `references/verification/verification-matrix-template.md`, `references/verification/verification-planning.md`
- **RTL self-review checklist:** `references/verification/self-review-checklist.md` — complete 13-category 65-item checklist used in SKILL.md Step 8
- Coverage models: `references/verification/coverage-models.md`
- Formal properties: `references/verification/formal-properties.md`
- UVM templates: `references/verification/uvm-templates.md`
- If an RTL fixture is provided, use `scripts/rtl_check.py --case <fixture_dir>` when Icarus Verilog is available
- Tool-driven RTL verification or iterative debug: `references/design/tool-driven-workflow.md`
- Golden reference methodology: `references/verification/golden-reference-guide.md` — functional verification strategies for all module types, testbench templates for known I/O pairs, software reference models, readback scoreboards, data integrity scoreboards, invariant checkers, and latency checkers

## Signoff and closure

- Signoff, lint, CDC, synthesis, timing, formal claims: `references/synthesis/toolchain-closure-guidelines.md`, `references/synthesis/synthesis-guidance.md`, `references/synthesis/constraint-guidance.md`

## Design intuition

- **Design principles (start here — applies to every RTL task):** `references/design/design-principles.md` — 6 core principles with active-search questions; principle-to-pattern mapping for all 57 patterns
- Design heuristics, sizing guidelines, red flags: `references/design/design-heuristics.md`
- Engineering intuition checklist (automatable): `references/design/engineering-intuition-checklist.md`; run `scripts/rtl_complexity_check.py` for automated checks

## Advanced methodology

- Low-power (clock gating, power domains, PSM, retention, isolation, DVFS): `references/advanced/low-power-guidelines.md`; power/timing/area rules: `references/design/power-timing-area.md`
- DFT (scan, BIST, testability): `references/advanced/dft-guidelines.md`
- UVM (constrained-random, coverage closure): `references/advanced/uvm-guidelines.md`
- Synthesis/timing closure (SDC, critical path): `references/synthesis/synthesis-timing-closure-guidelines.md`
- Formal verification (SVA properties, proofs): `references/synthesis/formal-verification-guidelines.md`
- Physical awareness (floorplan-aware RTL, macro placement, congestion, wire delay, CTS, area): `references/advanced/physical-awareness-guidelines.md`

## Maintenance

- Skill package maintenance: run `scripts/skill_static_check.py`
- Eval benchmark coverage: run `scripts/eval_benchmark_check.py`
- Task benchmark: `scripts/init_task_benchmark.py` and `scripts/grade_task_benchmark.py`
