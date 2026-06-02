# FIFO example patterns

## Source policy
Use FIFO examples that make boundary behavior explicit.
Prefer simple Verilog that exposes pointers, occupancy, and simultaneous write/read behavior clearly.
Use `naming-guidelines.md` for signal names and `cycle-trace-guidelines.md` before selecting a FIFO implementation.

## 1. Occupancy-based FIFO skeleton

```verilog
wire wr_do;
wire rd_do;

assign wr_do = wr_en_i && !full_o;
assign rd_do = rd_en_i && !empty_o;

always @(posedge clk_i) begin
  if (rst_i) begin
    wr_ptr <= 3'd0;
    rd_ptr <= 3'd0;
    count  <= 4'd0;
  end else begin
    if (wr_do)
      wr_ptr <= wr_ptr + 3'd1;
    if (rd_do)
      rd_ptr <= rd_ptr + 3'd1;
    case ({wr_do, rd_do})
      2'b10: count <= count + 4'd1;
      2'b01: count <= count - 4'd1;
      default: count <= count;
    endcase
  end
end
```

Pattern rule:
- define write/read legality explicitly
- keep occupancy updates consistent with pointer updates
- simultaneous write/read behavior must be defined in the contract
- this conservative skeleton rejects `wr_en` when full even if `rd_en` is high in the same cycle
- if full+read should accept a new write, specify memory read-during-write behavior before coding

## 2. Full and empty generation idea

```verilog
assign empty_o = (count_q == 4'd0);
assign full_o  = (count_q == DEPTH[3:0]);
```

Pattern rule:
- full and empty should come from one consistent occupancy model
- do not allow a hidden second truth source for boundary state

## 3. FWFT (First-Word-Fall-Through) pattern — STANDARD

Use FWFT as the default FIFO output style for all data-path FIFOs. FWFT exposes the head entry combinationally, so the consumer sees valid data without issuing a read-enable first. This eliminates the one-cycle read latency that registered-output FIFOs introduce.

**FWFT implementation (combinational read):**

```verilog
// Memory read: combinational — data available same cycle as rd_ptr
wire [DATA_WIDTH-1:0] rdata = mem[rd_ptr_q];

// FWFT: output is valid whenever queue is non-empty
// Consumer sees data immediately; rd_en_i advances the read pointer
assign rdata_o = rdata;
assign empty_o = (count_q == 0);
assign full_o  = (count_q == DEPTH);

// Read pointer advance: only on explicit rd_en_i
assign rd_do = rd_en_i && !empty_o;
```

**Why FWFT is the standard:**
- No read latency: consumer sees data on the same cycle `empty_o` is low
- No pipeline staging needed: data-path timing is one cycle shorter
- Simpler integration: `assign data = fifo_rdata; assign fifo_rd_en = consume;`

**Registered output pattern (NOT recommended for data paths):**

```verilog
// Registered read: data appears ONE CYCLE after rd_do
reg [DATA_WIDTH-1:0] rdata_q;
always @(posedge clk_i) begin
    if (rd_do)
        rdata_q <= mem[rd_ptr_q];
end
assign rdata_o = rdata_q;
```

This pattern adds one cycle of read latency. When used in AXI W data paths, it causes a one-beat data shift: every beat receives the previous beat's data. See bug pattern F1 in `references/debug/bug-pattern-library.md`.

**When registered output is acceptable:**
- Status/count registers where one-cycle latency doesn't affect protocol timing
- Configuration registers read infrequently
- Never in AXI R/W data paths, never in handshake data paths with protocol timing requirements

## 4. FWFT timing analysis for AXI data paths

When a FWFT FIFO feeds an AXI W channel:

**Design must first declare the W data mode** (see P12 in `references/axi-dma/axi-dma-channel-guidelines.md`):

**Continuous/full-burst-buffered mode (conservative local policy):**
```
Cycle 0: WVALID asserts (w_active_q, full burst pre-buffered in FIFO)
         WDATA = fifo_rdata (combinational, valid this cycle)
         Slave sees: WVALID=1, WDATA=beat_0 ✓
Cycle 1: w_fire → fifo_rd_en → rd_ptr advances
         WDATA = fifo_rdata (now shows beat_1)
         Slave sees: WVALID=1, WDATA=beat_1 ✓
```

**Elastic/per-beat buffered mode (legal if contract allows):**
```
Cycle 0: WVALID asserts (have_next_wbeat && !fifo_empty)
         WDATA = fifo_rdata (combinational, valid this cycle)
         Slave sees: WVALID=1, WDATA=beat_0 ✓
Cycle 1: FIFO empty → WVALID deasserts (legal bubble)
         Slave sees: WVALID=0 (no beat presented)
Cycle 2: data arrives → WVALID asserts with beat_1
         Slave sees: WVALID=1, WDATA=beat_1 ✓
Note: every presented beat must hold WVALID/WDATA/WSTRB/WLAST stable until WREADY.
```

With registered output (WRONG):
```
Cycle 0: WVALID asserts
         WDATA = rdata_q (STALE — from previous read or reset value)
         Slave sees: WVALID=1, WDATA=garbage ✗
Cycle 1: w_fire → fifo_rd_en → rd_ptr advances
         rdata_q updates NEXT cycle (registered)
         WDATA = rdata_q (still stale, now beat_0)
         Slave sees: WVALID=1, WDATA=beat_0 (shifted!) ✗
```

## 5. Read/write memory access idea

```verilog
always @(posedge clk_i) begin
  if (wr_do)
    mem[wr_ptr] <= din;
end
// Read is combinational (FWFT):
assign rdata = mem[rd_ptr_q];
```

Pattern rule:
- memory access must follow the same write/read contract as the control logic
- data output must be combinational (FWFT) for data-path FIFOs
- define old-data versus new-data behavior for same-address read/write if the design permits it

## 6. Dual-mode FIFO with generate block

When a FIFO module needs to support both FWFT and standard output modes, use a `generate` block:

```verilog
module sync_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 16,
    parameter FWFT       = 0        // 0: standard, 1: FWFT
)(
    input  wire                  clk_i,
    input  wire                  rst_i,
    input  wire                  wr_en_i,
    input  wire [DATA_WIDTH-1:0] wdata_i,
    output wire                  full_o,
    input  wire                  rd_en_i,
    output wire [DATA_WIDTH-1:0] rdata_o,
    output wire                  empty_o,
    output wire [$clog2(DEPTH):0] count_o
);
    // ... pointers, memory, count logic (same for both modes) ...

    // Read output: mode-selected via generate
    generate
        if (FWFT) begin : gen_fwft
            // FWFT: combinational read — data valid same cycle as empty_o deasserts
            assign rdata_o = mem[rd_ptr_q[ADDR_W-1:0]];
        end else begin : gen_standard
            // Standard: registered read — data valid one cycle after rd_do
            reg [DATA_WIDTH-1:0] rdata_q;
            always @(posedge clk_i) begin
                if (rd_do)
                    rdata_q <= mem[rd_ptr_q[ADDR_W-1:0]];
            end
            assign rdata_o = rdata_q;
        end
    endgenerate
endmodule
```

**Rule:** default to FWFT (`FWFT=1`) for data-path FIFOs. Use standard mode (`FWFT=0`) only for command/status queues where one-cycle latency is acceptable.

## What to capture from FIFO examples
- how depth is represented
- how full and empty are derived
- what happens when write and read occur together
- whether data output is registered or immediate (FWFT = combinational, preferred)
- what overflow and underflow protections are required
- whether the FIFO is used in a protocol data path (if yes, FWFT is mandatory)
- whether dual-mode (FWFT/standard) is needed via generate block
