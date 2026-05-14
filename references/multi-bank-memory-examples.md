# Multi-bank memory controller patterns

## Source authority

This file distills standard multi-bank memory controller architecture as found in DDR SDRAM controllers, GPU memory subsystems, and high-throughput FPGA designs. The concept is fundamental to memory system design and appears across vendor documentation and open-source implementations. No single canonical open-source module covers the generic pattern — this file synthesizes the common approach.

## When to use multi-bank memory

Use when:
- A single-port memory's bandwidth is insufficient for multiple concurrent accessors.
- Different address regions can be mapped to independent memory banks.
- Accessors have independent throughput needs and can tolerate occasional bank conflicts.

Do NOT use when:
- A single accessor needs guaranteed minimum latency — arbitration adds jitter.
- The number of accessors equals 1 — use a single-port memory with simple arbitration.
- Bank conflicts are frequent and performance degrades below a single fast memory — profile first.

## Architecture

```
addr_i ──► bank_decode ──► bank_0 (valid/ready) ──┐
data_i ────────────────────► bank_1 (valid/ready) ──┤
valid_i ───────────────────► ...                    ├─► output_arbiter ──► data_o
                                                    │                    valid_o
                                                    │                    ready_i ◄── ready_i
                                                    └── bank_N
```

## 1. Multi-bank memory with address-interleaved banking

```verilog
module multi_bank_mem #(
  parameter NUM_BANKS  = 4,
  parameter BANK_W     = 2,      // ceil(log2(NUM_BANKS))
  parameter ADDR_W     = 10,
  parameter DATA_W     = 32
) (
  input  wire                   clk,
  input  wire                   rst,

  // input port (shared by all banks)
  input  wire                   valid_i,
  input  wire [ADDR_W-1:0]      addr_i,
  input  wire [DATA_W-1:0]      data_i,
  input  wire                   wr_i,     // 1=write, 0=read
  output wire                   ready_o,

  // output port (arbitrated from all banks)
  output wire                   valid_o,
  output wire [DATA_W-1:0]      data_o,
  input  wire                   ready_i
);

  // bank select: use LSBs for interleaving (consecutive addresses → different banks)
  wire [BANK_W-1:0] bank_sel;
  assign bank_sel = addr_i[BANK_W-1:0];

  // per-bank ready signals
  wire [NUM_BANKS-1:0] bank_ready;
  wire [NUM_BANKS-1:0] bank_valid;
  wire [DATA_W-1:0]    bank_data [0:NUM_BANKS-1];

  // input ready: the selected bank is ready
  assign ready_o = bank_ready[bank_sel];

  // --- per-bank memory instances ---
  genvar b;
  generate
    for (b = 0; b < NUM_BANKS; b = b + 1) begin : g_bank

      // per-bank valid: asserted when input targets this bank
      wire bank_valid_in;
      assign bank_valid_in = valid_i && (bank_sel == b);

      bank_mem #(
        .ADDR_W(ADDR_W - BANK_W),  // lower address bits within bank
        .DATA_W(DATA_W)
      ) u_bank (
        .clk     (clk),
        .rst     (rst),
        .valid_i (bank_valid_in),
        .addr_i  (addr_i[ADDR_W-1:BANK_W]),
        .data_i  (data_i),
        .wr_i    (wr_i),
        .ready_o (bank_ready[b]),
        .valid_o (bank_valid[b]),
        .data_o  (bank_data[b]),
        .ready_i (1'b1)  // bank output always ready (arbiter provides backpressure)
      );
    end
  endgenerate

  // --- output arbiter: select from ready banks ---
  wire [NUM_BANKS-1:0] arb_grant;
  wire                 arb_valid;

  rr_arbiter #(
    .NUM_INPUTS(NUM_BANKS)
  ) u_arb (
    .clk      (clk),
    .rst      (rst),
    .valid_i  (bank_valid),
    .data_i   (bank_data),   // packed: {bank_data[3], bank_data[2], ...}
    .ready_o  (),             // per-bank ready handled at input side
    .valid_o  (arb_valid),
    .data_o   (data_o),
    .ready_i  (ready_i),
    .grant_o  (arb_grant)
  );

  assign valid_o = arb_valid;

endmodule
```

Pattern rule:
- Address LSBs select the bank — sequential addresses hit different banks (interleaving).
- Each bank is an independent memory with its own valid/ready handshake.
- Input `ready_o` is the selected bank's ready — other banks are unaffected.
- The output arbiter selects from banks that have valid data.
- Bank conflict: if two consecutive inputs target the same bank, the second stalls until the first completes.

## 2. Bank memory instance (single-port synchronous RAM)

The per-bank memory used in the multi-bank controller:

```verilog
module bank_mem #(
  parameter ADDR_W = 8,
  parameter DATA_W = 32,
  parameter DEPTH  = 256
) (
  input  wire                clk,
  input  wire                rst,

  input  wire                valid_i,
  input  wire [ADDR_W-1:0]   addr_i,
  input  wire [DATA_W-1:0]   data_i,
  input  wire                wr_i,
  output wire                ready_o,

  output wire                valid_o,
  output wire [DATA_W-1:0]   data_o,
  input  wire                ready_i
);

  reg [DATA_W-1:0] mem [0:DEPTH-1];

  wire accept_input;
  reg  busy;    // 1-cycle busy flag for read latency

  assign accept_input = valid_i && ready_o;
  assign ready_o      = !busy;

  always @(posedge clk) begin
    if (rst) begin
      busy <= 1'b0;
    end else if (accept_input) begin
      if (wr_i)
        mem[addr_i] <= data_i;
      busy <= 1'b1;  // one cycle for read data
    end else begin
      busy <= 1'b0;
    end
  end

  // read data: registered (one cycle after accept)
  reg [DATA_W-1:0] rdata_r;
  reg              valid_r;

  always @(posedge clk) begin
    if (rst) begin
      valid_r <= 1'b0;
    end else if (accept_input && !wr_i) begin
      rdata_r <= mem[addr_i];
      valid_r <= 1'b1;
    end else if (ready_i) begin
      valid_r <= 1'b0;
    end
  end

  assign valid_o = valid_r;
  assign data_o  = rdata_r;

endmodule
```

### Contract per bank

| Decision | Value |
|----------|-------|
| Write latency | 0 cycles (data written on accept_input cycle) |
| Read latency | 1 cycle (data available next cycle after accept_input) |
| Throughput | 1 access per 2 cycles (1 busy cycle between accepts) |
| Simultaneous read/write | Not applicable (single port) |
| Reset | `busy` cleared, `valid_r` deasserted |

## 3. Bank conflict detection and stall

The conflict detector identifies when consecutive accesses target the same bank:

```verilog
reg [BANK_W-1:0] last_bank;
reg              last_bank_valid;  // previous access still in flight

always @(posedge clk) begin
  if (rst) begin
    last_bank_valid <= 1'b0;
  end else if (accept_input) begin
    last_bank       <= bank_sel;
    last_bank_valid <= 1'b1;
  end else if (bank_valid[last_bank] && bank_ready[last_bank]) begin
    // previous access completed → clear tracking
    last_bank_valid <= 1'b0;
  end
end

// Conflict: current access targets bank still busy from previous access
wire conflict;
assign conflict = valid_i && last_bank_valid && (bank_sel == last_bank);

// Override ready when conflict detected
assign ready_o_conflict = ready_o_raw && !conflict;
```

Pattern rule:
- Conflict detection prevents two accesses to the same bank from overlapping.
- Conflict stall is per-bank: other banks are unaffected.
- For pipelined designs, track multiple in-flight accesses per bank with a counter.

## Common bugs

| Bug | Symptom | Fix |
|-----|---------|-----|
| Bank address bits wrong | All accesses hit bank 0 | Verify `bank_sel` uses correct address slice |
| Output arbiter starvation | One bank dominates output | Check arbiter policy (round-robin vs fixed priority) |
| Conflict detector stale | False conflicts after bank completes | Clear `last_bank_valid` when bank output accepted |
| Ready gating incomplete | Input ready_o doesn't check bank conflict | Combine bank_ready + conflict in ready_o |

## Synthesis notes
- Per-bank memories: each infers a separate BRAM block (or distributed RAM for small depths).
- Output arbiter: multiplexer tree — M:1 mux at output, ~DATA_W × log2(NUM_BANKS) LUTs.
- Bank decode: combinational, negligible area.
- Total BRAM count = NUM_BANKS × 1 (if each bank is large enough to infer BRAM).

## What to capture from multi-bank examples
- Address interleaving: LSBs select bank → sequential addresses span banks
- Each bank is independent: concurrent accesses to different banks proceed in parallel
- Bank conflict: same-bank accesses serialize → worst-case throughput = 1/N
- Output arbiter: selects among ready banks; round-robin for fairness
- Per-bank timing: read latency, write latency, and busy cycle defined per bank
