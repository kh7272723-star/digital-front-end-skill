# Utility module patterns

## Source authority

CDC patterns (pulse synchronizer, reset synchronizer, gray code counter) are distilled from:
- Cliff Cummings, "Simulation and Synthesis Techniques for Asynchronous FIFO Design" (SNUG 2002)
- Intel AN 545: "Metastability and CDC Designer"
- `references/cdc-reference.md` — the skill's canonical CDC reference

Sticky status and delay line are standard register-file and shift-register patterns.

## 1. Parameterized gray code counter

Produces Gray-encoded count values. Used for async FIFO pointers and any multi-bit CDC where only one bit changes per increment.

```verilog
module gray_counter #(
  parameter WIDTH = 4
) (
  input  wire             clk,
  input  wire             rst,
  input  wire             en,
  output wire [WIDTH-1:0] gray_o
);

  reg [WIDTH-1:0] bin;

  always @(posedge clk) begin
    if (rst)
      bin <= {WIDTH{1'b0}};
    else if (en)
      bin <= bin + {{WIDTH-1{1'b0}}, 1'b1};
  end

  // Gray encode: gray = bin ^ (bin >> 1)
  assign gray_o = bin ^ {1'b0, bin[WIDTH-1:1]};

endmodule
```

Pattern rule:
- Only one bit changes between consecutive Gray values — this is the property that makes CDC safe.
- The counter wraps naturally at `2^WIDTH`.
- `en` gates counting; without `en`, value holds.
- Binary-to-Gray is combinational (XOR tree); Gray-to-binary (not shown) is sequential XOR accumulation.

## 2. Gray-to-binary converter

```verilog
module gray_to_binary #(
  parameter WIDTH = 4
) (
  input  wire [WIDTH-1:0] gray_i,
  output wire [WIDTH-1:0] bin_o
);

  assign bin_o[WIDTH-1] = gray_i[WIDTH-1];

  genvar i;
  generate
    for (i = WIDTH-2; i >= 0; i = i - 1) begin : g2b
      assign bin_o[i] = bin_o[i+1] ^ gray_i[i];
    end
  endgenerate

endmodule
```

Pattern rule:
- MSB passes through unchanged.
- Each lower bit is the XOR of the next-higher binary bit and the corresponding Gray bit.
- This is combinational — safe to use in the destination clock domain after the Gray pointer has been synchronized.

## 3. Pulse synchronizer (toggle-based CDC)

Safely passes a single-cycle pulse from `clk_src` domain to `clk_dst` domain. Converts pulse→toggle→synchronize→edge-detect.

Based on `cdc-reference.md` §2.

```verilog
module sync_pulse (
  input  wire clk_src,
  input  wire rst_src_n,
  input  wire clk_dst,
  input  wire rst_dst_n,
  input  wire pulse_src,
  output wire pulse_dst
);
  // source domain: pulse → toggle
  reg toggle_src;

  always @(posedge clk_src) begin
    if (!rst_src_n)
      toggle_src <= 1'b0;
    else if (pulse_src)
      toggle_src <= ~toggle_src;
  end

  // 2-ff synchronizer in dst domain
  reg sync1, sync2;

  always @(posedge clk_dst) begin
    if (!rst_dst_n) begin
      sync1 <= 1'b0;
      sync2 <= 1'b0;
    end else begin
      sync1 <= toggle_src;
      sync2 <= sync1;
    end
  end

  // edge detect: any change in sync2 = a pulse in src domain
  reg sync3;

  always @(posedge clk_dst) begin
    if (!rst_dst_n)
      sync3 <= 1'b0;
    else
      sync3 <= sync2;
  end

  assign pulse_dst = sync2 ^ sync3;

endmodule
```

Pattern rule:
- Source pulses must be separated by at least `3 * max(clk_src_period, clk_dst_period)` to avoid missed toggles.
- `pulse_dst` is one `clk_dst` cycle wide.
- Place `ASYNC_REG` attribute on `sync1` and `sync2`.
- If source pulses can arrive faster than dst can consume, data is silently lost — add handshake CDC instead.

## 4. Reset synchronizer

Asynchronously asserted, synchronously deasserted reset. Each clock domain needs its own instance.

Based on `cdc-reference.md` §8.

```verilog
module reset_sync (
  input  wire clk,
  input  wire rst_async,    // async assert, may come from any domain
  output wire rst_sync       // sync deassert in clk domain
);
  reg sync1, sync2;

  always @(posedge clk or posedge rst_async) begin
    if (rst_async) begin
      sync1 <= 1'b1;
      sync2 <= 1'b1;
    end else begin
      sync1 <= 1'b0;
      sync2 <= sync1;
    end
  end

  assign rst_sync = sync2;

endmodule
```

Pattern rule:
- Assertion is asynchronous (combinational path through sensitivity list).
- Deassertion is synchronous (2-ff shift out).
- Every clock domain with logic affected by a global reset needs its own `reset_sync`.
- The synchronized reset from one domain must NOT be used in another domain.
- Place `ASYNC_REG` attribute on `sync1` and `sync2`.

## 5. Sticky status / error accumulator

Captures one-cycle events and holds them until software clears. Common for interrupt status registers, error flags, and event counters.

```verilog
module sticky_status #(
  parameter WIDTH = 8
) (
  input  wire             clk,
  input  wire             rst,

  input  wire [WIDTH-1:0] event_i,     // one-cycle events to capture
  input  wire [WIDTH-1:0] clear_i,     // SW clear mask (1 = clear that bit)

  output wire [WIDTH-1:0] status_o     // sticky status
);

  reg [WIDTH-1:0] status_r;

  always @(posedge clk) begin
    if (rst) begin
      status_r <= {WIDTH{1'b0}};
    end else begin
      status_r <= (status_r | event_i) & ~clear_i;
    end
  end

  assign status_o = status_r;

endmodule
```

Pattern rule:
- `event_i` is edge-sensitive: a single-cycle pulse sets the corresponding `status_o` bit.
- `clear_i` takes priority over `event_i` (write-1-to-clear).
- `status_o` stays asserted until explicitly cleared — it does not self-clear.
- For level-sensitive status (follows input), use a simple register without the OR.

## 6. Programmable delay line

Delays a signal and its valid by a configurable number of cycles. Common in DSP pipelines for data alignment.

```verilog
module delay_line #(
  parameter WIDTH     = 8,
  parameter MAX_DELAY = 16,
  parameter DELAY_W   = 5    // ceil(log2(MAX_DELAY+1))
) (
  input  wire                clk,
  input  wire                rst,

  input  wire                valid_i,
  input  wire [WIDTH-1:0]    data_i,

  input  wire [DELAY_W-1:0]  delay_i,   // configurable delay (1..MAX_DELAY)

  output wire                valid_o,
  output wire [WIDTH-1:0]    data_o
);

  reg                 valid_sr [0:MAX_DELAY-1];
  reg  [WIDTH-1:0]    data_sr  [0:MAX_DELAY-1];

  integer i;

  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < MAX_DELAY; i = i + 1) begin
        valid_sr[i] <= 1'b0;
      end
    end else begin
      valid_sr[0] <= valid_i;
      for (i = 1; i < MAX_DELAY; i = i + 1) begin
        valid_sr[i] <= valid_sr[i-1];
      end
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < MAX_DELAY; i = i + 1) begin
        data_sr[i] <= {WIDTH{1'b0}};
      end
    end else begin
      data_sr[0] <= data_i;
      for (i = 1; i < MAX_DELAY; i = i + 1) begin
        data_sr[i] <= data_sr[i-1];
      end
    end
  end

  assign valid_o = valid_sr[delay_i-1];
  assign data_o  = data_sr[delay_i-1];

endmodule
```

### Synthesis notes
- `for` loops in this module unroll to shift-register chains — intended inference.
- For `MAX_DELAY > 64`, consider SRL (Xilinx) or similar shift-register LUT inference instead of discrete FFs.
- Reset on the shift-register arrays resets ALL entries — for large `MAX_DELAY`, consider resetting only the valid chain and leaving data unreset (gated by valid).

## What to capture from utility examples
- Gray counter: exactly one bit changes per increment; en controls counting
- Pulse sync: minimum inter-pulse spacing for safety; 2-ff chain with edge detect
- Reset sync: async assert + sync deassert per domain; never share across domains
- Sticky status: set on event, clear by SW, clear-takes-priority
- Delay line: shift-register chain with configurable tap; valid/data must stay aligned through all taps
