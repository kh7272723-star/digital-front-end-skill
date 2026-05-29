# Physical Implementation Awareness Guidelines

## Purpose

This file covers physical design concepts that RTL engineers should understand, with actionable rules for writing RTL that physical-implementation-friendly. Use when the task involves floorplanning, IO planning, area optimization, or RTL decisions that affect physical implementation.

Sources: ARM Physical IP Guidelines, SNUG papers on physical-aware RTL, Synopsys DC User Guide, Cadence RTL Compiler UG, "VLSI Physical Design: From Graph Partitioning to Timing Closure" (Kahng et al.).

## Why RTL engineers need physical awareness

- RTL decisions determine gate count, wire length, and switching activity
- Poor RTL structure can make physical implementation impossible or slow
- Understanding physical constraints prevents late-stage surprises
- The best time to fix physical problems is in RTL, not in layout

---

## 1. Floorplan-aware RTL structuring

### Core principle

RTL hierarchy should mirror the physical floorplan. Each major module becomes a floorplan partition with clean registered boundaries.

### Rules

| Rule | Why |
|------|-----|
| One function per module, registered I/O | Clean partition boundary for floorplan |
| No cross-hierarchy combinational paths | Creates long routes that are hard to time |
| Top-level module groups related submodules | Enables physical clustering |
| Partition ports are registered (not combinational) | Clean timing boundary, easier placement |
| Keep partition size 10K-100K gates | Too small = overhead, too large = hard to place |

### Example: good vs bad hierarchy

```verilog
// BAD: combinational path across hierarchy
module top (
    input  [31:0] a_i, b_i,
    output [31:0] sum_o
);
    wire [31:0] a_delayed, b_delayed;
    delay_stage u_delay (.a_i(a_i), .b_i(b_i), .a_o(a_delayed), .b_o(b_delayed));
    assign sum_o = a_delayed + b_delayed;  // combinational: crosses hierarchy
endmodule

// GOOD: registered boundary at hierarchy
module top (
    input  clk_i,
    input  [31:0] a_i, b_i,
    output [31:0] sum_o
);
    wire [31:0] a_delayed, b_delayed;
    delay_stage u_delay (.clk_i(clk_i), .a_i(a_i), .b_i(b_i),
                         .a_o(a_delayed), .b_o(b_delayed));
    reg [31:0] sum_q;
    always @(posedge clk_i)
        sum_q <= a_delayed + b_delayed;  // registered: clean partition boundary
    assign sum_o = sum_q;
endmodule
```

---

## 2. Macro placement guidance

### What are macros

Macros are hard IP blocks: SRAM, ROM, PLL, analog blocks, IO pads. Their placement is fixed early in the flow and affects everything around them.

### Rules

| Rule | Why |
|------|-----|
| Place data-path memory near the logic that reads/writes it | Minimizes data bus wire length |
| Keep analog blocks away from high-switching logic | Reduces noise coupling |
| Macro abutment: align adjacent macros on grid | Avoids routing channel waste |
| Reserve routing channels around large macros | Macros block metal layers |
| Document macro placement intent in RTL comments | Guides physical designer |

### RTL implications

```verilog
// Group memory and its controller in the same module
// so physical designer places them together
module data_buffer (
    input  clk_i,
    input  wr_en_i,
    input  [ADDR_W-1:0] addr_i,
    input  [DATA_W-1:0] wdata_i,
    output [DATA_W-1:0] rdata_o
);
    // SRAM macro instance (placed by physical designer)
    sram_256x32 u_sram (
        .clk_i(clk_i),
        .wr_en_i(wr_en_i),
        .addr_i(addr_i),
        .wdata_i(wdata_i),
        .rdata_o(rdata_o)
    );

    // Controller logic in same module = same floorplan region
    // ...
endmodule
```

---

## 3. Congestion-aware coding

### What causes congestion

- Too many signals crossing a small area
- High-fanout nets requiring wide routing
- Long buses crossing partition boundaries
- Mux-heavy logic with many inputs

### Rules

| Rule | Why |
|------|-----|
| Group related bus signals at partition ports | Enables bus routing alignment |
| Replicate high-fanout registers (>50 fanout) | Reduces routing demand in one spot |
| Decompose wide muxes into hierarchical mux tree | Reduces input density at one location |
| Use pipeline registers at partition boundaries | Reduces cross-partition signal count |
| Avoid deep priority chains (>8 levels) | Creates hotspots of logic density |

### High-fanout register replication

```verilog
// BAD: single register drives 100 destinations
reg valid_q;
always @(posedge clk_i) valid_q <= valid_d;
// 100 consumers of valid_q → routing congestion

// GOOD: replicate register at synthesis
// RTL is the same, but synthesis attribute guides tool
(* max_fanout = 50 *)
reg valid_q;
always @(posedge clk_i) valid_q <= valid_d;
// Tool replicates to 2 copies, each driving ~50
```

### Mux decomposition

```verilog
// BAD: 16:1 mux → high input density
assign out = sel[3:0] == 4'd0  ? in0  :
             sel[3:0] == 4'd1  ? in1  :
             // ... 14 more ...
             sel[3:0] == 4'd15 ? in15 : 16'b0;

// GOOD: hierarchical 2-level mux → lower density
wire [3:0] sel_h = sel[3:2];  // high bits
wire [3:0] sel_l = sel[1:0];  // low bits
wire [15:0] stage0 = (sel_l == 2'd0) ? {in3,  in2,  in1,  in0}  :
                      (sel_l == 2'd1) ? {in7,  in6,  in5,  in4}  :
                      (sel_l == 2'd2) ? {in11, in10, in9,  in8}  :
                                        {in15, in14, in13, in12};
assign out = stage0[sel_h*4 +: 4];
```

---

## 4. Wire delay-aware pipeline

### Core principle

At 28nm and below, wire delay dominates gate delay for long paths. The fix is to pipeline long paths, not to optimize logic depth.

### When to add pipeline stages

| Physical distance | Clock frequency | Action |
|-------------------|----------------|--------|
| < 500um, < 500MHz | — | No pipeline needed |
| > 1mm, any frequency | — | Add 1 pipeline stage |
| > 2mm, > 500MHz | — | Add 2 pipeline stages |
| Cross-chip, any | — | Add pipeline + register at boundary |

### Pipeline insertion pattern

```verilog
// Long path: data crosses from block A to block B (2mm apart)
// Fix: register at the boundary

// Block A output (near its source)
always @(posedge clk_i) begin
    data_a_out_q <= data_a_computed;  // register close to source
end

// Block B input (near its destination)
always @(posedge clk_i) begin
    data_b_in_q <= data_a_out_q;     // register close to destination
end
// Now the long wire is between two registers → timing is ck-to-q + wire + setup
// Without pipeline: combinational path + wire = timing failure
```

### Rules

- Register outputs at module boundaries (PH1)
- Add pipeline stages for paths crossing floorplan partitions
- Document pipeline latency in the timing contract
- Use `power-timing-area.md` T2 for pipeline-at-boundary rules

---

## 5. IR drop mitigation in RTL

### What is IR drop

Current flowing through the power grid causes voltage drop. High switching activity in a small area creates localized IR drop that slows logic and can cause functional failures.

### RTL-level mitigation

| Technique | How | Impact |
|-----------|-----|--------|
| Clock gating | Disable clocks to idle logic | Reduces switching activity (P1) |
| Activity spreading | Distribute operations across time | Reduces peak current |
| Clock staggering | Offset clock edges for different blocks | Reduces simultaneous switching |
| Reset sequencing | Stagger reset release | Avoids power-on current spike |

### Clock staggering pattern

```verilog
// Stagger reset release to avoid simultaneous switching
reg [3:0] rst_release_q;
always @(posedge clk_i) begin
    rst_release_q <= {rst_release_q[2:0], 1'b1};
end
wire rst_block0 = rst_i | ~rst_release_q[0];  // releases first
wire rst_block1 = rst_i | ~rst_release_q[1];  // releases 1 cycle later
wire rst_block2 = rst_i | ~rst_release_q[2];  // releases 2 cycles later
wire rst_block3 = rst_i | ~rst_release_q[3];  // releases 3 cycles later
```

---

## 6. Standard cell library awareness

### Drive strength selection

| Path type | Drive strength | Why |
|-----------|---------------|-----|
| Short path, low fanout | X1, X2 | Minimum area and power |
| Medium path, medium fanout | X4, X8 | Balanced |
| Critical path, high fanout | X16, X32 | Maximum speed, but area/power cost |
| Clock buffer | X8, X16 | Balanced skew and power |

### Vt tradeoff

| Cell type | Speed | Leakage | Use case |
|-----------|-------|---------|----------|
| HVT (High Vt) | Slow | Low | Non-critical paths, always-on logic |
| SVT (Standard Vt) | Medium | Medium | Default |
| LVT (Low Vt) | Fast | High | Critical paths only |

### RTL implications

- RTL cannot specify Vt or drive strength (synthesis tool decides)
- But RTL structure influences tool decisions:
  - Clean logic cones → easier for tool to optimize
  - Deep combinational chains → tool forced to use LVT on many cells
  - Wide muxes → tool inserts large drivers → area/power cost

---

## 7. CTS-aware design

### What CTS does

Clock Tree Synthesis distributes the clock signal to all flip-flops with minimal skew. The clock tree is built from clock buffers/inverters in a balanced structure.

### RTL rules

| Rule | Why |
|------|-----|
| Minimize number of clock domains | Each domain needs its own tree |
| Use enable signals, not gated clocks | Lets CTS build one clean tree |
| Place clock gating at root, not leaves | CTS handles gating insertion |
| Document clock relationships | CTS constraints require this |

### Clock domain grouping

```verilog
// GOOD: all logic in one clock domain with enables
always @(posedge clk_i) begin
    if (ce_group_a) /* group A logic */;
    if (ce_group_b) /* group B logic */;
end

// BAD: multiple gated clocks from same source
wire clk_a = clk_i & en_a;
wire clk_b = clk_i & en_b;
always @(posedge clk_a) /* group A */;  // CTS must build 2 trees
always @(posedge clk_b) /* group B */;
```

---

## 8. Area optimization techniques

### Resource sharing

```verilog
// BAD: two adders (area = 2x)
wire [31:0] sum_a = a + b;
wire [31:0] sum_c = c + d;

// GOOD: shared adder with mux (area = 1x + mux, slower)
reg [31:0] op1, op2;
wire [31:0] result = op1 + op2;
// Time-multiplex: first cycle compute a+b, second cycle c+d
```

### Memory vs logic tradeoff

| Pattern | Area | Speed | Use when |
|---------|------|-------|----------|
| Register file | High | Fast | Small depth (<16), fast access needed |
| SRAM macro | Low | Medium | Large depth (>64), area-constrained |
| Distributed RAM (LUT) | Medium | Fast | FPGA, small depth |

### Register packing

```verilog
// BAD: separate enables for each register → more muxes, more area
always @(posedge clk_i) begin
    if (ce_a) reg_a <= d_a;
    if (ce_b) reg_b <= d_b;
    if (ce_c) reg_c <= d_c;
end

// GOOD: common enable when data is related → fewer muxes
always @(posedge clk_i) begin
    if (ce_abc) begin
        reg_a <= d_a;
        reg_b <= d_b;
        reg_c <= d_c;
    end
end
```

### Quantitative area estimates (28nm reference)

| Component | Area |
|-----------|------|
| Flip-flop | ~1.5 um² |
| 32-bit adder | ~200 um² |
| 32-bit multiplier | ~3000 um² |
| 32-bit comparator | ~100 um² |
| 4:1 mux (32-bit) | ~80 um² |
| 256x32 SRAM | ~5000 um² |

Use `power-timing-area.md` A1-A6 for detailed area optimization rules.

---

## 9. Yosys as physical proxy

When backend tools are unavailable, use Yosys synthesis output as a proxy for physical metrics:

```bash
yosys -p "read_verilog design.v; synth -flatten; stat"
```

### What to check

| Yosys metric | Physical meaning | Threshold |
|--------------|-----------------|-----------|
| Number of cells | Area proxy | Compare with similar designs |
| Number of wires | Routing complexity | High wire/cell ratio = congestion risk |
| Number of memories | Macro count | Each memory = physical macro |
| Critical path (ltp) | Timing proxy | >25 gates = may need pipeline |
| Latch count | Should be 0 | Latches = design error (E2) |

---

## Common mistakes

1. Ignoring wire delay (assuming gate delay dominates)
2. Cross-hierarchy combinational paths (unroutable)
3. Too many clock domains (CTS complexity explodes)
4. Not considering IR drop during RTL design
5. Assuming pre-layout timing is accurate
6. Not registering partition boundary signals
7. High-fanout nets without replication (congestion hotspot)
8. Memory macro too far from its data path consumer
9. Bus signals scattered across partition boundaries
