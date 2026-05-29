# digital-front-end-skill

A domain-specific AI Agent Skill that turns a general-purpose LLM into a disciplined digital front-end RTL design assistant. It distills authoritative engineering knowledge (IEEE standards, Arm AMBA specifications, synthesis/CDC methodology) into compact, machine-enforceable rules, and enforces a contract-first workflow: timing contract before cycle trace, cycle trace before RTL.

## Why this exists

General-purpose LLMs can generate syntactically valid Verilog, but they routinely:

- Write code first and describe timing behavior as an afterthought
- Guess FIFO boundary semantics and handshake policies instead of asking
- Mix blocking/nonblocking assignments or omit combinational defaults
- Treat bus protocol knowledge as text rather than cycle-level behavior
- Generate code that passes structural review but fails functional tests

This skill fixes those problems by encoding the engineering discipline that experienced RTL engineers follow internally, then making it explicit and mandatory for the agent.

## What it does

Given a digital front-end design request, the skill forces the agent through a structured workflow:

1. Parse and classify the request (leaf module / subsystem / full system)
2. Build a timing contract (clock, reset, handshake, latency, stall, flush, boundary)
3. Freeze the design spec (ports, widths, naming, protocol rules)
4. Identify state elements (registers, memories, movement conditions)
5. Write a cycle trace (pre-edge state, combinational condition, active-edge update, next visible state)
6. Select a design pattern (FSM, FIFO, pipeline, arbiter, etc.)
7. Generate synthesizable RTL (Verilog-first, conservative defaults, bug-pattern scan)
8. **Functional verification (mandatory)**: run tests with known inputs and expected outputs
9. Engineering review (maturity level, residual risks)
10. Verify RTL against the contract and trace

For large systems (DMA engines, bus bridges, multi-channel controllers), the skill refuses to emit monolithic RTL. Instead it produces a system contract, submodule decomposition, interface contracts, integration invariants, and a staged implementation sequence.

## What's inside

```
digital-front-end-skill/
├── SKILL.md                          # The skill definition (380 lines)
├── SKILL_CHANGELOG.md                # Iteration history (845+ lines)
├── README.md                         # This file
├── references/                       # 86 curated knowledge documents
│   ├── reference-index.md            # Task-to-reference mapping
│   ├── timing/                       # Timing semantics, contracts, naming, protocols
│   ├── architecture/                 # Hierarchy, system contracts, integration invariants
│   ├── axi-dma/                      # AXI full/Lite/Stream, DMA channel guidelines
│   ├── bus/                          # APB, AHB-Lite protocol rules
│   ├── rtl/                          # Coding guidelines, FSM/FIFO/pipeline/handshake examples
│   ├── patterns/                     # Arbiter, credit-based, CRC, ECC, width converter, etc.
│   ├── synthesis/                    # CDC, constraints, synthesis guidance
│   ├── verification/                 # TB examples, assertions, simulation loop, UVM
│   ├── debug/                        # Bug pattern library (55 patterns)
│   ├── design/                       # Power/timing/area rules, design heuristics
│   ├── project/                      # Brownfield, large module guidance
│   └── advanced/                     # Low-power, DFT, UVM, physical awareness
├── evals/
│   ├── evals.json                    # 59 evaluation prompts with 250+ assertions
│   ├── benchmark.json                # Benchmark metadata and dimension coverage
│   ├── task_benchmark.json           # 12 engineer-level A/B comparison tasks
│   ├── fixtures/                     # 4 bug fixtures for debug evaluation
│   └── trials/                       # 23 executable RTL + testbench trials
└── scripts/
    ├── skill_static_check.py         # Package health checks
    ├── eval_benchmark_check.py       # Eval dimension coverage checker
    ├── rtl_check.py                  # Run RTL fixture through Icarus Verilog
    ├── run_all_trials.py             # Batch-run all executable trials
    ├── init_task_benchmark.py        # Initialize a benchmark iteration
    ├── run_task_benchmark.py         # Prepare prompts for agent runs
    ├── grade_task_benchmark.py       # Grade outputs with deterministic assertions
    ├── rtl_complexity_check.py       # Engineering intuition complexity checks + Yosys integration
    ├── vcd_extract.py                # VCD waveform analysis: signal extraction, protocol reconstruction, violation detection
    └── yosys_extract.py             # Yosys synthesis report extraction: cell count, latch, loop, critical path
```

## Key capabilities

### Contract-first, always

The agent must write a timing contract before any RTL. This is not a suggestion — the skill's workflow makes it structurally impossible to skip. The contract includes clock domains, reset style, handshake semantics, latency, stall behavior, flush behavior, and boundary policy.

### Functional verification is mandatory

Structural self-review (Step 8) checks naming, FSM style, protocol compliance, and reset — but it does NOT verify functional correctness. Step 8b requires running functional tests with known inputs and expected outputs. This addresses the fundamental limitation that a design can pass all structural checks and still produce wrong results.

### 55 bug patterns with authoritative sources

The bug pattern library encodes known RTL failure modes discovered through 12 real projects:

| Category | Patterns | Examples |
|----------|----------|---------|
| Handshake (H1-H8) | 8 | Payload stability, ready loops, valid gating, backpressure bypass |
| Boundary (B1-B5) | 5 | FIFO full/empty, counter off-by-one, pointer reset |
| Reset (R1-R4) | 4 | Wrong FSM reset state, valid not cleared, async reset recovery |
| Pipeline (P1-P3) | 3 | Valid during stall, flush priority, data/control misalignment |
| Protocol (P4-P13) | 10 | AXI channel separation, WVALID burst, APB timing, B response hold |
| Counter (C1-C4) | 4 | Overflow, illegal FSM state, latch inference, load race |
| State Machine (SM1-SM2) | 2 | Shadow datapath, multi-bit _d in FSM |
| Data Path (DP1-DP5) | 5 | Width converter, bit-slicing, mux glitch, error paths |
| FIFO (F1-F2) | 2 | FWFT output shift, registered output race |
| CDC (D1-D2) | 2 | Gray code, ASYNC_REG |
| Memory (M1-M2) | 2 | Write-during-read hazard, ungated write port |
| Arbitration (A1) | 1 | Grant stability under backpressure |
| Clock/Power (CL1) | 1 | Clock gating glitch |
| Counter/Status (P14-P18) | 5 | Auto-reload race, dedicated clear, status release, pipeline latency |
| Verification (V1) | 1 | Structural PASS but functional FAIL |

### Synthesis awareness

RTL is verified with Yosys 0.45 open-source synthesis. Patterns include:
- Clock-enable over manual clock gating (P1)
- Casez priority encoder for balanced decode trees (A1)
- $clog2 for parameterized width discipline (A3)
- No latch inference from incomplete combinational blocks (E2)

### Multi-module integration

Sub-agent delegation with interface contracts (`interface_contract.md`) ensures port width consistency across independently generated modules.

## Design philosophy

### Refuse to guess

When requirements are incomplete (e.g., "design a FIFO" without specifying full+read behavior), the skill forces the agent to ask or state conservative assumptions. Silent invention of protocol semantics is treated as a bug, not a feature.

### Large systems get decomposed

A request for "complete AXI DMA engine" does not produce 500 lines of guessed RTL. It produces a system contract, submodule decomposition, interface contracts, integration invariants, and a recommendation for which leaf module to implement first.

### CDC is not negotiable

Multi-bit clock domain crossings cannot be fixed by "just add two flops per bit." The skill refuses to generate guessed CDC RTL and requires an explicit safe crossing pattern (handshake, snapshot, gray counter, or async FIFO).

### Verilog-first

Default output is plain Verilog, not SystemVerilog. This minimizes synthesis tool compatibility issues. SystemVerilog features are used only when explicitly requested or when the task genuinely requires them (e.g., SVA assertions).

## Protocol coverage

All protocol-specific rules are grounded in official specifications:

| Protocol | Source | Reference files |
|----------|--------|-----------------|
| AXI4 Full | Arm IHI 0022 | axi-full-guidelines, axi-multi-outstanding-guidelines, axi-dma-channel-guidelines |
| AXI4-Lite | Arm IHI 0022 | axi-lite-guidelines |
| APB | Arm IHI 0024 | apb-guidelines |
| AHB-Lite | Arm IHI 0033 | ahb-lite-guidelines |
| AXI4-Stream | Arm IHI 0051 | axi-stream-guidelines |

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

## Validated projects (12)

| Project | Type | Tests | Key findings |
|---------|------|-------|-------------|
| CDMA x6 | AXI DMA | Multi-round | AW/W/B channel separation, 6 rounds |
| Timer | Counter | 16/16 | P14-P17: trigger race, status register |
| INTC | Interrupt | 12/12 | PSLVERR scope, combinational output timing |
| CRC | Data path | 7/7 | P18: pipeline latency, functional verification |
| Async FIFO | CDC | 10/10 | CDC guidelines quality verified |
| AHB-Lite | Bus | 11/11 | Read data timing, simulation loop |
| DMA System | Multi-module | 1/2 | Interface contracts, SVA compatibility |
| UART | Multi-module | 6/6 | Interface contract verified |
| Crossbar | Parameterized | 0/4 | Structural vs functional gap |
| Arbiter | Arbitration | 6/6 | Synthesis awareness, mask reset bug |
| Clock Gate | Low-power | 8/8 | P1 rule verified, zero defects |
| SPI Master | Complex FSM | 5/5 | 6-state FSM, Yosys synthesis |

## Usage

### As a Claude Code skill

Place the `digital-front-end-skill` directory under your project and reference it in your CLAUDE.md or load it via the skill mechanism. The agent will automatically follow the contract-first workflow for any RTL design request.

### Running static checks

```bash
python scripts/skill_static_check.py
```

### Running eval benchmark coverage

```bash
python scripts/eval_benchmark_check.py
```

### Running executable trials

```bash
python scripts/rtl_check.py --case evals/trials/rr_arbiter_trial
```

### Running all trials

```bash
python scripts/run_all_trials.py
```

## License

This project is a curated engineering knowledge base and evaluation framework. See individual reference files for attribution of authoritative sources.
