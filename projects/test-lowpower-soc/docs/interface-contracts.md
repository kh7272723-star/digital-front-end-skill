# Interface Contracts for Low-Power SoC Subsystem

## Common Conventions
- All ports: `*_i` (input), `*_o` (output)
- Registered state: `*_q` (reg), `*_d` (wire)
- Active-high reset: `rst_i`
- Single clock domain: `clk_i` (all modules)
- FSM: two-process style, single-bit control outputs

---

## Module 1: psm (Power State Machine)

### Purpose
Controls power domain state transitions: ON → ISOLATING → SAVE → OFF → SLEEP → WAKE → RESTORE → ON. Validates LP1 (isolation before power-off), LP2 (retention save/restore handshake), LP3 (no illegal state transitions).

### Ports

```verilog
module psm (
    input  clk_i,
    input  rst_i,
    // APB CSR interface (from apb_regs)
    input        sleep_req_i,       // PMU sleep request
    input        wake_req_i,        // PMU wake request
    // DVFS gating
    input        dvfs_busy_i,       // block sleep during DVFS (LP5)
    // Domain control outputs
    output       isolation_en_o,    // assert BEFORE power off (LP1)
    output       power_switch_o,    // 1=on, 0=off
    output       retain_save_o,     // pulse: save retention state (LP2)
    output       retain_restore_o,  // pulse: restore retention state (LP2)
    output       domain_clk_en_o,   // clock enable for switchable domain
    // Status
    output [2:0] power_state_o,     // current PSM state (RO)
    output       sleep_ack_o,       // acknowledged sleep entry
    output       wake_ack_o         // acknowledged wake completion
);
```

### FSM States (7 states, 3-bit encoding)
1. S_ON (3'b001) — normal operation
2. S_ISOLATING (3'b010) — assert isolation, wait settling (LP1)
3. S_SAVE_RETAIN (3'b011) — pulse retain_save, wait (LP2)
4. S_POWER_OFF (3'b100) — cut power_switch, gate clock
5. S_SLEEP (3'b101) — waiting for wake_req
6. S_WAKING (3'b110) — restore power, wait stability
7. S_RESTORE (3'b111) — pulse retain_restore, de-isolate (LP2)

### Critical Timing Requirements
- **LP1**: isolation_en_o MUST assert (S_ISOLATING) BEFORE power_switch_o deasserts (S_POWER_OFF)
- **LP2**: retain_save_o MUST pulse (S_SAVE_RETAIN) BEFORE power_switch_o deasserts; retain_restore_o MUST pulse (S_RESTORE) AFTER power_switch_o reasserts
- **LP3**: FSM MUST NOT skip states; any jump (e.g., S_ON→S_SLEEP) is illegal
- **LP5 check**: sleep_req_i ignored when dvfs_busy_i=1 (prevent power-down during DVFS)
- Wait counters: use `wait_cnt_q` with configurable thresholds per state

### Interface Connection
- `sleep_req_i`, `wake_req_i` ← apb_regs CSR decode
- `dvfs_busy_i` ← dvfs_ctrl busy_o
- `isolation_en_o`, `power_switch_o`, `domain_clk_en_o` → all switchable modules
- `retain_save_o`, `retain_restore_o` → retention flops in datapath
- `power_state_o`, `sleep_ack_o`, `wake_ack_o` → apb_regs status readback

---

## Module 2: dvfs_ctrl (DVFS Controller)

### Purpose
Controls dynamic frequency switching. Validates LP5 (no frequency switch during active transfer) and LP6 (operand isolation for wide combinational logic >32-bit).

### Ports

```verilog
module dvfs_ctrl (
    input  clk_i,
    input  rst_i,
    // APB CSR interface
    input        freq_req_i,        // frequency switch request
    input  [3:0] freq_idx_i,        // target frequency table index
    input        bus_idle_i,        // from clk_gate_ctrl: bus is idle
    // Operand isolation control (LP6)
    output       isolate_en_o,      // isolate >32b combinational inputs
    // PMU handshake
    output       pmu_valid_o,       // frequency change command valid
    output [3:0] pmu_freq_o,        // target frequency
    input        pmu_done_i,        // PMU acknowledges frequency change
    // Status
    output [3:0] current_freq_o,    // current operating frequency index
    output       busy_o             // DVFS in progress (gates PSM sleep)
);
```

### FSM States (4 states)
1. S_IDLE — ready for requests
2. S_CHECK_IDLE — verify bus_idle_i before proceeding (LP5)
3. S_REQUEST — assert pmu_valid_o with target frequency
4. S_WAIT — wait for pmu_done_i

### Critical Timing Requirements
- **LP5**: MUST check `bus_idle_i==1` before entering S_REQUEST. If bus is active, stay in S_CHECK_IDLE or return to S_IDLE with error
- **LP6**: `isolate_en_o` asserted during DVFS transition to gate wide combinational logic inputs (>32-bit multiply/accumulate in datapath)
- `busy_o` high from freq_req_i acceptance to pmu_done_i — blocks psm sleep
- Atomic: request→check→commit→wait→done

### Interface Connection
- `freq_req_i`, `freq_idx_i` ← apb_regs CSR decode
- `bus_idle_i` ← clk_gate_ctrl (activity monitoring)
- `isolate_en_o` → phys_aware_datapath (operand isolation)
- `busy_o` → psm dvfs_busy_i
- `current_freq_o` → apb_regs status readback

---

## Module 3: clk_gate_ctrl (Clock Gating Controller)

### Purpose
Controls clock gating for switchable domains. Validates LP4 (gated clock domain CDC — pulse synchronizer for crossing from gated to ungated domain).

### Ports

```verilog
module clk_gate_ctrl (
    input  clk_i,
    input  rst_i,
    // APB CSR interface
    input  [3:0] gate_en_i,         // per-domain gate enable (bit[0]=datapath)
    input  [3:0] force_on_i,        // per-domain force clock on (override)
    // Domain clock enables (to switchable modules)
    output [3:0] domain_clk_en_o,   // per-domain clock enable
    // Activity monitoring (from datapath)
    input        datapath_active_i, // datapath has pending work
    // CDC: signal FROM gated domain TO ungated (PWR_MGMT) domain
    input        gated_event_i,     // event from gated domain (on gated clock)
    output       ungated_event_o,   // same event, synchronized to ungated clk
    // Status
    output       bus_idle_o,        // all gated domains are idle
    output [3:0] activity_o         // per-domain activity status
);
```

### Clock Gating Logic
- `domain_clk_en_o[d] = !gate_en_i[d] | force_on_i[d] | activity_detected[d]`
- Auto-gate when no activity for IDLE_THRESHOLD cycles
- Auto-ungate when activity detected or force_on asserted

### CDC Pulse Synchronizer (LP4)
- Signal from gated domain (`gated_event_i`) crosses to ungated (always-on) domain
- Use pulse synchronizer: edge detect in gated domain → 2FF sync in ungated → edge detect
- Rationale: gated clock may stop, level synchronizer would lose the event
- MUST use `(* ASYNC_REG = "TRUE" *)` on synchronizer flops

### Critical Rules
- **LP4**: ANY signal crossing FROM gated clock domain TO ungated domain MUST use pulse synchronizer
- Never gate the clock used by the CDC synchronizer itself
- `bus_idle_o` = AND of all `!activity_o[d]` for gated domains

### Interface Connection
- `gate_en_i`, `force_on_i` ← apb_regs CSR decode
- `domain_clk_en_o` → phys_aware_datapath clock enables
- `datapath_active_i` ← phys_aware_datapath busy_o
- `bus_idle_o` → dvfs_ctrl bus_idle_i
- `ungated_event_o` → apb_regs (interrupt/wakeup)

---

## Module 4: phys_aware_datapath (Physical-Aware MAC Array)

### Purpose
Multiply-Accumulate (MAC) array with physical-awareness features. Validates PH1 (registered I/O at hierarchy boundaries), PH2 (max_fanout attribute on high-fanout signals), PH3 (SRAM macro in same hierarchy as consumer), PH4 (bus signals grouped by channel in port declarations).

### Ports

```verilog
module phys_aware_datapath (
    input  clk_i,
    input  rst_i,
    // Clock enable (from clk_gate_ctrl)
    input        clk_en_i,          // domain clock enable
    // Operand isolation (from dvfs_ctrl, LP6)
    input        isolate_en_i,      // isolate wide combinational inputs
    // APB CSR interface (from apb_regs)
    input  [31:0] src_a_i,          // operand A
    input  [31:0] src_b_i,          // operand B
    input         start_i,           // start MAC computation
    input  [1:0]  op_sel_i,         // 00=MAC, 01=MUL, 10=ADD, 11=ACC
    // Results
    output [31:0] result_lo_o,      // low 32 bits
    output [31:0] result_hi_o,      // high 32 bits (for MAC/MUL)
    // Status
    output        done_o,            // computation complete (pulse)
    output        busy_o,            // computation in progress
    // Retention (from psm, LP2)
    input         retain_save_i,     // save state to shadow
    input         retain_restore_i,  // restore state from shadow
    // Activity monitor (to clk_gate_ctrl)
    output        active_o           // MAC has pending/in-progress work
);
```

### MAC Pipeline Stages
1. **Input Register** (PH1: registered I/O boundary)
   - Register src_a_i, src_b_i, op_sel_i on start_i
   - Apply operand isolation: isolate_en_i → zero the registered operands (LP6)
2. **SRAM Buffer** (PH3: SRAM near consumer)
   - 256x32 SRAM for accumulation buffer
   - Wrapped in same module as MAC (not separate hierarchy)
3. **MAC Compute**
   - 32x32 multiplier → 64-bit product
   - 64-bit accumulator (result_hi_o, result_lo_o)
4. **Output Register** (PH1: registered I/O boundary)
   - result_lo_o, result_hi_o, done_o driven from registers

### Physical Awareness Requirements
- **PH1**: ALL module ports driven from registers (no combinational output paths)
- **PH2**: `(* max_fanout = 50 *)` on clk_en_i and other high-fanout control signals
- **PH3**: SRAM instance inside phys_aware_datapath (not external)
- **PH4**: Port declarations grouped: first clock/reset, then control bus, then data bus, then status
- **Retention**: accumulate_q and SRAM shadow for power-down state preservation

### Interface Connection
- `clk_en_i` ← clk_gate_ctrl domain_clk_en_o[0]
- `isolate_en_i` ← dvfs_ctrl isolate_en_o
- `src_a_i`, `src_b_i`, `start_i`, `op_sel_i` ← apb_regs CSR decode
- `result_lo_o`, `result_hi_o`, `done_o`, `busy_o` → apb_regs status readback
- `retain_save_i`, `retain_restore_i` ← psm
- `active_o` → clk_gate_ctrl datapath_active_i

---

## Module 5: apb_regs (APB Register Block)

### Purpose
Standard APB slave providing CSR access to all submodules. Regression test for existing APB pattern.

### Ports

```verilog
module apb_regs (
    input  clk_i,
    input  rst_i,
    // APB slave interface
    input  [11:0] paddr_i,
    input         psel_i,
    input         penable_i,
    input         pwrite_i,
    input  [31:0] pwdata_i,
    output [31:0] prdata_o,
    output        pready_o,
    output        pslverr_o,
    // Control outputs (to submodules)
    // PSM
    output        psm_sleep_req_o,
    output        psm_wake_req_o,
    input  [2:0]  psm_power_state_i,
    input         psm_sleep_ack_i,
    input         psm_wake_ack_i,
    // DVFS
    output        dvfs_freq_req_o,
    output [3:0]  dvfs_freq_idx_o,
    input  [3:0]  dvfs_current_freq_i,
    input         dvfs_busy_i,
    // Clock Gate
    output [3:0]  cg_gate_en_o,
    output [3:0]  cg_force_on_o,
    input  [3:0]  cg_activity_i,
    // Datapath
    output [31:0] dp_src_a_o,
    output [31:0] dp_src_b_o,
    output        dp_start_o,
    output [1:0]  dp_op_sel_o,
    input  [31:0] dp_result_lo_i,
    input  [31:0] dp_result_hi_i,
    input         dp_done_i,
    input         dp_busy_i
);
```

### APB Rules (from `references/bus/apb-guidelines.md`)
- PSEL asserted in SETUP, PENABLE in ACCESS
- PREADY asserted in ACCESS phase (can add wait states)
- PSLVERR on invalid address (both read AND write)
- Registered PRDATA (sample on PREADY handshake)

### Interface Connection
- APB pins ← external APB master (testbench)
- All `*_o` control outputs → respective submodule inputs
- All `*_i` status inputs ← respective submodule outputs

---

## Module 6: soc_top (Top-Level Integration)

### Purpose
Instantiate all 5 submodules, connect interfaces per contracts, add power control coordination.

### Ports

```verilog
module soc_top (
    input  clk_i,
    input  rst_i,
    // APB external
    input  [11:0] paddr_i,
    input         psel_i,
    input         penable_i,
    input         pwrite_i,
    input  [31:0] pwdata_i,
    output [31:0] prdata_o,
    output        pready_o,
    output        pslverr_o,
    // External status (for testbench observation)
    output [2:0]  psm_state_o,
    output [3:0]  dvfs_freq_o,
    output [3:0]  cg_activity_o,
    output [31:0] mac_result_o,
    output        mac_done_o
);
```

### Integration Checklist
- [ ] All submodule ports connected per interface contract
- [ ] No width mismatches between producer/consumer
- [ ] psm dvfs_busy_i ← dvfs_ctrl busy_o
- [ ] dvfs_ctrl bus_idle_i ← clk_gate_ctrl bus_idle_o
- [ ] clk_gate_ctrl datapath_active_i ← phys_aware_datapath active_o
- [ ] phys_aware_datapath clk_en_i ← clk_gate_ctrl domain_clk_en_o[0]
- [ ] phys_aware_datapath isolate_en_i ← dvfs_ctrl isolate_en_o
- [ ] phys_aware_datapath retain_*_i ← psm retain_*_o
