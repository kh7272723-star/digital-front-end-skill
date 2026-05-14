# CRC pipeline patterns

## Source authority

This file distills patterns from:
- **IEEE 802.3** clause 3.2.8 — Frame Check Sequence (CRC-32 polynomial: `x³² + x²⁶ + x²³ + x²² + x¹⁶ + x¹² + x¹¹ + x¹⁰ + x⁸ + x⁷ + x⁵ + x⁴ + x² + x + 1`)
- **alexforencich `verilog-ethernet`** (`github.com/alexforencich/verilog-ethernet`, MIT) — parametrizable parallel CRC using precomputed XOR-reduction matrix, verified against Xilinx/Intel/Mellanox/Arista commercial implementations
- **Xilinx XAPP209** — "IEEE 802.3 Cyclic Redundancy Check" with Perl generator for parallel CRC
- **Easics CRC Tool** (`easics.com/webtools/crctool`) — canonical online generator for parallel CRC equations

## When to use a CRC pipeline

Use when:
- Data integrity must be verified in hardware (Ethernet FCS, PCIe LCRC, storage, wireless).
- The data path is wider than 1 bit — parallel CRC is required for throughput.
- The CRC polynomial is a standard one (CRC-32, CRC-16-CCITT, CRC-8-ATM).

Do NOT use when:
- Error correction is needed — use ECC (`references/ecc-examples.md`).
- The polynomial is non-standard and unverified — a wrong CRC polynomial silently passes corrupt data.

## Concept

CRC computation can be expressed as: `crc_next = (crc_current << N) XOR data XOR polynomial_reduction(crc_current, N)`

For a parallel implementation processing N bits per cycle:
1. Compute the LFSR shift contribution of the current CRC value shifted by N positions.
2. XOR in the new N data bits, each at its corresponding tap position.
3. Reduce the combined effect through the polynomial to produce the new CRC.

This produces a purely combinational XOR tree — one set of XOR operations per output CRC bit. For CRC-32 with 8-bit input: ~32 XOR equations, each with ~10-15 inputs.

## 1. Parameterized parallel CRC (LFSR iteration method)

Uses a Verilog `for` loop to iterate the LFSR N times per cycle. Synthesis unrolls this to a combinational XOR tree. This is the simplest method for any polynomial/data-width combination.

```verilog
module crc_parallel #(
  parameter DATA_W   = 8,
  parameter CRC_W    = 32,
  parameter [CRC_W-1:0] POLYNOMIAL = 32'h04C11DB7,  // CRC-32 Ethernet
  parameter [CRC_W-1:0] INIT_VALUE = {CRC_W{1'b1}},  // all-ones
  parameter [CRC_W-1:0] XOR_OUT    = {CRC_W{1'b1}},  // complement output
  parameter REFLECT_IN  = 1,   // bit-reverse each input byte
  parameter REFLECT_OUT = 1    // bit-reverse CRC before final XOR
) (
  input  wire                clk,
  input  wire                rst,

  input  wire                valid_i,
  input  wire [DATA_W-1:0]   data_i,
  input  wire                flush_i,  // finalize CRC for this frame

  output wire [CRC_W-1:0]    crc_o,
  output wire                crc_valid_o
);

  // bit-reverse function
  function [DATA_W-1:0] reflect_data;
    input [DATA_W-1:0] d;
    integer j;
    begin
      reflect_data = {DATA_W{1'b0}};
      for (j = 0; j < DATA_W; j = j + 1)
        reflect_data[j] = d[DATA_W-1-j];
    end
  endfunction

  function [CRC_W-1:0] reflect_crc;
    input [CRC_W-1:0] c;
    integer j;
    begin
      reflect_crc = {CRC_W{1'b0}};
      for (j = 0; j < CRC_W; j = j + 1)
        reflect_crc[j] = c[CRC_W-1-j];
    end
  endfunction

  wire [DATA_W-1:0] data_processed;
  assign data_processed = REFLECT_IN ? reflect_data(data_i) : data_i;

  reg [CRC_W-1:0] crc_r;

  always @(posedge clk) begin
    if (rst) begin
      crc_r <= INIT_VALUE;
    end else if (flush_i) begin
      crc_r <= INIT_VALUE;
    end else if (valid_i) begin
      // parallel LFSR step: shift N bits, XOR in data
      integer bit_idx;
      reg [CRC_W-1:0] crc_next;
      crc_next = crc_r;
      for (bit_idx = 0; bit_idx < DATA_W; bit_idx = bit_idx + 1) begin
        // shift left by 1, feed MSB through polynomial
        crc_next = {crc_next[CRC_W-2:0], 1'b0}
                 ^ ({CRC_W{data_processed[DATA_W-1-bit_idx]}} & POLYNOMIAL);
        // also feed the feedback bit
        if (crc_next[CRC_W-1])
          crc_next = crc_next ^ POLYNOMIAL;
      end
      crc_r <= crc_next;
    end
  end

  wire [CRC_W-1:0] crc_raw;
  assign crc_raw = REFLECT_OUT ? reflect_crc(crc_r) : crc_r;

  assign crc_o       = crc_raw ^ XOR_OUT;
  assign crc_valid_o = 1'b1;  // CRC is always valid (combinational from registered state)

endmodule
```

### Synthesis notes
- The `for` loop unrolls to `DATA_W` levels of XOR logic per output CRC bit.
- For CRC-32 with 8-bit input: ~32 XOR equations, ~5-6 LUT levels. Good to ~300 MHz on modern FPGA.
- For CRC-32 with 64-bit input: ~32 XOR equations, ~8-10 LUT levels. Pipeline at >200 MHz.

## 2. CRC with ready/valid data path (complete module)

```verilog
module crc_pipeline #(
  parameter DATA_W = 8,
  parameter CRC_W  = 32
) (
  input  wire                clk,
  input  wire                rst,

  input  wire                valid_i,
  input  wire [DATA_W-1:0]   data_i,
  input  wire                last_i,   // end of frame
  output wire                ready_o,

  output wire                valid_o,
  output wire [CRC_W-1:0]    crc_o,
  input  wire                ready_i
);

  wire crc_ready;
  assign crc_ready = !valid_o || ready_i;

  wire accept_input = valid_i && crc_ready;

  wire crc_valid;
  wire [CRC_W-1:0] crc_val;

  crc_parallel #(
    .DATA_W(DATA_W),
    .CRC_W(CRC_W)
  ) u_crc (
    .clk         (clk),
    .rst         (rst),
    .valid_i     (accept_input),
    .data_i      (data_i),
    .flush_i     (last_i && accept_input),
    .crc_o       (crc_val),
    .crc_valid_o (crc_valid)
  );

  // register final CRC on last beat
  reg                valid_r;
  reg  [CRC_W-1:0]   crc_r;

  always @(posedge clk) begin
    if (rst) begin
      valid_r <= 1'b0;
    end else if (last_i && accept_input) begin
      crc_r   <= crc_val;
      valid_r <= 1'b1;
    end else if (ready_i) begin
      valid_r <= 1'b0;
    end
  end

  assign valid_o = valid_r;
  assign crc_o   = crc_r;
  assign ready_o = crc_ready;

endmodule
```

### Contract

| Decision | Value |
|----------|-------|
| CRC polynomial | IEEE 802.3 CRC-32 (0x04C11DB7) |
| Init value | 0xFFFFFFFF |
| Final XOR | 0xFFFFFFFF |
| Input reflection | Byte-wise bit reversal |
| Output reflection | CRC register bit reversal |
| Throughput | 1 byte per cycle (combinational CRC, registered output) |
| Frame boundary | `last_i` triggers CRC capture and reset for next frame |
| Backpressure | `ready_o` deasserts when output CRC not yet consumed |

## 3. CRC-16-CCITT (for SDLC/HDLC, SPI flash, BLE)

For reference, the standard CRC-16-CCITT polynomial:

```verilog
// Polynomial: x^16 + x^12 + x^5 + 1  (0x1021)
// Init: 0xFFFF, no XOR out, no reflection for CCITT-FALSE variant
crc_parallel #(
  .DATA_W    (8),
  .CRC_W     (16),
  .POLYNOMIAL(16'h1021),
  .INIT_VALUE(16'hFFFF),
  .XOR_OUT   (16'h0000),
  .REFLECT_IN(0),
  .REFLECT_OUT(0)
) u_crc16 (...);
```

## Common bugs

| Bug | Symptom | Fix |
|-----|---------|-----|
| Wrong reflect setting | CRC matches no known implementation | Match reflect_in/out to protocol spec. Ethernet: both 1. CRC-16-CCITT-FALSE: both 0. |
| Init not all-ones | First bytes of every frame produce wrong CRC | Use INIT_VALUE per protocol spec |
| CRC sampled before last byte processed | CRC-32 off by one byte | `last_i` must gate CRC capture AFTER the last byte is processed |
| For-loop synthesized as sequential | Iteration count too small for data width | Ensure all DATA_W iterations are modeled in the for-loop |

## Verification notes

Directed tests:
1. Known vector: Ethernet CRC-32 of 8'h00 → verify against IEEE 802.3 example.
2. Multi-byte vector: CRC-32 of "123456789" → 0xCBF43926 (standard test vector).
3. Back-to-back frames: verify CRC resets on `last_i` and new frame starts clean.
4. Backpressure: `ready_i=0` holds CRC output; next frame blocked until consumed.

## What to capture from CRC examples
- Parallel CRC = XOR tree: the for-loop unrolls to combinational logic
- Reflection, init value, and final XOR are protocol-specific — get them right
- Frame boundary (`last_i`) triggers capture and reset
- For CRC-32 with >8-bit input: use higher DATA_W and accept deeper XOR levels, or pipeline
