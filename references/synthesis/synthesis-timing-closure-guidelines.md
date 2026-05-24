# Synthesis and Timing Closure Guidelines

## Purpose

This file covers synthesis-aware RTL design and timing closure fundamentals. Use when the task involves synthesis constraints, critical path optimization, area/timing tradeoffs, or timing violation debugging.

Sources: Synopsys Design Compiler User Guide, Cadence Genus User Guide, ARM Cortex-A Series Programmer's Guide for ARMv8-A (timing methodology), "Static Timing Analysis for Nanometer Designs" (Khan, Navabi).

## Synthesis basics

### What synthesis does

- Converts RTL to gate-level netlist using a technology library
- Optimizes for area, timing, or power based on constraints
- Infers sequential elements, memories, and arithmetic from RTL patterns

### RTL patterns that affect synthesis

```verilog
// GOOD: clear mux structure, synthesizes to priority mux
always @(*) begin
  casez ({sel_a, sel_b, sel_c})
    3'b1??: out = a;
    3'b01?: out = b;
    3'b001: out = c;
    default: out = 32'b0;
  endcase
end

// BAD: nested if-else creates deep priority chain
if (sel_a) out = a;
else if (sel_b) out = b;
else if (sel_c) out = c;
else out = 32'b0;
```

### Memory inference

```verilog
// Synthesizable RAM (inferred by most tools)
reg [DW-1:0] mem [0:DEPTH-1];
always @(posedge clk) begin
  if (wen)
    mem[addr] <= wdata;
  rdata <= mem[addr];  // registered read
end
```

- Registered read: one-cycle read latency, infers block RAM
- Combinational read: infers distributed RAM or LUT-based memory
- Do not reset memory arrays element-by-element (prevents RAM inference)

## Timing fundamentals

### Setup and hold

- **Setup**: data must be stable Tsetup before the clock edge
- **Hold**: data must be stable Thold after the clock edge
- **Setup violation**: path is too slow (reduce logic depth or clock frequency)
- **Hold violation**: path is too fast (add delay buffers)

### Clock period and slack

```
Slack = Required time - Arrival time
Positive slack: timing met
Negative slack: timing violated
```

- Setup slack: Tperiod - Tck-q - Tlogic - Tsetup
- Hold slack: Tck-q + Tlogic - Thold

### Critical path

The slowest combinational path between two flip-flops. Reducing critical path delay is the primary timing closure activity.

## SDC/XDC constraints

### Basic clock

```tcl
create_clock -period 5.0 -name clk [get_ports clk]
# 200 MHz target
```

### Input/output delays

```tcl
set_input_delay -clock clk -max 2.0 [get_ports data_in*]
set_output_delay -clock clk -max 2.0 [get_ports data_out*]
# Assume 2ns board delay (placeholder — must be replaced with real data)
```

### Clock groups

```tcl
set_clock_groups -asynchronous -group [get_clocks clk] -group [get_clocks debug_clk]
# Async clocks: no timing paths between them
```

### False paths

```tcl
set_false_path -from [get_ports reset_n]
# Reset is asynchronous, no timing check needed
```

### Multicycle paths

```tcl
set_multicycle_path -setup 2 -from [get_reg A] -to [get_reg B]
# 2-cycle path: data takes 2 clock periods
```

## Timing closure strategies

### 1. RTL restructuring

- Pipeline long combinational paths
- Register outputs of large muxes
- Break wide comparators into staged logic

### 2. Constraint refinement

- Check for false paths that are incorrectly timed
- Verify clock uncertainty and jitter margins
- Confirm IO delays match board-level reality

### 3. Synthesis directives

```tcl
compile_ultra -timing_high_effort_script
set_max_area 0
```

### 4. Physical awareness

- Long routes add delay (wire delay dominates at advanced nodes)
- Floorplanning can reduce critical path length
- Register replication reduces fanout-driven delay

## Area/timing tradeoffs

| Technique | Timing | Area | When to use |
|-----------|--------|------|-------------|
| Pipelining | Better | More FFs | Critical path too long |
| Resource sharing | Worse | Fewer gates | Area-constrained, timing relaxed |
| Logic replication | Better | More gates | Fanout-driven delay |
| Clock gating | Neutral | Slightly more | Power reduction |

## Common mistakes

1. No clock constraint (synthesis uses default, may be wrong)
2. False-pathing everything (hides real timing problems)
3. Not specifying IO delays (synthesis assumes 0, unrealistic)
4. Reset treated as synchronous when it is asynchronous
5. Assuming synthesis results match post-layout timing
6. Not checking hold violations (they are real in silicon)
