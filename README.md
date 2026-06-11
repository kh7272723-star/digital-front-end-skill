# digital-front-end-skill

A domain-specific AI Agent Skill that turns a general-purpose LLM into a disciplined digital front-end RTL design assistant. It distills authoritative engineering knowledge (IEEE standards, Arm AMBA specifications, synthesis/CDC methodology) into compact, machine-enforceable rules, and enforces a contract-first workflow: timing contract before cycle trace, cycle trace before RTL.

## Latest release: v2026.06.11-r3

**r3 — Engineering design pattern hardening:**

**FSM Split Mandatory (C8 R->M + C8a threshold):** >=4 states AND >=6 control outputs must use separate `_fsm.v` file. Main module must not contain `case(cstate)`. FSM file must not instantiate IP.

**CDC Analysis Gate (Step 7b):** L1/L2 designs must produce `cdc_report.md` before RTL self-review. New `--phase cdc` gate. Hard rules: cross-domain control -> `xpm_cdc_pulse`, cross-domain data -> `xpm_fifo_async`, no manual 2-FF synchronizers.

**AXI Channel Split Template:** Generic five-module AW/W/B/AR/R independent channel separation pattern. Pure structural wrapper, zero logic.

**Naming Convention (N14):** Multi-instance numeric prefix (`ch0_`, `ch1_`).
## Why this exists

General-purpose LLMs can generate syntactically valid Verilog, but they routinely:

- Write code first and describe timing behavior as an afterthought
- Guess FIFO boundary semantics and handshake policies instead of asking
- Mix blocking/nonblocking assignments or omit combinational defaults
- Treat bus protocol knowledge as text rather than cycle-level behavior
- Generate code that passes structural review but fails functional tests

This skill fixes those problems by encoding the engineering discipline that experienced RTL engineers follow internally, then making it explicit and mandatory for the agent.

## What it does

Given a digital front-end design request, the skill forces the agent through a structured workflow with **three-tier complexity gating** (L0/L1/L2) and **distributed principle checkpoints** (2a/5a/8c):

1. Parse and classify the request (L0: trivial, L1: leaf, L2: subsystem — auto-skip checkpoints for L0)
2. Build a timing contract (clock, reset, handshake, latency, stall, flush, boundary)
2a. Principle check — P4 Independence + P6 Boundaries (skipped for L0)
3. Freeze the design spec (ports, widths, naming, protocol rules)
4. Identify state elements (registers, memories, movement conditions)
5. Write a cycle trace (pre-edge, combinational condition, active-edge update, next visible state)
5a. Principle check — P1 Timing Contract + P2 FSM Safety (LITE mode for linear FSMs)
6. Choose a design pattern (FSM, FIFO, pipeline, arbiter, etc.)
7. Generate synthesizable RTL only (no TB), then pass the post-rtl gate with RTL-only compile evidence
8. Structural self-review (79-item checklist across 13 categories)
8c. Principle check — P3 Known Values + P5a Output Discipline (P5b Physical Impl for L2 only)
8b. Functional verification plan only (golden reference methodology, scoreboard plan, no TB generation)
9. L2 per-module TB + guarded simulation + sim_log_gate + module verification matrix
9-EXIT. Module-sim/pre-integration gate; integration TB is still forbidden before PASS
10. Integration TB + guarded simulation + principle-driven debug after pre-integration passes
10-EXIT. Post-sim gate
11. Final delivery gate before claiming PASS

For large systems (DMA engines, bus bridges, multi-channel controllers), the skill refuses to emit monolithic RTL. Instead it produces a system contract, submodule decomposition, interface contracts, integration invariants, and a staged implementation sequence.

## What's inside

```
digital-front-end-skill/
├── SKILL.md                          # Skill definition (~345 lines, three-tier gate)
├── SKILL_CHANGELOG.md                # Full iteration history (R5-R10 experiments, NVMe Phase 1)
├── README.md / README_CN.md          # This file
├── references/                       # 90+ curated knowledge documents
│   ├── reference-index.md            # Task-to-reference mapping
│   ├── timing/                       # Timing semantics, contracts, naming, protocols
│   ├── architecture/                 # Hierarchy, system contracts, integration invariants
│   ├── axi-dma/                      # AXI full/Lite/Stream, DMA channel guidelines
│   ├── bus/                          # APB, AHB-Lite, NVMe protocol rules
│   ├── rtl/                          # Coding guidelines, FSM/FIFO/pipeline/handshake examples
│   ├── patterns/                     # Arbiter, credit-based, CRC, ECC, width converter, etc.
│   ├── synthesis/                    # CDC, constraints, synthesis guidance
│   ├── verification/                 # TB examples (skeleton+BFM), assertions, simulation loop, golden reference, **Icarus pitfalls**
│   ├── debug/                        # Bug pattern library (66+ patterns)
│   ├── design/                       # **7 design principles (P5a/P5b split)**, heuristics, PTA rules, intuition checklist
│   ├── project/                      # Brownfield, large module guidance
│   └── advanced/                     # Low-power, DFT, UVM, physical awareness
├── evals/
│   ├── evals.json                    # 63 evaluation prompts with 250+ assertions
│   ├── benchmark.json                # Benchmark metadata and dimension coverage
│   ├── task_benchmark.json           # 12 engineer-level A/B comparison tasks
│   ├── fixtures/                     # 4 bug fixtures for debug evaluation
│   └── trials/                       # 23 executable RTL + testbench trials
├── scripts/                          # 10 Python automation scripts
├── projects/                         # 16 validated RTL projects + A/B experiments
│   ├── test-workflow-round5/         # R5: AXI-S FIFO A/B experiment
│   ├── test-workflow-round6/         # R6: AXI-S 2x2 Switch A/B experiment
│   ├── test-workflow-round8/         # R8: UART TX + I2C A/B experiment
│   ├── test-workflow-round9/         # R9: Step 8d stress test (P2 FSM bug)
│   ├── test-workflow-round10/        # R10: Step 8d cross-principle test (P3 bug)
│   ├── test-e2e-validation/          # E2E: AXI-Stream→APB Bridge (36/36)
│   ├── pipeline-fork-join/           # Split-Merge Pipeline (5/5, 3 patterns)
│   ├── nvme-admin-engine/            # NVMe Phase 1: Admin Engine (2/2)
│   └── ...                           # (13 original validated projects)
```

## Key capabilities

### 7 Design Principles (with complexity-gated application)

The skill's 66+ bug patterns are organized under 7 core design principles. **P5 was split** (R5-R8 experiment data showed P5 never triggered on leaf modules — output discipline and physical implementation are orthogonal concerns). Each principle has **When-to-skip/lite** rules to avoid wasting time on inapplicable questions:

| # | Principle | Applies to | Key Question |
|---|-----------|:---:|-------------|
| P1 | Every Signal Has a Timing Contract | L1/L2 | Is every output's signal type (pulse/level/registered) documented? |
| P2 | Every FSM Must Find Its Way Home | L1/L2 (LITE for linear) | Can every state find a path back to IDLE? Abort paths? |
| P3 | Every Register Has a Known Value | **All levels** | What value does every register hold after reset? |
| P4 | Independent Things Stay Independent | L1/L2 (skip single-channel) | Are independent channels/paths/domains decoupled? |
| P5a | Every Output Respects the Next Engineer | L1/L2 | Are boundary outputs registered (not combinational from state_q)? |
| P5b | The Physical World Always Wins | L2/ASIC only | Power gating, DVFS, placement — skip for FPGA and L0/L1 |
| P6 | Boundaries Are Where Bugs Hide | All (LITE for single-module) | Does every module boundary have an explicit contract? |

See `references/design/design-principles.md` for full active-search questions, protocol-agnostic guidance, and skip/lite rules.

### Contract-first, always

The agent must write a timing contract before any RTL. This is not a suggestion — the skill's workflow makes it structurally impossible to skip. The contract includes clock domains, reset style, handshake semantics, latency, stall behavior, flush behavior, and boundary policy.

### Functional verification is mandatory (Golden Reference)

Step 8b requires running functional tests with known inputs and expected outputs. Six golden reference strategies cover every module type: known I/O pairs (CRC/ECC), software reference model (algorithms), write-readback scoreboard (register blocks), data integrity scoreboard (DMA/FIFO), invariant checking (arbiters), and latency verification (pipelines). All 6 strategies validated across 10 real projects.

### 66+ bug patterns with authoritative sources

The bug pattern library encodes known RTL failure modes discovered through 14 real projects and 4 A/B experiment rounds. All patterns trace to authoritative sources (IEEE 1364, ARM IHI specs, Cummings SNUG papers).

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
| Low-Power (LP1-LP7) | 7 | Isolation timing, retention handshake, PSM states, DVFS gate |
| Physical (PH1-PH4) | 4 | Registered I/O, fanout control, SRAM proximity, bus grouping |
| Verification (V1) | 1 | Structural PASS but functional FAIL |
| **Testbench Pitfalls (A1-E1)** | **16** | **Icarus-specific: return/break unsupported, delta-cycle race, #1 settling, address aliasing, while(busy_o) timing** |

### Simulation loop + principle-driven debug

Full closed-loop verification: read `icarus-common-pitfalls.md` (mandatory) → `iverilog` compile → `vvp` simulate → parse PASS/FAIL → Phase 4 principle-driven debug (re-read 2a/5a/8c review docs before fixing) → bug pattern matching → minimal fix → re-simulate. Maximum 3 fix-and-rerun iterations.

### Icarus testbench pitfalls (16 documented)

R5-R8 experiments uncovered 16 recurring Icarus-specific testbench bugs. Each pitfall is documented with broken/fix code, authoritative source citation, and empirical verification. Categories: language gaps (return/break/ref), delta-cycle timing, protocol compliance, structural issues, CDC. See `references/verification/icarus-common-pitfalls.md`.

### Standard testbench skeleton + BFM library

`references/verification/tb-examples.md` Section 0 provides a copy-paste skeleton with safe clock gen, error accumulation, output protocol markers. APB BFM (write/read/check/PSLVERR tasks, ARM IHI 0024C compliant) and AXI-Stream BFM (send/recv/packet tasks, ARM IHI 0051B compliant) included.

### Synthesis awareness (Yosys)

Post-simulation synthesis check: latch detection, combinational loop detection, critical path analysis (ltp), cell count verification. `yosys_extract.py` for automated report extraction.

### Multi-module integration + sub-agent delegation

Sub-agent delegation with interface contracts ensuring port width consistency. Step 12 prompt template with mandatory skill loading directive. L2 decomposition recommendation for modules >400 lines. Validated on UART (4 sub-agents), DMA subsystem (4 sub-agents), Low-Power SoC (5 sub-agents), and E2E validation.

### A/B experiment methodology (6 rounds validated)

R5-R10 experiments established the evidence base for workflow decisions. Distributed checkpoints reduce simulation iterations 3× for subsystems. Principle fatigue confirmed — 6-at-once review misses bugs. R9-R10 validated Step 8d principle-driven debug (P2 and P3 bug types). Complexity gate calibrated from data. See `SKILL_CHANGELOG.md` for full experiment reports.

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
| NVMe | NVM Express 2.3 + NVM Cmd Set 1.2 | nvme-guidelines (Admin + NVM I/O + PRP traversal) |

## Design pattern catalog (18)

Ready/valid register slice, skid buffer, FIFO, pipeline stage, FSM (two-process), arbiter (fixed/round-robin), credit-based flow control, retry buffer, width converter, CRC generator, SECDED ECC, multi-bank memory scheduler, counter/register slice, req/ack adapter, rate limiter, frame assembler, CAM, AXI DMA slice.

## Validated projects (14 + 4 A/B experiments)

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
| **Low-Power SoC** | **Subsystem** | **28/28** | **LP1-LP7 + PH1-PH4 validated** |
| **AXI-S→APB Bridge** | **Dual-protocol** | **36/36** | **E2E workflow validation, B6 pitfall discovered** |
| **Split-Merge Pipeline** | **Pipeline** | **5/5** | **3 patterns: data-loss under backpressure, alignment delay anti-pattern, signal type mismatch** |
| **NVMe Admin Engine** | **Storage** | **2/2** | **First domain extension, 5-module L2 subsystem, AXI adapter** |

### A/B Experiment Rounds

| Round | Project | Result | Core finding |
|:---:|------|------|------|
| R5 | AXI-S Packet FIFO | Both 12/12 | First distributed-checkpoint trial |
| **R6** | **AXI-S 2×2 Switch** | **New: 0 RTL bug, Old: 2 bugs** | **3× fewer iterations, bug at Step 5a** |
| R7 | Width Converter | Invalid (contract mismatch) | Experimental design lesson |
| R8 | UART TX + I2C | Both 6/6 (UART) | Leaf module ceiling confirmed |
| **R9** | **UART TX (P2 bug)** | **32K tokens, 44s** | **Step 8d Keeper Test passed** |
| **R10** | **UART TX (P3 bug)** | **30K tokens, 55s** | **Cross-principle validation: P2+P3 both verified** |

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
