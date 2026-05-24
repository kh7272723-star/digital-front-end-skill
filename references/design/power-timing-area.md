# Power, Timing, and Area Design Rules

## Purpose

Rules for writing RTL that is low-power, timing-closure friendly, and area efficient. These are synthesizable Verilog-2001 techniques — no UPF/CPF power intent files required.

## Sources

| ID | Document | Publisher |
|----|----------|-----------|
| LPMM | Low Power Methodology Manual (Keating, Flynn, Aitken) | Synopsys/ARM, Springer |
| UG901 | Vivado Synthesis User Guide | AMD/Xilinx |
| UG949 | UltraFast Design Methodology Guide | AMD/Xilinx |
| UG952 | Power Design User Guide | AMD/Xilinx |
| XAPP796 | Low Power Design Techniques for 7 Series | AMD/Xilinx |
| AN573 | Low Power Techniques for FPGAs | Intel/Altera |
| UG20136 | Recommended HDL Coding Styles | Intel |
| SNUG | Cummings SNUG papers (CDC, async FIFO) | Sunburst Design |
| DC | Design Compiler User Guide (HDL coding styles) | Synopsys |
| OpenTitan | `prim_clock_gating.sv` | lowRISC |
| PULP | `common_cells/cluster_clock_gate.sv` | ETH Zurich |

---

## 1. Low Power

### P1. Clock enable over clock gating (LPMM Ch.5, UG901)

Write registers with clock enables; let synthesis infer ICG cells. Never manually AND-gate clocks in RTL — it causes glitches and creates new clock domains that complicate STA.

```verilog
// CORRECT: synthesis infers ICG cell
always @(posedge clk_i) begin
    if (en_i) q <= d;
end

// WRONG: glitch-prone manual gating — do NOT do this
assign gclk = clk_i & en_i;
always @(posedge gclk) q <= d;
```

Impact: up to 70% dynamic power savings on gated registers.

### P2. Gate at lowest hierarchy level (LPMM, XAPP796)

Place clock enables close to the consuming register, not at the module boundary. Finer-grained gating = less wasted switching.

### P3. Operand isolation (Synopsys Power Compiler, Intel AN573)

Gate inputs to large combinational blocks (multipliers, adders) when their output is unused. Prevents unnecessary switching in deep combinational cones.

```verilog
wire [31:0] a_gated = en ? a : 32'b0;
wire [31:0] b_gated = en ? b : 32'b0;
assign product = a_gated * b_gated;
```

### P4. Gray FSM encoding for sequential transitions (UG901, LPMM)

For FSMs where transitions are predominantly sequential (one direction), Gray encoding toggles exactly 1 bit per transition, minimizing switching activity.

```verilog
(* fsm_encoding = "gray" *)
reg [3:0] state_q;
```

Tradeoff: slightly more next-state decode logic. For highly branching FSMs, binary or one-hot is fine.

### P5. Memory access qualification (UG901, Intel Power Optimization)

Always use read/write enables on RAMs. Unqualified memory accesses waste power on every clock edge.

```verilog
always @(posedge clk_i) begin
    if (wr_en) mem[addr] <= wdata;  // write only when needed
    if (rd_en) rdata <= mem[addr];  // read only when needed
end
```

### P6. Shift register inference (UG901 SHREG_EXTRACT)

Long shift register chains should infer into SRL primitives (fewer resources, fewer switching nodes).

```verilog
(* shreg_extract = "yes" *)
reg [63:0] shift_chain;
always @(posedge clk_i)
    if (en) shift_chain <= {shift_chain[62:0], din};
```

---

## 2. Timing Closure

### T1. Synchronous reset preferred (UG949)

Asynchronous resets create timing races on reset release (recovery/removal violations). Use synchronous resets for all non-POR logic. Reserve async resets for true power-on-reset only.

This skill already mandates synchronous active-high reset. This rule reinforces that choice.

### T2. Clock enable over clock gating (UG949)

Same as P1, but from the timing perspective: gated clocks create new clock domains that require separate STA constraints. Clock-enable preserves a single clock domain.

### T3. Pipeline at boundaries (UG901, UG949)

Insert register stages at:
- Module I/O ports (breaks long inter-module paths)
- SLR crossings (FPGA multi-die)
- High-fanout nets (use `MAX_FANOUT` attribute)

```verilog
(* max_fanout = 50 *)
reg [ADDR_WIDTH-1:0] addr_q;
```

### T4. False path discipline (UG949)

- `set_false_path`: only for truly unrelated clocks (e.g., crystal oscillator vs. unrelated test clock)
- CDC synchronizers: prefer `set_max_delay -datapath_only` — the tool still optimizes the path, but the constraint acknowledges it crosses domains
- Never use `set_multicycle_path` on async CDC (it doesn't solve metastability, just delays the check)

### T5. Multicycle path guard (UG949 "Common Mistakes")

When using `set_multicycle_path -setup N`, always add the matching `-hold N-1`:
```tcl
set_multicycle_path -setup 3 -from [get_pins src/C] -to [get_pins dst/D]
set_multicycle_path -hold  2 -from [get_pins src/C] -to [get_pins dst/D]
```

### T6. Control set minimization (UG949)

Use the same reset polarity and enable structure across a module. Mixing sync/async resets or having many unique control sets prevents register packing into the same slice/CLB.

### T7. Register retiming attributes (UG901)

For modules where combinational depth is the bottleneck, let the tool move registers:

```verilog
(* retiming_forward = "yes" *)
module my_pipeline (...);
```

### T8. Flatten vs. hierarchy (UG901)

Use `(* keep_hierarchy = "yes" *)` only where needed for timing budgets or verification boundaries. Letting the tool flatten enables cross-module logic optimization.

---

## 3. Area Efficiency

### A1. Balanced operator trees (Synopsys DC)

Parenthesized balanced trees reduce combinational depth from O(N) to O(log N):

```verilog
// BAD: linear chain — O(N) depth
assign sum = a + b + c + d;

// GOOD: balanced tree — O(log N) depth
wire [N-1:0] sum_ab = a + b;
wire [N-1:0] sum_cd = c + d;
assign sum = sum_ab + sum_cd;
```

### A2. Don't-care for case defaults (UG901)

Assign `default: out = 1'bx` in case statements where the default is unreachable. Synthesis treats X as "choose simplest logic," reducing gate count.

```verilog
always @(*) begin
    case (sel)
        2'b00: out = a;
        2'b01: out = b;
        2'b10: out = c;
        default: out = 1'bx;  // don't-care optimization
    endcase
end
```

Warning: simulation and synthesis diverge on X. Use this only for truly unreachable defaults.

### A3. Bit-width discipline (Synopsys DC)

Minimize register and wire widths to the minimum needed. Use `$clog2` for address/counter widths. A 32-bit counter used for 1000 counts wastes routing and area.

### A4. DSP inference patterns (UG901)

Write `a * b + c` as a single expression to infer multiply-accumulate in DSP48:

```verilog
// GOOD: infers DSP48
always @(posedge clk_i)
    acc <= a * b + acc;

// BAD: split — may not infer DSP
always @(posedge clk_i) begin
    product <= a * b;
    acc <= product + acc;
end
```

Use `(* use_dsp = "yes" *)` to force DSP mapping when needed.

### A5. BRAM inference patterns (UG901)

Use standard write-first or read-first RAM coding. Avoid resets on BRAM read-data registers (prevents BRAM inference):

```verilog
reg [31:0] mem [0:1023];
reg [31:0] dout;
always @(posedge clk_i) begin
    if (wr_en) mem[addr] <= wdata;
    dout <= mem[addr];  // no reset — maps to BRAM output register
end
```

Use `(* ram_style = "block" *)` or `(* ram_style = "distributed" *)` to control mapping.

### A6. Resource sharing via enable (Intel UG-20136)

When multiple operations share hardware, use clock-enable and MUX to time-share a single operator rather than instantiating duplicates.

---

## 4. CDC-Aware Timing (Cummings SNUG, UG949)

These rules complement the existing CDC guidelines in `references/synthesis/cdc-guidelines.md`.

### C1. Double-flop synchronizer constraint

Apply `set_max_delay -datapath_only` (not `set_false_path`) so the tool still optimizes the path:

```tcl
set_max_delay -datapath_only -from [get_cells sync_ff1] 1.5
```

### C2. Gray-code for multi-bit counter CDC

When crossing a counter between clock domains, convert to gray code. Only one bit changes per increment. FIFO depth must be power of 2.

### C3. Never MCP on async CDC

`set_multicycle_path` does not solve metastability. It only delays the timing check. Use proper synchronizers instead.

### C4. Handshake for non-counter multi-bit CDC

When gray code is impractical (arbitrary multi-bit data), use req/ack handshake with double-flop synchronizers on both control signals. Latch data only after acknowledge.

---

## How to apply these rules

1. **During RTL generation (step 7):** Apply P1 (clock enable), P5 (memory qualification), A3 (bit-width) by default. These have zero cost and high impact.

2. **During self-review (step 8):** Check for manual clock gating (P1), unbalanced operator trees (A1), oversized counters (A3), missing memory enables (P5).

3. **For timing-critical designs:** Apply T3 (pipeline at boundaries), T6 (control set minimization), T7 (retiming attributes).

4. **For FPGA targets:** Apply A4 (DSP inference), A5 (BRAM inference), P6 (SRL inference) — these directly map to dedicated hardware resources.

5. **For low-power targets:** Apply P3 (operand isolation), P4 (Gray FSM encoding), P2 (gate at lowest level).
