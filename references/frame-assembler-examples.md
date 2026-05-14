# Frame / packet assembler and disassembler patterns

## Source authority

This file distills patterns from:
- **alexforencich `verilog-axis` `axis_frame_join`** (`github.com/alexforencich/verilog-axis`, MIT) — frame-aware stream joiner that aligns frame boundaries across multiple input streams
- **Standard packet processing architecture** — found in Ethernet MACs, PCIe transaction layer, HDMI/DP packetizers, and any protocol that segments data into framed units

## When to use a frame assembler

Use when:
- Variable-length frames/packets must be assembled from a continuous data stream.
- Multiple streams must be merged into one, with frame boundaries preserved.
- A continuous stream must be segmented into fixed or bounded-length frames.

Do NOT use when:
- The data stream has no framing (no `last` signal) — use a width converter or FIFO.
- Frames are always exactly the same length — a simple counter may suffice.

## 1. Frame assembler (stream → frames with tlast)

Collects a stream of data beats into a frame buffer and outputs complete frames. Used at protocol boundaries.

```verilog
module frame_assembler #(
  parameter DATA_W = 8,
  parameter MAX_FRAME_LEN = 256,  // max beats per frame
  parameter LEN_W  = 8            // ceil(log2(MAX_FRAME_LEN+1))
) (
  input  wire                clk,
  input  wire                rst,

  // input stream (unframed, or with frame boundary markers)
  input  wire                valid_i,
  input  wire [DATA_W-1:0]   data_i,
  input  wire                sof_i,   // start of frame marker
  input  wire                eof_i,   // end of frame marker
  output wire                ready_o,

  // output stream (framed, with last)
  output wire                valid_o,
  output wire [DATA_W-1:0]   data_o,
  output wire                last_o,  // asserted on final beat of frame
  input  wire                ready_i
);

  // simple implementation: pass-through with eof_i → last_o
  // adds a register stage for frame alignment

  reg                 valid_r;
  reg  [DATA_W-1:0]   data_r;
  reg                 last_r;

  wire accept_input  = valid_i && ready_o;
  wire accept_output = valid_o && ready_i;

  assign ready_o = !valid_r || accept_output;

  always @(posedge clk) begin
    if (rst) begin
      valid_r <= 1'b0;
      last_r  <= 1'b0;
    end else if (accept_input) begin
      valid_r <= 1'b1;
      data_r  <= data_i;
      last_r  <= eof_i;
    end else if (accept_output) begin
      valid_r <= 1'b0;
      last_r  <= 1'b0;
    end
  end

  assign valid_o = valid_r;
  assign data_o  = data_r;
  assign last_o  = last_r;

endmodule
```

Pattern rule:
- `eof_i` is delayed and aligned to the output data beat — `last_o` matches the same output cycle as the final data.
- Frame boundaries are explicit: `sof_i` starts a frame, `eof_i` ends it.
- If `sof_i` and `eof_i` are asserted in the same cycle: single-beat frame.

## 2. Frame disassembler (frames → stream with boundary markers)

Extracts frame boundary markers from a framed stream. Useful for protocol termination or frame inspection.

```verilog
module frame_disassembler #(
  parameter DATA_W = 8
) (
  input  wire                clk,
  input  wire                rst,

  input  wire                valid_i,
  input  wire [DATA_W-1:0]   data_i,
  input  wire                last_i,    // frame boundary from upstream
  output wire                ready_o,

  output wire                valid_o,
  output wire [DATA_W-1:0]   data_o,
  output wire                sof_o,     // detected frame start
  output wire                eof_o,     // detected frame end
  input  wire                ready_i
);

  reg  in_frame;   // track frame state
  reg  valid_r;
  reg  [DATA_W-1:0] data_r;
  reg  sof_r, eof_r;

  wire accept_input  = valid_i && ready_o;
  wire accept_output = valid_o && ready_i;

  assign ready_o = !valid_r || accept_output;

  always @(posedge clk) begin
    if (rst) begin
      in_frame <= 1'b0;
      valid_r  <= 1'b0;
      sof_r    <= 1'b0;
      eof_r    <= 1'b0;
    end else if (accept_input) begin
      valid_r <= 1'b1;
      data_r  <= data_i;

      // sof: first beat after not-in-frame
      sof_r <= !in_frame;

      // eof: last_i marks frame end
      eof_r <= last_i;

      // track frame state
      if (last_i)
        in_frame <= 1'b0;
      else
        in_frame <= 1'b1;
    end else if (accept_output) begin
      valid_r <= 1'b0;
      sof_r   <= 1'b0;
      eof_r   <= 1'b0;
    end
  end

  assign valid_o = valid_r;
  assign data_o  = data_r;
  assign sof_o   = sof_r;
  assign eof_o   = eof_r;

endmodule
```

## 3. Frame-based width adapter (non-integer ratio)

When the width ratio is not an integer multiple, frames can be assembled/disassembled by treating the data as a serial bit/byte stream. This is the general case that `width_adapter` (integer-ratio only) cannot handle.

```verilog
module frame_width_adapter #(
  parameter IN_W   = 24,   // e.g., 3-byte input
  parameter OUT_W  = 32,   // e.g., 4-byte output
  parameter BUF_W   = 96   // LCM(IN_W, OUT_W) — minimum buffer for alignment
) (
  input  wire                clk,
  input  wire                rst,

  input  wire                valid_i,
  input  wire [IN_W-1:0]     data_i,
  input  wire                last_i,
  output wire                ready_o,

  output wire                valid_o,
  output wire [OUT_W-1:0]    data_o,
  output wire                last_o,
  input  wire                ready_i
);

  // Implementation uses a shift-register buffer at byte granularity.
  // Accumulate input bytes, output when OUT_W/8 bytes available.
  // At frame end (last_i), flush remaining bytes with last_o.
  // See width-converter-examples.md for the integer-ratio simple case.

  // (Full implementation omitted for space — this is an architecture reference.
  //  The key principle: treat the data as a byte FIFO, pack/unpack at byte granularity.)

endmodule
```

Pattern rule:
- For non-integer ratios, the adapter must work at the smallest common granularity (typically 1 byte).
- Frame boundaries (`last_i`) must be respected: partial output at frame end is valid.
- Buffer depth must accommodate the worst-case alignment: LCM of input and output widths.

## 4. Multi-stream frame join (merge N framed streams into 1)

Merges multiple framed input streams into a single output, preserving per-stream frame boundaries. Used in packet switches and concentrators.

```verilog
module frame_join #(
  parameter NUM_INPUTS = 4,
  parameter DATA_W     = 8
) (
  input  wire                       clk,
  input  wire                       rst,

  input  wire [NUM_INPUTS-1:0]      valid_i,
  input  wire [NUM_INPUTS*DATA_W-1:0] data_i,
  input  wire [NUM_INPUTS-1:0]      last_i,
  output wire [NUM_INPUTS-1:0]      ready_o,

  output wire                       valid_o,
  output wire [DATA_W-1:0]          data_o,
  output wire                       last_o,
  input  wire                       ready_i
);

  // Round-robin select among inputs that have data.
  // Hold current input until its frame completes (last_i), then switch.
  // This prevents interleaving frames from different sources.

  reg  [$clog2(NUM_INPUTS)-1:0] selected;
  reg                           active;  // currently processing a frame

  always @(posedge clk) begin
    if (rst) begin
      selected <= {$clog2(NUM_INPUTS){1'b0}};
      active   <= 1'b0;
    end else if (!active) begin
      // find next input with valid data
      // (simplified — real implementation uses round-robin search)
      if (valid_i[selected])
        active <= 1'b1;
    end else if (valid_i[selected] && ready_o && last_i[selected]) begin
      active <= 1'b0;
      // advance selected to next input
      selected <= selected + {{$clog2(NUM_INPUTS)-1{1'b0}}, 1'b1};
    end
  end

  assign valid_o = active && valid_i[selected];
  assign data_o  = data_i[selected*DATA_W +: DATA_W];
  assign last_o  = last_i[selected];

  // ready: only to the selected input
  genvar g;
  generate
    for (g = 0; g < NUM_INPUTS; g = g + 1) begin : g_rdy
      assign ready_o[g] = (selected == g) && active && ready_i;
    end
  endgenerate

endmodule
```

### Contract for frame join

| Decision | Value |
|----------|-------|
| Arbitration | Frame-level: once an input is selected, it holds until its frame completes |
| Fairness | Round-robin among inputs with valid data |
| Backpressure | Only the selected input gets `ready_o=1` |
| Deadlock | None: each selected input will complete its frame |

## What to capture from frame assembler examples
- Frame boundaries (`sof_i`/`eof_i` → `last_o`) must be aligned with the data path
- Frame-based merging: hold input until frame completes; no interleaving
- Non-integer width adaptation: requires byte-granularity buffering
- Frame state tracking: `in_frame` register distinguishes frame-start from mid-frame beats
- Always define what happens on single-beat frames (`sof_i && eof_i` in same cycle)
