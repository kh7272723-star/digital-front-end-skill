# CDC guidelines

## Purpose

Use this file for clock-domain crossing, multi-clock reset, async FIFO, synchronizer, metastability, and CDC review requests.
CDC correctness is a methodology topic; do not claim it from RTL inspection alone.

## Safe pattern selection

- Single-bit slow level: two-flop synchronizer in the destination clock domain.
- Single-cycle pulse: convert to toggle or handshake before crossing.
- Multi-bit coherent value: use request/acknowledge with source-side data hold, a gray-coded counter, or an async FIFO.
- Stream or queue traffic: use an async FIFO with gray-coded pointers and full/empty checks.
- Reset: asynchronous assertion is allowed by project style, but deassertion must be synchronized per destination clock domain.

Do not synchronize each bit of a multi-bit bus independently and call it coherent.

## Required contract fields

- source clock and destination clock relationship,
- data coherence requirement,
- event loss tolerance,
- reset assertion and deassertion policy,
- maximum source and destination rates,
- chosen CDC primitive and constraints.

## Verification and constraints

- Simulate with unrelated clock periods and varied phase offsets.
- For handshake CDC, check that data is stable while the request is outstanding.
- For async FIFO, check no overflow, no underflow, and one-bit gray pointer changes.
- Mark synchronizer flops with project-approved attributes such as `ASYNC_REG`.
- Declare unrelated clocks with the project STA method, commonly `set_clock_groups -asynchronous`.
- Use CDC tools or formal apps for signoff; directed simulation is only a sanity check.

## Synthesis attributes for synchronizers

Mark all synchronizer flip-flops with synthesis attributes so the toolchain places them in the same SLICE/CLB and prevents optimization:

```verilog
(* ASYNC_REG = "TRUE" *)
reg [PTR_WIDTH-1:0] rd_ptr_gray_wrclk_q;   // first sync stage
(* ASYNC_REG = "TRUE" *)
reg [PTR_WIDTH-1:0] rd_ptr_gray_wrclk_2q;  // second sync stage
```

**Vivado/Quartus:** `(* ASYNC_REG = "TRUE" *)`
**Synopsys DC:** `// synopsys async_set_reset "rst_ni"` on the reset branch
**Cadence Genus:** check vendor documentation for equivalent attribute

Without ASYNC_REG, the synthesis tool may optimize away the synchronizer or place the FFs far apart, defeating the metastability MTBF guarantee.

## Reset synchronizer pattern for CDC

Asynchronous assertion / synchronized deassertion is the standard CDC reset pattern. Use a reset synchronizer per destination domain:

```verilog
// Reset synchronizer: async assert, sync deassert
reg rst_meta_q;
reg rst_sync_q;
always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        rst_meta_q <= 1'b0;  // async assertion
        rst_sync_q <= 1'b0;
    end else begin
        rst_meta_q <= 1'b1;  // sync deassertion (2-stage)
        rst_sync_q <= rst_meta_q;
    end
end
wire rst_synced = ~rst_sync_q;  // active-high synchronized reset
```

This ensures:
- Reset asserts immediately (asynchronous) on `rst_ni=0`
- Reset deasserts synchronously (after 2 clock edges) preventing metastability on release
- Each clock domain gets its own synchronized reset

Naming: `rst_meta_q` (first sync stage), `rst_sync_q` (second sync stage, output).

## Async FIFO template — complete synthesizable implementation

**Source:** Cliff Cummings, "Simulation and Synthesis Techniques for Asynchronous FIFO Design," SNUG San Jose 2002. This is the canonical async FIFO reference used across the industry.

### Core principle

Async FIFO uses gray-coded pointers with an extra MSB (wrap bit) to safely cross clock domains. The write side increments a binary pointer, converts to gray, and crosses to the read domain via 2FF synchronizers. The read side does the same in reverse. Full/empty are detected conservatively by comparing gray pointers in their respective domains.

Key rules from Cummings:
- Binary pointers are used for natural increment (write side) and memory addressing (read side)
- Gray-coded pointers are used ONLY for CDC crossing — they never drive memory addresses directly
- Extra MSB bit distinguishes "full" (pointers at same index, opposite wrap) from "empty" (pointers identical)
- Full is detected in the write domain: compare `wr_gray_next` against synchronized `rd_gray`
- Empty is detected in the read domain: compare `rd_gray` against synchronized `wr_gray`
- 2FF synchronizers are placed immediately after the gray pointer registers in the destination domain
- ASYNC_REG attribute on ALL synchronizer flip-flops
- Conservative full/empty: full may assert slightly early, empty may assert slightly late. Never the opposite.

### Complete template

```verilog
`default_nettype none

//============================================================================
// async_fifo — CDC crossing FIFO with gray-coded pointers and 2FF syncs
//
// Ref: Cliff Cummings, SNUG San Jose 2002
//      "Simulation and Synthesis Techniques for Asynchronous FIFO Design"
//============================================================================

module async_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH       = 8,          // must be power of 2
    parameter PTR_WIDTH   = $clog2(DEPTH) + 1  // +1 for wrap bit
)(
    // Write domain (wr_clk)
    input  wire                  wr_clk_i,
    input  wire                  wr_rst_i,       // synchronized to wr_clk
    input  wire                  wr_en_i,
    input  wire [DATA_WIDTH-1:0] wdata_i,
    output wire                  full_o,

    // Read domain (rd_clk)
    input  wire                  rd_clk_i,
    input  wire                  rd_rst_i,       // synchronized to rd_clk
    input  wire                  rd_en_i,
    output wire [DATA_WIDTH-1:0] rdata_o,
    output wire                  empty_o
);

    //----------------------------------------------------------------------
    // Memory (inferred dual-port register array)
    //----------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    //----------------------------------------------------------------------
    // Write domain: binary pointers + gray conversion
    //----------------------------------------------------------------------
    reg  [PTR_WIDTH-1:0] wr_ptr_bin_q;
    wire [PTR_WIDTH-1:0] wr_ptr_bin_next;
    reg  [PTR_WIDTH-1:0] wr_ptr_gray_q;

    assign wr_ptr_bin_next = wr_ptr_bin_q + {{PTR_WIDTH-1{1'b0}}, 1'b1};

    // Write-side data store (independent clock)
    wire wr_do;
    assign wr_do = wr_en_i && !full_o;

    always @(posedge wr_clk_i) begin
        if (wr_do)
            mem[wr_ptr_bin_q[PTR_WIDTH-2:0]] <= wdata_i;
    end

    always @(posedge wr_clk_i) begin
        if (wr_rst_i) begin
            wr_ptr_bin_q  <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray_q <= {PTR_WIDTH{1'b0}};
        end else if (wr_do) begin
            wr_ptr_bin_q  <= wr_ptr_bin_next;
            wr_ptr_gray_q <= (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;  // bin->gray
        end
    end

    //----------------------------------------------------------------------
    // Read domain: binary pointers + gray conversion
    //----------------------------------------------------------------------
    reg  [PTR_WIDTH-1:0] rd_ptr_bin_q;
    wire [PTR_WIDTH-1:0] rd_ptr_bin_next;
    reg  [PTR_WIDTH-1:0] rd_ptr_gray_q;

    assign rd_ptr_bin_next = rd_ptr_bin_q + {{PTR_WIDTH-1{1'b0}}, 1'b1};

    wire rd_do;
    assign rd_do = rd_en_i && !empty_o;

    always @(posedge rd_clk_i) begin
        if (rd_rst_i) begin
            rd_ptr_bin_q  <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray_q <= {PTR_WIDTH{1'b0}};
        end else if (rd_do) begin
            rd_ptr_bin_q  <= rd_ptr_bin_next;
            rd_ptr_gray_q <= (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;  // bin->gray
        end
    end

    //----------------------------------------------------------------------
    // 2FF synchronizers: wr_gray → rd domain (for empty detection)
    //----------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] wr_gray_sync_q;
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] wr_gray_sync_2q;

    always @(posedge rd_clk_i) begin
        if (rd_rst_i) begin
            wr_gray_sync_q   <= {PTR_WIDTH{1'b0}};
            wr_gray_sync_2q  <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_gray_sync_q   <= wr_ptr_gray_q;     // launched from wr_clk domain
            wr_gray_sync_2q  <= wr_gray_sync_q;
        end
    end

    //----------------------------------------------------------------------
    // 2FF synchronizers: rd_gray → wr domain (for full detection)
    //----------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] rd_gray_sync_q;
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] rd_gray_sync_2q;

    always @(posedge wr_clk_i) begin
        if (wr_rst_i) begin
            rd_gray_sync_q   <= {PTR_WIDTH{1'b0}};
            rd_gray_sync_2q  <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_gray_sync_q   <= rd_ptr_gray_q;     // launched from rd_clk domain
            rd_gray_sync_2q  <= rd_gray_sync_q;
        end
    end

    //----------------------------------------------------------------------
    // Full detection (write domain)
    // Full when: wr_gray_next == {~rd_sync[PTR_W-1:PTR_W-2], rd_sync[PTR_W-3:0]}
    // i.e., same address + opposite wrap bits
    //----------------------------------------------------------------------
    wire [PTR_WIDTH-1:0] wr_gray_next;
    assign wr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

    wire full_comb;
    assign full_comb = (wr_gray_next[PTR_WIDTH-1:PTR_WIDTH-2]
                        == ~rd_gray_sync_2q[PTR_WIDTH-1:PTR_WIDTH-2])
                    && (wr_gray_next[PTR_WIDTH-3:0]
                        == rd_gray_sync_2q[PTR_WIDTH-3:0]);

    reg full_q;
    always @(posedge wr_clk_i) begin
        if (wr_rst_i)
            full_q <= 1'b0;
        else
            full_q <= full_comb;
    end
    assign full_o = full_q;

    //----------------------------------------------------------------------
    // Empty detection (read domain)
    // Empty when: rd_gray == wr_sync (all bits equal)
    //----------------------------------------------------------------------
    wire empty_comb;
    assign empty_comb = (rd_ptr_gray_q == wr_gray_sync_2q);

    reg empty_q;
    always @(posedge rd_clk_i) begin
        if (rd_rst_i)
            empty_q <= 1'b1;
        else
            empty_q <= empty_comb;
    end
    assign empty_o = empty_q;

    //----------------------------------------------------------------------
    // Data output: FWFT (combinational read from registered pointer)
    //----------------------------------------------------------------------
    assign rdata_o = mem[rd_ptr_bin_q[PTR_WIDTH-2:0]];

endmodule
`default_nettype wire
```

### Key design decisions

| Decision | Choice | Rationale (Cummings 2002) |
|----------|--------|---------------------------|
| Pointer representation | Binary for addressing, gray for CDC | Binary increment is unambiguous; gray prevents multi-bit metastability |
| Extra MSB (wrap bit) | PTR_WIDTH = $clog2(DEPTH) + 1 | Required to distinguish full (msbs differ) from empty (all equal) |
| Full detection | Registered, conservative (uses next-pointer) | `wr_gray_next` vs synced `rd_gray`: early-full prevents overflow |
| Empty detection | Registered, conservative (uses current-pointer) | `rd_gray` vs synced `wr_gray`: slightly delayed empty prevents underflow |
| Synchronizer depth | 2FF | Industry standard for technology nodes >= 28nm. See MTBF section below for when 3FF is needed. |
| Full/empty registration | Registered (not combinational) | Prevents delta-cycle oscillation through write/read-enable feedback paths |
| Memory | Inferred register array | Works for depths ≤ 32. For deeper FIFOs, use SRAM inference with attribute guidance. |
| Output style | FWFT (combinational read) | Consistent with sync FIFO standard; eliminates read latency |

### Gray code formula

The standard binary-to-gray conversion (Cummings Sec.3.1):

```
gray = (bin >> 1) ^ bin
```

This is a linear XOR operation — the i-th gray bit equals `bin[i] ^ bin[i+1]`. For synthesis, no explicit gray-to-binary is needed since full/empty compare directly in the gray domain using the formulas above.

### When NOT to use this template

- Depths > 32: use inferred true dual-port SRAM with vendor-specific attributes
- Widths > 512 bits: consider narrower FIFO + serializer/deserializer
- Multi-synchronous clock relationships: use a mesochronous FIFO (simpler, skips gray coding)
- Depths not a power of 2: gray-pointer comparison formulas change — consult Cummings Sec.5

## CDC constraints (SDC) — concrete syntax

**Source:** Synopsys Design Constraints (SDC) standard, Accellera/IEEE; Xilinx UG903 Vivado Using Constraints, Ch.4 "Timing Exceptions."

The skill previously said "declare unrelated clocks" without showing how. Below is the concrete SDC/Tcl syntax needed for CDC signoff.

### Clock group declaration (mandatory for any CDC design)

```tcl
# Define the two clocks
create_clock -name wr_clk -period 2.5 [get_ports wr_clk_i]   ;# 400 MHz
create_clock -name rd_clk -period 10.0 [get_ports rd_clk_i]  ;# 100 MHz

# Declare them asynchronous — STA ignores all cross-domain paths
set_clock_groups -asynchronous \
    -group [get_clocks wr_clk] \
    -group [get_clocks rd_clk]
```

`set_clock_groups -asynchronous` tells the static timing analyzer that these clocks have no fixed phase relationship. Without this, STA will compute worst-case launch/capture across domains and report false violations. With it, only paths within each group are analyzed.

### False path on synchronized signals (supplementary)

After `set_clock_groups -asynchronous`, synchronizer paths are already excluded from timing by the clock group declaration. However, explicitly marking synchronizer outputs as false paths documents the CDC intent and protects against accidental clock-group configuration errors:

```tcl
# Mark synchronizer output as intentionally unsynchronized
set_false_path -from [get_cells -hier -filter {NAME =~ *wr_gray_sync_2q*}] \
               -to   [get_cells -hier -filter {NAME =~ *empty_q*}] \
               -comment "CDC: wr_gray synchronized by 2FF in rd_clk domain"
```

### What happens WITHOUT these constraints

If `set_clock_groups` is omitted:
- Synthesis tries to optimize cross-domain timing paths → adds buffers on synchronizer nets → destroys MTBF guarantee
- Place-and-route spreads synchronizer FFs apart → adds routing delay → reduces t_meta → MTBF plummets
- STA reports thousands of cross-domain violations → masks real within-domain violations

### Constraint checklist

- [ ] `create_clock` for each input clock port with correct period
- [ ] `set_clock_groups -asynchronous` for each pair of unrelated clocks
- [ ] Generated clocks declared with `create_generated_clock` if PLL/MMCM is present
- [ ] No `set_false_path -from * -to *` blanket false paths (masks real violations)
- [ ] Synchronizer cells explicitly marked with ASYNC_REG attribute (RTL-level) AND DONT_TOUCH (constraint-level, if tool requires)

## MTBF and synchronizer depth

**Source:** Xilinx XAPP094 "Metastability Recovery"; Cummings SNUG 2008 Sec.4 "Synchronizer MTBF"; W.J. Dally "Digital Design Using VHDL" Ch.28.

### The MTBF formula

The mean time between metastability-induced failures for an N-stage synchronizer is:

```
MTBF = e^(t_meta / τ) / (f_clk · f_data · T_w)
```

Where:
- **t_meta** = settling time = (N × T_clk) − t_setup − t_path_delay — the time available for metastability to resolve
- **τ** = resolution time constant, technology-dependent (~25–50ps for 28nm, ~5–15ps for 7nm)
- **f_clk** = destination clock frequency
- **f_data** = source data toggle rate (typically f_clk_source / 2)
- **T_w** = metastability window, technology-dependent (~10–50ps for 28nm)

### Why 2FF may NOT be enough at high frequency

2FF is the industry baseline, but it has limits:

| Destination freq | t_meta (2FF) | Approx MTBF (τ=50ps, 28nm) | Acceptable? |
|------------------|-------------|---------------------------|-------------|
| 100 MHz | ~20 ns | >1000 years | Yes |
| 200 MHz | ~10 ns | ~100 years | Yes |
| 400 MHz | ~5 ns | ~hours | **No — need 3FF** |
| 800 MHz | ~2.5 ns | ~seconds | **No — need 3FF or 4FF** |
| 1 GHz+ | ~1.5 ns | ~milliseconds | **No — need 4FF+** |

The exponential dependence on t_meta means each additional FF stage adds a full clock period of settling time, increasing MTBF by a factor of e^(T_clk/τ), which is enormous (e^20 ≈ 5×10^8 for 100MHz with τ=50ps).

### When to use 3FF

Use a 3-stage synchronizer (per Cummings 2008) when:
- Destination clock ≥ 300 MHz (even 28nm)
- Advanced process nodes (≤ 16nm) where τ is smaller
- Safety-critical systems (ISO 26262, DO-254)
- High-reliability datacenter/telecom (target MTBF > 10^9 years)

### 3FF synchronizer pattern

```verilog
(* ASYNC_REG = "TRUE" *) reg [W-1:0] sync_q1;
(* ASYNC_REG = "TRUE" *) reg [W-1:0] sync_q2;
(* ASYNC_REG = "TRUE" *) reg [W-1:0] sync_q3;   // third stage

always @(posedge dst_clk_i) begin
    if (dst_rst_i) begin
        sync_q1 <= {W{1'b0}};
        sync_q2 <= {W{1'b0}};
        sync_q3 <= {W{1'b0}};
    end else begin
        sync_q1 <= async_signal;
        sync_q2 <= sync_q1;
        sync_q3 <= sync_q2;
    end
end
wire sync_out = sync_q3;
```

Design choice: the async FIFO template above uses 2FF. For finfet nodes or frequencies above 300MHz, change to 3FF by adding `sync_3q` registers and updating the full/empty comparison to use the third stage.

### What simulation CANNOT tell you

Icarus Verilog, Verilator, and all event-driven simulators do NOT model:
- Metastability (setup/hold violations produce X, not metastable behavior)
- MTBF (simulation shows zero failures even with MTBF = 1 second)
- Reconvergence hazards (two independently synchronized bits of a gray bus reconverging at different times)

**Only STA + CDC formal tools (SpyGlass CDC, Questa CDC, Jasper CDC) can sign off CDC correctness.** The RTL patterns in this file are necessary but insufficient without tool-based verification.
