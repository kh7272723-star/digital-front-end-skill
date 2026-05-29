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

Given a digital front-end design request, the skill forces the agent through a structured 12-step workflow:

1. Parse and classify the request (leaf module / subsystem / full system)
2. Build a timing contract (clock, reset, handshake, latency, stall, flush, boundary)
3. Freeze the design spec (ports, widths, naming, protocol rules)
4. Identify state elements (registers, memories, movement conditions)
5. Write a cycle trace (pre-edge, combinational condition, active-edge update, next visible state)
6. Choose a design pattern (FSM, FIFO, pipeline, arbiter, etc.)
7. Generate synthesizable RTL (Verilog-first, conservative defaults, bug-pattern scan)
8. Structural self-review (57-item checklist across 10 categories)
8b. Functional verification (mandatory — golden reference methodology, 6 strategies)
8c. Design principle review (mandatory — 6 principles, active-search questions)
9. Simulation loop (lint → compile → simulate → VCD analysis → fix → re-simulate)
10. Synthesis feedback (Yosys: latch/loop/critical-path/cell-count checks)
11. Review and iterate
12. Verify timing against contract and trace

For large systems (DMA engines, bus bridges, multi-channel controllers), the skill refuses to emit monolithic RTL. Instead it produces a system contract, submodule decomposition, interface contracts, integration invariants, and a staged implementation sequence.

## What's inside

```
digital-front-end-skill/
├── SKILL.md                          # Skill definition (415 lines)
├── SKILL_CHANGELOG.md                # Full iteration history
├── README.md / README_CN.md          # This file
├── references/                       # 87 curated knowledge documents
│   ├── reference-index.md            # Task-to-reference mapping
│   ├── timing/                       # Timing semantics, contracts, naming, protocols
│   ├── architecture/                 # Hierarchy, system contracts, integration invariants
│   ├── axi-dma/                      # AXI full/Lite/Stream, DMA channel guidelines
│   ├── bus/                          # APB, AHB-Lite protocol rules
│   ├── rtl/                          # Coding guidelines, FSM/FIFO/pipeline/handshake examples
│   ├── patterns/                     # Arbiter, credit-based, CRC, ECC, width converter, etc.
│   ├── synthesis/                    # CDC, constraints, synthesis guidance
│   ├── verification/                 # TB examples, assertions, simulation loop, golden reference
│   ├── debug/                        # Bug pattern library (57 patterns)
│   ├── design/                       # **6 design principles**, heuristics, PTA rules, intuition checklist
│   ├── project/                      # Brownfield, large module guidance
│   └── advanced/                     # Low-power, DFT, UVM, physical awareness
├── evals/
│   ├── evals.json                    # 63 evaluation prompts with 250+ assertions
│   ├── benchmark.json                # Benchmark metadata and dimension coverage
│   ├── task_benchmark.json           # 12 engineer-level A/B comparison tasks
│   ├── fixtures/                     # 4 bug fixtures for debug evaluation
│   └── trials/                       # 23 executable RTL + testbench trials
├── scripts/                          # 10 Python automation scripts
│   ├── skill_static_check.py         # Package health checks
│   ├── eval_benchmark_check.py       # Eval dimension coverage checker
│   ├── rtl_check.py                  # Single trial compile + sim
│   ├── run_all_trials.py             # Batch-run all 23 trials
│   ├── rtl_complexity_check.py       # Engineering intuition checks + Yosys integration
│   ├── vcd_extract.py                # VCD waveform analysis + protocol reconstruction
│   └── yosys_extract.py              # Yosys synthesis report extraction
└── projects/                         # 13 validated RTL projects
    ├── test-cdc-capture/
    ├── test-dma-datapath/
    ├── test-dma-subsystem/
    ├── test-fuzzy-spec/
    ├── test-lowpower-soc/
    └── test-validation/
```

## Key capabilities

### 6 Design Principles (core innovation)

The skill's 57 bug patterns are organized under 6 core design principles. Instead of scanning 57 patterns one by one, the agent applies these principles as an "active search" lens to catch functional bugs before they become patterns:

| # | Principle | Key Question |
|---|-----------|-------------|
| P1 | Every Signal Has a Timing Contract | Is every output's signal type (pulse/level/registered) documented? |
| P2 | Every FSM Must Find Its Way Home | Can every state find a path back to IDLE? Abort paths for intermediate states? |
| P3 | Every Register Has a Known Value | What value does every register hold after reset? Uninitialized memories? |
| P4 | Independent Things Stay Independent | Are AXI channels, clock domains, read/write paths decoupled? |
| P5 | The Physical World Always Wins | Are power sequences, isolation, operand gating correct for physical implementation? |
| P6 | Boundaries Are Where Bugs Hide | Does every module boundary have an explicit contract? |

See `references/design/design-principles.md` for the full active-search question set.

### Contract-first, always

The agent must write a timing contract before any RTL. This is not a suggestion — the skill's workflow makes it structurally impossible to skip. The contract includes clock domains, reset style, handshake semantics, latency, stall behavior, flush behavior, and boundary policy.

### Functional verification is mandatory (Golden Reference)

Step 8b requires running functional tests with known inputs and expected outputs. Six golden reference strategies cover every module type: known I/O pairs (CRC/ECC), software reference model (algorithms), write-readback scoreboard (register blocks), data integrity scoreboard (DMA/FIFO), invariant checking (arbiters), and latency verification (pipelines). All 6 strategies validated across 10 real projects.

### 57 bug patterns with authoritative sources

The bug pattern library encodes known RTL failure modes discovered through 13 real projects:

| Category | Patterns | Examples |
|----------|----------|---------|
| Handshake (H1-H8) | 8 | Payload stability, ready loops, valid gating, backpressure bypass |
| Protocol (P4-P13) | 10 | AXI channel separation, WVALID burst, APB timing, B response hold |
| Counter/Status (P14-P18) | 5 | Auto-reload race, dedicated clear, status release, pipeline latency |
| State Machine (SM1-SM3) | 3 | Shadow datapath, multi-bit _d in FSM, FSM abort path |
| Data Path (DP1-DP5) | 5 | Width converter, bit-slicing, mux glitch, error paths |
| RTL Correctness (E1-E8) | 8 | Latch inference, multi-driver, truncation, blocking/nonblocking |
| FIFO (F1-F2) | 2 | FWFT output shift, registered output race |
| CDC (D1-D2) | 2 | Gray code, ASYNC_REG |
| Low-Power (LP1-LP7) | 7 | Isolation timing, retention handshake, PSM states, CDC pulse sync, DVFS gate, operand isolation, pulse transition |
| Physical (PH1-PH4) | 4 | Registered I/O, fanout control, SRAM proximity, bus grouping |
| Verification (V1) | 1 | Structural PASS but functional FAIL |

### Simulation loop + VCD analysis

Full closed-loop verification: `iverilog` compile → `vvp` simulate → parse PASS/FAIL → `vcd_extract.py` waveform analysis (signal timeline extraction, AXI/APB protocol reconstruction, violation detection) → bug pattern matching → minimal fix → re-simulate. Maximum 3 fix-and-rerun iterations.

### Synthesis awareness (Yosys)

Post-simulation synthesis check: latch detection, combinational loop detection, critical path analysis (ltp), cell count verification. `yosys_extract.py` for automated report extraction.

### Multi-module integration

Sub-agent delegation with interface contracts ensuring port width consistency and signal type alignment across independently generated modules. Validated on UART (4 sub-agents), DMA subsystem (4 sub-agents), and Low-Power SoC (5 sub-agents).

## Design philosophy

### Refuse to guess

When requirements are incomplete, the skill forces the agent to ask or state conservative assumptions. Silent invention of protocol semantics is treated as a bug, not a feature.

### Large systems get decomposed

A request for "complete AXI DMA engine" does not produce 500 lines of guessed RTL. It produces a system contract, submodule decomposition, interface contracts, integration invariants, and a recommendation for which leaf module to implement first.

### CDC is not negotiable

Multi-bit clock domain crossings cannot be fixed by "just add two flops per bit." The skill refuses to generate guessed CDC RTL and requires an explicit safe crossing pattern.

### Verilog-first

Default output is plain Verilog. SystemVerilog features are used only when explicitly requested or when the task genuinely requires them.

## Protocol coverage

| Protocol | Source | Reference files |
|----------|--------|-----------------|
| AXI4 Full | Arm IHI 0022 | axi-full-guidelines, axi-multi-outstanding, axi-dma-channel |
| AXI4-Lite | Arm IHI 0022 | axi-lite-guidelines |
| APB | Arm IHI 0024 | apb-guidelines |
| AHB-Lite | Arm IHI 0033 | ahb-lite-guidelines |
| AXI4-Stream | Arm IHI 0051 | axi-stream-guidelines |

## Design pattern catalog (18)

Ready/valid register slice, skid buffer, FIFO, pipeline stage, FSM (two-process), arbiter (fixed/round-robin), credit-based flow control, retry buffer, width converter, CRC generator, SECDED ECC, multi-bank memory scheduler, counter/register slice, req/ack adapter, rate limiter, frame assembler, CAM, AXI DMA slice.

## Validated projects (13)

| Project | Type | Tests | Key findings |
|---------|------|-------|-------------|
| CDMA x6 | AXI DMA | Multi-round | AW/W/B channel separation, 6-round iteration |
| Timer | Counter | 16/16 | P14-P17: trigger race, status register |
| INTC | Interrupt | 12/12 | PSLVERR scope, combinational output timing |
| CRC | Data path | 7/7 | P18: pipeline latency, functional verification |
| Async FIFO | CDC | 10/10 | CDC guidelines quality verified |
| AHB-Lite | Bus | 11/11 | Read data timing, simulation loop validated |
| DMA System | Multi-module | 1/2 | Interface contracts, SVA compatibility |
| UART | Multi-module | 6/6 | Interface contract pattern verified |
| Crossbar | Parameterized | 0/4 | Structural vs functional gap confirmed |
| Arbiter | Arbitration | 6/6 | Synthesis awareness, mask reset bug |
| Clock Gate | Low-power | 8/8 | P1 rule verified, zero design defects |
| SPI Master | Complex FSM | 5/5 | 6-state FSM, first Yosys synthesis pass |
| **Low-Power SoC** | **Subsystem** | **28/28** | **LP1-LP7 + PH1-PH4 validated, SM3+LP7 patterns** |

## Usage

### As a Claude Code skill

Place the skill under `~/.claude/skills/` or reference it in your project's CLAUDE.md. The agent will automatically follow the contract-first workflow for any RTL design request.

### Running static checks

```bash
python scripts/skill_static_check.py
python scripts/eval_benchmark_check.py
```

### Running trials

```bash
python scripts/rtl_check.py --case evals/trials/rr_arbiter_trial
python scripts/run_all_trials.py              # batch all 23
```

### VCD waveform analysis

```bash
python scripts/vcd_extract.py dump.vcd --signals WVALID,WDATA --range 0:50000
python scripts/vcd_extract.py dump.vcd --protocol axi-write
python scripts/vcd_extract.py dump.vcd --find-violation stall-data-change
```

### Yosys synthesis check

```bash
python scripts/yosys_extract.py --top <module> --sources <files>
```

## License

This project is a curated engineering knowledge base and evaluation framework. See individual reference files for attribution of authoritative sources (IEEE, Arm, SNUG, etc.).
