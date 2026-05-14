# digital-front-end-skill

A domain-specific AI Agent Skill that turns a general-purpose LLM into a disciplined digital front-end RTL design assistant. It distills authoritative engineering knowledge (IEEE standards, Arm AMBA specifications, synthesis/CDC methodology) into compact, machine-enforceable rules, and enforces a contract-first workflow: timing contract before cycle trace, cycle trace before RTL.

## Why this exists

General-purpose LLMs can generate syntactically valid Verilog, but they routinely:

- Write code first and describe timing behavior as an afterthought
- Guess FIFO boundary semantics and handshake policies instead of asking
- Mix blocking/nonblocking assignments or omit combinational defaults
- Treat bus protocol knowledge as text rather than cycle-level behavior

This skill fixes those problems by encoding the engineering discipline that experienced RTL engineers follow internally, then making it explicit and mandatory for the agent.

## What it does

Given a digital front-end design request, the skill forces the agent through a structured workflow:

1. Parse and classify the request (leaf module / subsystem / full system)
2. Build a timing contract (clock, reset, handshake, latency, stall, flush, boundary)
3. Freeze the design spec (ports, widths, naming, protocol rules)
4. Identify state elements (registers, memories, movement conditions)
5. Write a cycle trace (pre-edge state, combinational condition, active-edge update, next visible state)
6. Select a design pattern (FSM, FIFO, pipeline, arbiter, etc.)
7. Generate synthesizable RTL (Verilog-first, conservative defaults)
8. Generate verification plan (testbench skeleton, directed tests, assertions)
9. Engineering review (maturity level, residual risks)
10. Verify RTL against the contract and trace

For large systems (DMA engines, bus bridges, multi-channel controllers), the skill refuses to emit monolithic RTL. Instead it produces a system contract, submodule decomposition, interface contracts, integration invariants, and a staged implementation sequence.

## What's inside

```
digital-front-end-skill/
├── SKILL.md                          # The skill definition (entry point)
├── README.md                         # This file
├── references/                       # 60 curated knowledge documents
│   ├── authority-synthesis.md        # How authoritative sources become rules
│   ├── timing-semantics.md           # Cycle-level timing language
│   ├── timing-contract-template.md   # Contract template for all designs
│   ├── cycle-trace-guidelines.md     # How to write cycle traces
│   ├── rtl-writing-guidelines.md     # RTL coding rules
│   ├── rtl-patterns.md               # Pattern catalog and selection logic
│   ├── naming-guidelines.md          # Signal naming conventions
│   ├── protocol-authority-map.md     # Maps protocols to their official specs
│   ├── axi-full-guidelines.md        # AXI4 full master/slave rules
│   ├── axi-lite-guidelines.md        # AXI-Lite register block rules
│   ├── axi-dma-channel-guidelines.md # DMA channel design rules
│   ├── axi-dma-planning-example.md   # DMA architecture planning walkthrough
│   ├── apb-guidelines.md             # APB protocol rules
│   ├── ahb-lite-guidelines.md        # AHB-Lite protocol rules
│   ├── axi-stream-guidelines.md      # AXI-Stream protocol rules
│   ├── cdc-guidelines.md             # Clock domain crossing safety
│   ├── hierarchical-design-guidelines.md  # Large system decomposition
│   ├── staged-bringup-guidelines.md  # Staged implementation sequence
│   ├── engineering-review-checklist.md    # Design maturity assessment
│   ├── verification-matrix-template.md    # Verification planning template
│   ├── toolchain-closure-guidelines.md    # Signoff gate definitions
│   ├── tradeoff-guidance.md          # Microarchitecture tradeoff framework
│   ├── ...                           # 38 more pattern/example/guideline files
│   └── frame-assembler-examples.md
├── evals/
│   ├── evals.json                    # 44 evaluation prompts with 250+ assertions
│   ├── benchmark.json                # Benchmark metadata and dimension coverage
│   ├── task_benchmark.json           # 12 engineer-level A/B comparison tasks
│   ├── task-benchmark.md             # Benchmark workflow documentation
│   ├── fixtures/                     # 4 bug fixtures for debug evaluation
│   │   ├── ready_valid_stall_bug/    # valid/data changes during downstream stall
│   │   ├── fifo_boundary_bug/        # write accepted while FIFO is full
│   │   ├── fsm_reset_release_bug/    # FSM stuck after reset deassertion
│   │   └── pipeline_stall_bug/       # pipeline data advances during stall
│   └── trials/                       # 19 executable RTL + testbench trials
│       ├── credit_counter_trial/
│       ├── rr_arbiter_trial/
│       ├── skid_buffer_trial/
│       ├── axi_read_tracker_trial/
│       ├── axi_write_tracker_trial/
│       ├── dma_burst_planner_trial/
│       ├── vfs_sw_hw_comm_hierarchy_trial/
│       ├── multi_bank_scheduler_trial/
│       └── ... (11 more)
└── scripts/
    ├── skill_static_check.py         # Package health checks
    ├── eval_benchmark_check.py       # Eval dimension coverage checker
    ├── rtl_check.py                  # Run RTL fixture through Icarus Verilog
    ├── run_all_trials.py             # Batch-run all executable trials
    ├── init_task_benchmark.py        # Initialize a benchmark iteration
    ├── run_task_benchmark.py         # Prepare prompts for agent runs
    └── grade_task_benchmark.py       # Grade outputs with deterministic assertions
```

## Design philosophy

### Contract-first, always

The agent must write a timing contract before any RTL. This is not a suggestion -- the skill's workflow makes it structurally impossible to skip. The contract includes clock domains, reset style, handshake semantics, latency, stall behavior, flush behavior, and boundary policy.

### Refuse to guess

When requirements are incomplete (e.g., "design a FIFO" without specifying full+read behavior), the skill forces the agent to ask or state conservative assumptions. Silent invention of protocol semantics is treated as a bug, not a feature.

### Large systems get decomposed

A request for "complete AXI DMA engine" does not produce 500 lines of guessed RTL. It produces a system contract, submodule decomposition, interface contracts, integration invariants, and a recommendation for which leaf module to implement first.

### CDC is not negotiable

Multi-bit clock domain crossings cannot be fixed by "just add two flops per bit." The skill refuses to generate guessed CDC RTL and requires an explicit safe crossing pattern (handshake, snapshot, gray counter, or async FIFO).

### Verilog-first

Default output is plain Verilog, not SystemVerilog. This minimizes synthesis tool compatibility issues. SystemVerilog features are used only when explicitly requested or when the task genuinely requires them (e.g., SVA assertions).

## Evaluation framework

The project includes a two-layer evaluation system:

### Layer 1: Prompt coverage (evals.json)

44 prompts covering 14 quality dimensions:

| Dimension | What it tests |
|-----------|---------------|
| module_timing | Leaf RTL timing contracts, state elements, cycle traces |
| protocol_axi_full | AXI full channel, burst, outstanding, response semantics |
| protocol_axi_lite | AXI-Lite register blocks and small slaves |
| protocol_axi_dma | DMA ordering, response tracking, completion, slice planning |
| protocol_apb | APB setup/access phases, wait states, byte strobes |
| protocol_ahb_lite | AHB-Lite address/data phase alignment |
| protocol_axi_stream | AXI-Stream payload, sideband, backpressure |
| system_hierarchy | Large-system decomposition, interface contracts, invariants |
| verification_closure | Verification matrices, tool evidence, signoff discipline |
| debug_review | First-divergent-cycle reasoning and protocol bug review |
| cdc_safety | CDC refusal, safe pattern selection |
| project_adaptation | Existing repo convention adaptation |
| synthesis_timing | Synthesis inference, constraints, timing closure awareness |
| specialized_rtl_patterns | Credits, retry buffers, width converters, ECC, multi-bank |

Each prompt has 5-7 deterministic assertions checked by regex matching.

### Layer 2: Engineer-level task benchmark (task_benchmark.json)

12 tasks that simulate real RTL development, with A/B comparison:
- **with_skill**: agent runs with `digital-front-end-skill` loaded
- **baseline**: agent runs without the skill

Grading is automated by `scripts/grade_task_benchmark.py`, producing structured `benchmark.md` and `benchmark.json` reports.

### Executable trials

19 trials contain synthesizable RTL + testbenches + manifest files. Each can be compiled and simulated with Icarus Verilog via `scripts/rtl_check.py`. This provides hard evidence that generated code passes simulation, not just that it looks correct.

### Bug fixtures

4 fixtures encode real RTL bug patterns (stall hold violation, boundary policy error, reset release issue, pipeline data corruption). Each has a manifest specifying expected failure signatures, used to evaluate the agent's debug capability.

## Usage

### As a Claude Code skill

Place the `digital-front-end-skill` directory under your project and reference it in your CLAUDE.md or load it via the skill mechanism. The agent will automatically follow the contract-first workflow for any RTL design request.

### Running static checks

```bash
python scripts/skill_static_check.py
```

Validates: evals JSON schema, reference files listed in SKILL.md, banned legacy terminology (fire/push/pop), fixture manifests.

### Running eval benchmark coverage

```bash
python scripts/eval_benchmark_check.py
```

Checks that all 14 dimensions have sufficient eval coverage and that executable trials exist for required patterns.

### Running executable trials

```bash
python scripts/rtl_check.py --case evals/trials/rr_arbiter_trial
```

Compiles and simulates the trial with Icarus Verilog, then checks the output against the manifest's expected result.

### Running all trials

```bash
python scripts/run_all_trials.py
```

Batch-runs all 19 executable trials and reports pass/fail status.

### Running the task benchmark

```bash
# Initialize iteration
python scripts/init_task_benchmark.py --iteration 1

# (Run agent with and without skill, save outputs)

# Grade the iteration
python scripts/grade_task_benchmark.py --iteration-dir ../digital-front-end-skill-workspace/iteration-1
```

## Protocol coverage

All protocol-specific rules are grounded in official specifications:

| Protocol | Source | Reference files |
|----------|--------|-----------------|
| AXI4 Full | Arm IHI 0022 | axi-full-guidelines, axi-multi-outstanding-guidelines, axi-dma-channel-guidelines |
| AXI4-Lite | Arm IHI 0022 | axi-lite-guidelines |
| APB | Arm IHI 0024 | apb-guidelines |
| AHB-Lite | Arm IHI 0033 | ahb-lite-guidelines |
| AXI4-Stream | Arm IHI 0051 | axi-stream-guidelines |

The `references/protocol-authority-map.md` file documents the mapping from each protocol to its authoritative source and the local reference files derived from it.

## Design pattern catalog

The skill covers 18 reusable RTL patterns:

| Pattern | Use case |
|---------|----------|
| Ready/valid register slice | Single-cycle decoupling with backpressure |
| Skid buffer | Two-entry buffer for throughput under backpressure |
| FIFO | Bordered storage with ordering guarantees |
| Pipeline stage | Timing closure with controlled latency |
| FSM (two-process) | Multi-stage control with explicit states |
| Arbiter (fixed/round-robin) | Shared resource arbitration |
| Credit-based flow control | Long-latency backpressure with credit accounting |
| Retry buffer | ACK/NAK replay with bounded in-flight window |
| Width converter | Narrow-to-wide or wide-to-narrow streaming |
| CRC generator | Error detection for data paths |
| SECDED ECC | Single-error correct, double-error detect |
| Multi-bank memory scheduler | Bank conflict detection with fair arbitration |
| Counter / register slice | Simple state tracking |
| Req/ack adapter | Protocol conversion |
| Rate limiter | Throughput bounding |
| Frame assembler | Packet framing with sideband |
| CAM | Content-addressable lookup |
| AXI DMA slice | Descriptor parsing, burst planning, completion tracking |

## Maturity levels

The skill defines four design maturity levels to prevent overclaiming:

- **Sketch**: Behavior is plausible, but contracts and checks are incomplete.
- **Reviewable RTL**: Contract, cycle trace, RTL, and directed checks exist.
- **Integration-ready RTL**: Interfaces, reset, error, backpressure, and invariants are checked.
- **Signoff candidate**: Lint, CDC, simulation, formal/coverage, synthesis, and timing risks are addressed by project tools.

The agent is required to state the maturity level and top residual risks before finalizing any nontrivial design.

## License

This project is a curated engineering knowledge base and evaluation framework. See individual reference files for attribution of authoritative sources.
