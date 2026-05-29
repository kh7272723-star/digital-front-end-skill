# Low-Power Design Guidelines

## Purpose

This file covers low-power digital design techniques for RTL engineers. Use when the task involves power optimization, clock gating, power domains, or power-aware verification.

Sources: ARM Low Power Methodology Manual (LPMM), IEEE 1801-2015 (UPF), OpenTitan power management, PULP power management, Cummings SNUG papers on clock gating (SNUG 2002), Wakerly "Digital Design" §10.4.

## Power reduction hierarchy

1. **Clock gating** — disable clocks to idle logic (highest ROI, lowest risk)
2. **Operand isolation** — disable inputs to combinational blocks when output is unused
3. **Power gating** — cut power to entire blocks (requires retention/isolation cells)
4. **Dynamic voltage/frequency scaling** — adjust V/F at runtime (system-level)

---

## 1. Clock gating

### When to gate

- Register banks with stable inputs for multiple cycles
- FSM idle states with no pending work
- FIFO empty with no write expected
- Pipeline stages with no valid data

### RTL pattern

```verilog
// Preferred: clock-enable style (synthesis tool infers ICG cell)
always @(posedge clk_i) begin
    if (rst_i)
        data_q <= {WIDTH{1'b0}};
    else if (ce_i)       // clock enable, not gated clock
        data_q <= data_d;
end

// If explicit ICG needed (e.g., for power analysis):
reg clk_en_latch;
always @(*) begin
    if (!clk_i)
        clk_en_latch = clk_en_i;
end
wire gated_clk = clk_i & clk_en_latch;
```

### Rules

- Gate at the source, not downstream (reduces switching on the clock tree)
- Never gate clocks used for CDC synchronizers
- Never gate reset clocks
- Use enable signals, not gated clocks, in RTL (synthesis tool inserts ICG)
- Verify gated domain does not lose state on re-entry
- See `power-timing-area.md` P1 for clock-enable vs gating tradeoff

---

## 2. Operand isolation

```verilog
// Isolate multiplier inputs when result is unused
wire [31:0] a_isolated = result_needed ? a_i : 32'b0;
wire [31:0] b_isolated = result_needed ? b_i : 32'b0;
wire [31:0] product = a_isolated * b_isolated;

// Better: isolate at register boundary (avoids glitch power on operands)
always @(posedge clk_i) begin
    if (result_needed) begin
        a_reg <= a_i;
        b_reg <= b_i;
    end
end
wire [31:0] product = a_reg * b_reg;
```

### When to apply

- Wide combinational logic (>32-bit multiplier, barrel shifter, priority encoder)
- Logic with high switching activity but infrequent use
- See `power-timing-area.md` P3 for operand isolation rules

---

## 3. Power domains

### Concepts

- **Always-on domain**: power management controller, wake-up logic, isolation cells
- **Switchable domain**: functional logic that can be powered off
- **Retention domain**: flip-flops that retain state during power-off (balloon flops)

### RTL implications

- Insert isolation cells at domain boundaries (clamp to 0 or hold)
- Use retention flops for state that must survive power-off
- Model power states in testbench (do not assume always-on)

---

## 4. Power State Machine (PSM)

The PSM controls power domain transitions. It lives in the always-on domain and communicates with the PMU (Power Management Unit).

### Design pattern

```verilog
module power_state_machine (
    input  clk_i,
    input  rst_i,
    // PMU interface
    input  pmu_sleep_req_i,
    output pmu_sleep_ack_o,
    input  pmu_wake_req_i,
    output pmu_wake_ack_o,
    // Domain control
    output reg isolation_en_o,    // assert BEFORE power off
    output reg power_switch_o,    // 1 = on, 0 = off
    output reg retain_save_o,     // pulse to save retention state
    output reg retain_restore_o,  // pulse to restore retention state
    output reg domain_clk_en_o,   // gate clock during sleep
    // Status
    output [2:0] power_state_o
);
    localparam S_ON           = 3'b001;
    localparam S_ISOLATING    = 3'b001;
    localparam S_SAVE_RETAIN  = 3'b010;
    localparam S_POWER_OFF    = 3'b011;
    localparam S_SLEEP        = 3'b100;
    localparam S_WAKING       = 3'b101;
    localparam S_RESTORE      = 3'b110;
    localparam S_DEISOLATING  = 3'b111;

    reg [2:0] state_q, state_d;
    reg [3:0] wait_cnt_q;  // timing guard counter

    assign power_state_o = state_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q      <= S_ON;
            wait_cnt_q   <= 4'd0;
        end else begin
            state_q <= state_d;
            if (state_q != state_d)
                wait_cnt_q <= 4'd0;
            else
                wait_cnt_q <= wait_cnt_q + 1'b1;
        end
    end

    always @(*) begin
        // Safe defaults — never leave signals undriven
        isolation_en_o    = 1'b0;
        power_switch_o    = 1'b1;
        retain_save_o     = 1'b0;
        retain_restore_o  = 1'b0;
        domain_clk_en_o   = 1'b1;
        pmu_sleep_ack_o   = 1'b0;
        pmu_wake_ack_o    = 1'b0;
        state_d           = S_ON;

        case (state_q)
            S_ON: begin
                if (pmu_sleep_req_i)
                    state_d = S_ISOLATING;
            end
            S_ISOLATING: begin
                isolation_en_o = 1'b1;  // MUST assert before power off
                if (wait_cnt_q == 4'd2)  // wait for isolation to settle
                    state_d = S_SAVE_RETAIN;
                else
                    state_d = S_ISOLATING;
            end
            S_SAVE_RETAIN: begin
                isolation_en_o  = 1'b1;
                retain_save_o   = 1'b1;  // save retention state
                if (wait_cnt_q == 4'd1)
                    state_d = S_POWER_OFF;
                else
                    state_d = S_SAVE_RETAIN;
            end
            S_POWER_OFF: begin
                isolation_en_o = 1'b1;
                power_switch_o = 1'b0;  // cut power
                domain_clk_en_o = 1'b0;
                pmu_sleep_ack_o = 1'b1;
                state_d = S_SLEEP;
            end
            S_SLEEP: begin
                isolation_en_o  = 1'b1;
                power_switch_o  = 1'b0;
                domain_clk_en_o = 1'b0;
                if (pmu_wake_req_i)
                    state_d = S_WAKING;
                else
                    state_d = S_SLEEP;
            end
            S_WAKING: begin
                isolation_en_o = 1'b1;   // keep isolated during power-on
                power_switch_o = 1'b1;   // restore power
                if (wait_cnt_q == 4'd4)  // wait for power stable
                    state_d = S_RESTORE;
                else
                    state_d = S_WAKING;
            end
            S_RESTORE: begin
                isolation_en_o   = 1'b1;  // still isolated
                retain_restore_o = 1'b1;  // restore retention state
                if (wait_cnt_q == 4'd1)
                    state_d = S_DEISOLATING;
                else
                    state_d = S_RESTORE;
            end
            S_DEISOLATING: begin
                pmu_wake_ack_o = 1'b1;
                state_d = S_ON;
            end
            default: state_d = S_ON;
        endcase
    end
endmodule
```

### Key properties

- Two-process FSM (mandatory for multi-stage control)
- All outputs have safe defaults (no latches)
- Isolation enable asserts BEFORE power switch off (LP1)
- Retention save completes BEFORE power off, restore AFTER power on (LP2)
- Timing guard counter prevents premature transitions
- `power_switch_o` is a register (no glitches)

---

## 5. Isolation cells

### Clamp-to-0 pattern

```verilog
// Isolation: clamp output to 0 when domain is off
assign data_out = isolation_en_i ? {WIDTH{1'b0}} : data_in;

// Synthesis attribute: tell tool this is an isolation cell
// (tool replaces mux with dedicated isolation cell)
```

### Clamp-to-hold pattern

```verilog
// Isolation: hold last value when domain is off
reg [WIDTH-1:0] hold_reg;
always @(posedge clk_i) begin
    if (!isolation_en_i)
        hold_reg <= data_in;
end
assign data_out = isolation_en_i ? hold_reg : data_in;
```

### Isolation timing rules

- Isolation enable MUST assert before power-off (settling time)
- Isolation enable MUST deassert after power-on (stability time)
- Never use isolation on clock or reset signals
- Isolation cells belong to the always-on domain

---

## 6. Retention flops

### Balloon flop pattern

```verilog
// Retention flip-flop: saves state to shadow register on retain_save
module retention_flop (
    input  clk_i,
    input  rst_i,
    input  d_i,
    input  retain_save_i,    // pulse: save to shadow
    input  retain_restore_i, // pulse: restore from shadow
    output reg q_o
);
    reg shadow_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            q_o     <= 1'b0;
            shadow_q <= 1'b0;
        end else if (retain_save_i) begin
            shadow_q <= q_o;           // save current state
        end else if (retain_restore_i) begin
            q_o <= shadow_q;           // restore saved state
        end else begin
            q_o <= d_i;                // normal operation
        end
    end
endmodule
```

### Retention handshake rules

- Save must complete before power-off (LP2)
- Restore must happen after power-on and before de-isolation
- Shadow register is in the always-on domain (retains during power-off)
- For wide buses, use array of retention flops (not a single wide register)

---

## 7. Level shifter awareness

### When to insert

- Signal crosses from low-voltage domain to high-voltage domain (or vice versa)
- Always required at voltage domain boundaries
- Synthesis tool inserts based on UPF; RTL does not instantiate level shifters

### RTL implications

- Treat voltage domain crossings like clock domain crossings (register at boundary)
- Document voltage domains in the design spec
- Level shifter adds 1-2 gate delays to the path (account in timing budget)

---

## 8. Power-aware CDC

### Problem

Gated clock domains can cross with ungated domains. The gated clock may stop, causing the synchronizer to lose state.

### Solution: clock-enable synchronizer

```verilog
// Synchronize a signal from gated domain to ungated domain
// Use a pulse synchronizer (not level) to handle gated clock stopping
reg signal_gated_d;
always @(posedge gated_clk_i) begin
    signal_gated_d <= signal_gated_i;
end
wire pulse_gated = signal_gated_i & ~signal_gated_d;

// Pulse synchronizer (double-flop in ungated domain)
reg [2:0] sync_q;
always @(posedge ungated_clk_i) begin
    if (rst_i)
        sync_q <= 3'b000;
    else
        sync_q <= {sync_q[1:0], pulse_gated};
end
wire pulse_ungated = sync_q[1] & ~sync_q[2];
```

### Rules

- Never gate clocks used for CDC synchronizers
- Use pulse synchronizers when source clock may stop
- Use level synchronizers only when source clock is guaranteed running

---

## 9. DVFS controller

### Design pattern

```verilog
module dvfs_controller (
    input  clk_i,
    input  rst_i,
    // Software request
    input        sw_req_valid_i,
    input  [3:0] sw_freq_idx_i,   // frequency table index
    output reg   sw_req_ready_o,
    // PMU interface
    output reg       pmu_valid_o,
    output reg [3:0] pmu_freq_o,
    input            pmu_done_i,
    // Status
    output [3:0] current_freq_o,
    output       busy_o
);
    localparam S_IDLE     = 2'b01;
    localparam S_REQUEST  = 2'b10;
    localparam S_WAIT     = 2'b11;

    reg [1:0] state_q, state_d;
    reg [3:0] current_freq_q, target_freq_q;

    assign current_freq_o = current_freq_q;
    assign busy_o = (state_q != S_IDLE);

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q        <= S_IDLE;
            current_freq_q <= 4'd0;
            target_freq_q  <= 4'd0;
        end else begin
            state_q <= state_d;
            if (state_q == S_IDLE && sw_req_valid_i)
                target_freq_q <= sw_freq_idx_i;
            if (state_q == S_WAIT && pmu_done_i)
                current_freq_q <= target_freq_q;
        end
    end

    always @(*) begin
        sw_req_ready_o = 1'b0;
        pmu_valid_o    = 1'b0;
        pmu_freq_o     = 4'd0;
        state_d        = S_IDLE;

        case (state_q)
            S_IDLE: begin
                sw_req_ready_o = 1'b1;
                if (sw_req_valid_i)
                    state_d = S_REQUEST;
            end
            S_REQUEST: begin
                pmu_valid_o = 1'b1;
                pmu_freq_o  = target_freq_q;
                state_d     = S_WAIT;
            end
            S_WAIT: begin
                if (pmu_done_i)
                    state_d = S_IDLE;
                else
                    state_d = S_WAIT;
            end
            default: state_d = S_IDLE;
        endcase
    end
endmodule
```

### Key properties

- Frequency change is atomic (request → wait → done handshake)
- No frequency change during active transfer (LP5)
- Current frequency always readable (no glitch on read)
- Two-process FSM with safe defaults

---

## 10. Low-power memory design

### Clock-gated RAM

```verilog
// RAM with clock-enable for power reduction
reg [WIDTH-1:0] mem [0:DEPTH-1];
always @(posedge clk_i) begin
    if (wr_en_i)           // only clock memory on write
        mem[addr_i] <= wdata_i;
end
// Read is combinational (no clock needed for read port)
assign rdata_o = mem[addr_i];
```

### Sleep-aware register file

```verilog
// Register file with sleep mode: retain values but stop switching
always @(posedge clk_i) begin
    if (rst_i)
        regfile <= {DEPTH*WIDTH{1'b0}};
    else if (!sleep_i && wr_en_i)  // block writes during sleep
        regfile[wr_addr_i] <= wr_data_i;
end
```

---

## Verification checklist

- [ ] Clock gating does not affect CDC synchronizers
- [ ] Gated domains retain or correctly re-initialize state
- [ ] Isolation cells clamp outputs when domain is off
- [ ] Wake-up latency meets system requirements
- [ ] Power transitions do not create glitches on active-domain signals
- [ ] Retention save completes before power-off (LP2)
- [ ] Isolation enable asserts before power-off (LP1)
- [ ] Power state machine has no illegal transitions (LP3)
- [ ] DVFS frequency change does not occur during active transfer (LP5)
- [ ] Operand isolation applied to wide combinational logic (LP6)

## Common mistakes

1. Gating a clock used by a synchronizer (breaks CDC)
2. Not verifying re-initialization after power-on (stale state)
3. Forgetting isolation at domain boundaries (contention)
4. Assuming combinational paths through powered-off domains are safe
5. Isolation enable timing: asserting AFTER power-off (too late, causes contention)
6. Retention save overlapping with power-off (data loss)
7. DVFS frequency change during active bus transfer (protocol violation)
