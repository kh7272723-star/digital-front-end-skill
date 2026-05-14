# Data width converter patterns (upsizer / downsizer)

## Source authority

This file distills patterns from:
- **alexforencich `verilog-axis` `axis_adapter`** (`github.com/alexforencich/verilog-axis`, MIT) — parametrizable AXI Stream bus width adapter with integer-multiple ratio constraint
- **PULP `common_cells` stream_mux / stream_demux** (`github.com/pulp-platform/common_cells`) — ready/valid multiplexer and demultiplexer for composing width converters

## When to use a width converter

Use when:
- Two modules have different data bus widths but the same per-word (lane) width. Example: 8-bit peripheral → 64-bit internal pipeline.
- The ratio between input and output widths is an integer multiple. Example: 8→32 (×4 upsizer) or 64→16 (÷4 downsizer).

Do NOT use when:
- The per-word width differs between sides (e.g., 16-bit words → 32-bit words). That requires a different adapter class.
- The ratio is non-integer (e.g., 3 words → 2 words). Needs a frame-based assembler (`references/frame-assembler-examples.md`).

## 1. Upsizer (narrow input → wide output)

Accumulates multiple narrow beats into one wide output beat. Example: 8-bit input × 4 beats → 32-bit output.

```verilog
module upsizer #(
  parameter IN_W  = 8,
  parameter OUT_W = 32,
  parameter RATIO = 4    // OUT_W / IN_W (must be integer)
) (
  input  wire                clk,
  input  wire                rst,

  input  wire                valid_i,
  input  wire [IN_W-1:0]     data_i,
  output wire                ready_o,

  output wire                valid_o,
  output wire [OUT_W-1:0]    data_o,
  input  wire                ready_i
);

  reg  [$clog2(RATIO)-1:0] beat_cnt;  // 0..RATIO-1
  reg  [OUT_W-1:0]          data_r;

  wire last_beat = (beat_cnt == RATIO-1);
  wire accept_input  = valid_i && ready_o;
  wire accept_output = valid_o && ready_i;

  // ready: accept narrow beats until buffer full
  assign ready_o = !valid_o || accept_output;

  // valid: asserted when RATIO beats accumulated
  assign valid_o = (beat_cnt == RATIO-1);

  always @(posedge clk) begin
    if (rst) begin
      beat_cnt <= {$clog2(RATIO){1'b0}};
      data_r   <= {OUT_W{1'b0}};
    end else begin
      if (accept_input) begin
        // shift data into the wide register
        data_r[beat_cnt*IN_W +: IN_W] <= data_i;
        if (last_beat) begin
          beat_cnt <= {$clog2(RATIO){1'b0}};
        end else begin
          beat_cnt <= beat_cnt + {{$clog2(RATIO)-1{1'b0}}, 1'b1};
        end
      end else if (accept_output) begin
        beat_cnt <= {$clog2(RATIO){1'b0}};
      end
    end
  end

  assign data_o = data_r;

  // synthesis: $clog2 may not be supported in plain Verilog
  // Use parameter or explicit width: `localparam CNT_W = 2;` for RATIO=4

endmodule
```

Pattern rule:
- Narrow beats accumulate into `data_r` at offset `beat_cnt * IN_W`.
- `valid_o` asserted when `beat_cnt == RATIO-1` (all beats collected).
- `ready_o` low while `valid_o` is pending and unread — backpressures upstream.
- On `accept_output`, counter resets and new accumulation begins.

### Execution trace (8→32, RATIO=4)

```
Cycle | valid_i | data_i | ready_o | beat_cnt | valid_o | accept_output | note
    0 |       0 |      - |       1 |        0 |       0 |             0 | idle
    1 |       1 |   0xA0 |       1 |        0 |       0 |             0 | beat 0 captured
    2 |       1 |   0xA1 |       1 |        1 |       0 |             0 | beat 1
    3 |       1 |   0xA2 |       1 |        2 |       0 |             0 | beat 2
    4 |       1 |   0xA3 |       0 |        3 |       1 |             0 | beat 3 (last), valid_o=1, ready_o=0
    5 |       0 |      - |       0 |        3 |       1 |             1 | output consumed, reset
    6 |       1 |   0xB0 |       1 |        0 |       0 |             0 | next frame beat 0
```

## 2. Downsizer (wide input → narrow output)

Unpacks one wide input beat into multiple narrow output beats.

```verilog
module downsizer #(
  parameter IN_W  = 64,
  parameter OUT_W = 16,
  parameter RATIO = 4    // IN_W / OUT_W
) (
  input  wire                clk,
  input  wire                rst,

  input  wire                valid_i,
  input  wire [IN_W-1:0]     data_i,
  output wire                ready_o,

  output wire                valid_o,
  output wire [OUT_W-1:0]    data_o,
  input  wire                ready_i
);

  reg  [$clog2(RATIO)-1:0] beat_cnt;
  reg  [IN_W-1:0]           data_r;

  wire accept_input  = valid_i && ready_o;
  wire accept_output = valid_o && ready_i;

  wire transfer_output = valid_o && ready_i;

  // ready: accept new wide word when buffer not holding data
  assign ready_o = !valid_o || (beat_cnt == RATIO-1 && accept_output);

  // valid: asserted while beats remain to be output
  assign valid_o = (valid_i && ready_o) || (beat_cnt > 0);

  always @(posedge clk) begin
    if (rst) begin
      beat_cnt <= {$clog2(RATIO){1'b0}};
      data_r   <= {IN_W{1'b0}};
    end else begin
      if (accept_input) begin
        data_r   <= data_i;
        beat_cnt <= RATIO[$clog2(RATIO)-1:0] - {{$clog2(RATIO)-1{1'b0}}, 1'b1};  // RATIO-1
      end else if (accept_output) begin
        if (beat_cnt == 1)
          beat_cnt <= {$clog2(RATIO){1'b0}};
        else
          beat_cnt <= beat_cnt - {{$clog2(RATIO)-1{1'b0}}, 1'b1};
      end
    end
  end

  // output the current narrow slice from the wide register
  wire [OUT_W-1:0] current_slice;
  assign current_slice = data_r[(beat_cnt) * OUT_W +: OUT_W];  // high-to-low or low-to-high per contract

  assign data_o = current_slice;

endmodule
```

Pattern rule:
- Wide input captured in `data_r`.
- Narrow slices output one at a time: `data_r[beat_cnt*OUT_W +: OUT_W]`.
- `ready_o` low while still outputting narrow beats from previous wide word.
- On last narrow beat, `ready_o` reasserts to accept next wide word.

## 3. Combined upsizer + downsizer (generic width adapter)

For a full width adapter that handles both directions, parameterize by input/output widths:

```verilog
module width_adapter #(
  parameter IN_W  = 8,
  parameter OUT_W = 32
) (
  input  wire                clk,
  input  wire                rst,
  input  wire                valid_i,
  input  wire [IN_W-1:0]     data_i,
  output wire                ready_o,
  output wire                valid_o,
  output wire [OUT_W-1:0]    data_o,
  input  wire                ready_i
);

  generate
    if (OUT_W > IN_W) begin : g_upsize
      upsizer #(.IN_W(IN_W), .OUT_W(OUT_W), .RATIO(OUT_W/IN_W))
        u_conv (.clk, .rst, .valid_i, .data_i, .ready_o,
                .valid_o, .data_o, .ready_i);
    end else if (OUT_W < IN_W) begin : g_downsize
      downsizer #(.IN_W(IN_W), .OUT_W(OUT_W), .RATIO(IN_W/OUT_W))
        u_conv (.clk, .rst, .valid_i, .data_i, .ready_o,
                .valid_o, .data_o, .ready_i);
    end else begin : g_pass
      assign valid_o = valid_i;
      assign data_o  = data_i;
      assign ready_o = ready_i;
    end
  endgenerate

endmodule
```

### Contract

| Decision | Value |
|----------|-------|
| Ratio constraint | OUT_W / IN_W must be integer OR IN_W / OUT_W must be integer |
| Per-word width | Same on both sides |
| Upsizer latency | RATIO-1 cycles from first beat to `valid_o` |
| Downsizer latency | 1 cycle to capture, then RATIO-1 cycles to output remaining beats |
| Backpressure | Upsizer: backpressures during accumulation. Downsizer: backpressures during unpacking |
| Throughput (upsizer) | 1 wide word per RATIO cycles |
| Throughput (downsizer) | 1 narrow word per cycle after first cycle |

## Common bugs

| Bug | Symptom | Fix |
|-----|---------|-----|
| Counter off-by-one | Last beat duplicated or missing | Check that `beat_cnt` wraps at exactly RATIO for upsizer, 0 for downsizer |
| ready_o deasserted too early | Deadlock | Upsizer: `ready_o = !valid_o || accept_output`. Downsizer: check condition allows next input while outputting last beat |
| Slice ordering reversed | Output MSB/LSB wrong per protocol | Define whether `beat_cnt=0` is LSB or MSB slice. LSB-first is common. |

## What to capture from width converter examples
- Integer-multiple ratio constraint: both sides must share the same per-word width
- Upsizer: accumulate narrow beats into wide register; valid when all beats present
- Downsizer: unpack wide word into narrow slices; count down beats
- Backpressure must hold state through both accumulation and unpacking phases
- For frame-based protocols: propagate `last_i` sideband alongside data
