# Low-Power SoC Subsystem — System Contract

## 1. Overview

A minimal but representative SoC subsystem with APB control plane, power management, DVFS, clock gating, and a physical-aware data path. Purpose: validate 10 new bug patterns (LP1-LP6, PH1-PH4) via real RTL + simulation.

## 2. Architecture

```
                    APB Bus (PADDR/PWDATA/PRDATA/PSEL/PENABLE/...)
                         |
                    +----+----+
                    | apb_regs|  (APB register file, decode to per-module CSR)
                    +----+----+
                         |
         +-------+-------+-------+-------+
         |       |       |       |       |
    +----+--+ +--+---+ +-+----+ +-+-----+
    |  psm  | |dvfs | |clk   | |phys   |
    |       | |ctrl | |gate  | |aware  |
    |       | |     | |ctrl  | |datapth|
    +-------+ +-----+ +------+ +-------+
         |       |       |       |
         +-------+-------+-------+
                         |
                    +----+----+
                    | soc_top |  (integration, power control signals)
                    +---------+
```

## 3. Module Decomposition

| Module | Function | Lines (est.) | Patterns Covered |
|--------|----------|-------------|------------------|
| `psm` | Power State Machine: controls isolation, retention, power switch | ~250 | LP1, LP2, LP3 |
| `dvfs_ctrl` | DVFS Controller: frequency switching + operand isolation | ~200 | LP5, LP6 |
| `clk_gate_ctrl` | Clock Gating Controller: domain clock gate + CDC sync | ~200 | LP4 |
| `phys_aware_datapath` | MAC Array: registered I/O, fanout control, bus grouping | ~300 | PH1, PH2, PH3, PH4 |
| `apb_regs` | APB Register Block: CSR decode, per-module control/status | ~200 | (regression) |
| `soc_top` | Top-level integration + power control coordination | ~100 | (integration) |

Total: ~1250 lines RTL

## 4. Clock and Reset

- Single clock domain: `clk_i` (simulated at 100MHz)
- Async reset: `rst_i` (active high)
- PSM/dvfs/clk_gate use APB control from apb_regs
- phys_aware_datapath processes data through MAC pipeline

## 5. APB Register Map

| Offset | Module | Register | Width | Access |
|--------|--------|----------|-------|--------|
| 0x00 | psm | CTRL (sleep_req, wake_req) | 2 | RW |
| 0x04 | psm | STATUS (power_state, busy) | 4 | RO |
| 0x08 | dvfs | CTRL (freq_idx, req) | 5 | RW |
| 0x0C | dvfs | STATUS (current_freq, busy) | 5 | RO |
| 0x10 | clk_gate | CTRL (gate_en, force_on) | 4 | RW |
| 0x14 | clk_gate | STATUS (gated, activity) | 2 | RO |
| 0x20 | datapath | SRC_A, SRC_B (operand inputs) | 32 | RW |
| 0x24 | datapath | CTRL (start, op_sel) | 2 | RW |
| 0x28 | datapath | RESULT_HI, RESULT_LO | 64 | RO |
| 0x2C | datapath | STATUS (done, busy) | 2 | RO |

## 6. Integration Invariants

1. **PSM outputs** (isolation_en, power_switch, retain_save/restore) connect to all switchable-domain modules
2. **DVFS busy** gates psm sleep requests — no power-down during frequency switch (LP5)
3. **Clock gate enable** from clk_gate_ctrl feeds clock-enable pins of datapath registers
4. **Pulse synchronizer** (LP4) used for any signal crossing from gated to ungated domain
5. **All module I/O registered** at top-level boundaries (PH1)
6. **Fanout >50** signals use `(* max_fanout = 50 *)` attribute (PH2)
7. **MAC array SRAM** placed in same hierarchy as MAC datapath (PH3)
8. **Bus signals grouped** by channel in port declarations (PH4)

## 7. Verification Strategy

| Test Group | What | Patterns |
|------------|------|----------|
| psm_tests | Power-up/down sequence, isolation timing, retention save/restore | LP1, LP2, LP3 |
| dvfs_tests | Frequency switch idle/busy, operand isolation | LP5, LP6 |
| clk_gate_tests | Gate enable/disable, CDC pulse sync | LP4 |
| datapath_tests | Registered I/O, fanout, bus grouping (Yosys check) | PH1-PH4 |
| integration_tests | PSM→DVFS gating, full power cycle + MAC compute | Integration |

## 8. Implementation Sequence

1. Write interface contracts for all 5 submodules
2. Spawn sub-agents for parallel RTL generation (psm, dvfs_ctrl, clk_gate_ctrl, phys_aware_datapath, apb_regs)
3. Write soc_top integration
4. Generate testbench
5. Compile + simulate with iverilog
6. Yosys synthesis check (latch, loop, critical path)
7. Review results and identify skill gaps
