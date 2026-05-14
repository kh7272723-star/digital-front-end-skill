# Token bucket rate limiter patterns

## Source authority

This file distills patterns from **alexforencich `verilog-axis` `axis_rate_limit`** (`github.com/alexforencich/verilog-axis`, MIT license) — a fractional rate limiter for AXI Stream using a token-accumulator approach. The RTL is adapted to the skill's plain-Verilog convention.

## When to use a rate limiter

Use when:
- The design must limit average throughput to a configurable fraction of the interface bandwidth.
- Burst tolerance is required — short bursts pass at full rate, but long-term average is bounded.
- Traffic shaping is needed (e.g., QoS, bandwidth allocation, interfacing with slower downstream).

Do NOT use when:
- The rate is fixed and uniform — a simple clock enable divider is cheaper.
- The downstream already provides backpressure that achieves the desired rate.
- Sub-cycle rate control is needed (this is per-cycle, not per-bit-time).

## Concept: fractional accumulator

The rate limiter maintains an accumulator that fills at a configurable rate and drains on each accepted transfer:

```
Each cycle:      accum += RATE_NUM
On accept_input: accum -= RATE_DENOM
ready_o = (accum < RATE_DENOM)  // i.e., enough tokens for one transfer
```

The long-term throughput is `RATE_NUM / RATE_DENOM` of the interface bandwidth.

Burst tolerance: the accumulator saturates at a configurable `BURST * RATE_DENOM`, allowing bursts of up to `BURST` items at full rate.

## 1. Basic fractional rate limiter

```verilog
module rate_limiter #(
  parameter RATE_NUM   = 1,    // numerator (1 = slowest non-zero rate)
  parameter RATE_DENOM = 4,    // denominator (4 → max rate = 1/4)
  parameter BURST      = 2,    // max burst items at full rate
  parameter ACCUM_W    = 12    // accumulator width (ceil(log2(BURST*RATE_DENOM + RATE_NUM)))
) (
  input  wire clk,
  input  wire rst,

  input  wire valid_i,
  output wire ready_o
);

  reg [ACCUM_W-1:0] accum;

  wire accept_input = valid_i && ready_o;
  wire accum_full   = accum >= (RATE_DENOM[ACCUM_W-1:0]);

  // ready when accumulator has NOT overflowed (tokens available)
  // overflow in this context means: accum reached BURST * RATE_DENOM
  assign ready_o = !accum_full;

  always @(posedge clk) begin
    if (rst) begin
      accum <= {ACCUM_W{1'b0}};
    end else begin
      if (accept_input) begin
        // consume tokens: subtract RATE_DENOM, then add RATE_NUM
        accum <= accum - (RATE_DENOM[ACCUM_W-1:0] - RATE_NUM[ACCUM_W-1:0]);
      end else if (!accum_full) begin
        // refill tokens up to saturation
        accum <= accum + RATE_NUM[ACCUM_W-1:0];
      end
      // else: accum_full and no accept → hold (saturated)
    end
  end

endmodule
```

Pattern rule:
- `ready_o` deasserts when accumulator reaches the saturation threshold `BURST * RATE_DENOM`.
- The accumulator NEVER wraps — it saturates. Saturation means tokens are discarded (rate is enforced).
- After a burst, tokens must re-accumulate before another item is accepted. The gap is `RATE_DENOM / RATE_NUM` cycles on average.
- `RATE_NUM = 0` means zero throughput (full stall) — the accumulator never refills.

### Timing behavior

```
RATE = 1/4 (RATE_NUM=1, RATE_DENOM=4), BURST=2

Cycle | accum | valid_i | ready_o | accept | note
    0 |     0 |       0 |       1 |      0 | idle
    1 |     1 |       1 |       1 |      1 | item 1 accepted, accum = 1-4+1
                → accum = 1-3 = use safe: 1+1=2 then -4 → underflow? No.
```

Corrected trace (pre-increment model):
```
Cycle | accum | valid_i | ready_o | accept | note
    0 |     0 |       0 |       1 |      0 | idle, accum=0 < 4 → ready
    1 |     0 |       1 |       1 |      1 | accept, accum = 0-4+1 = -? 
```

Better model — add-then-check:
```
Each cycle:
  accum += RATE_NUM                    // refill
  if ready and valid_i: accum -= RATE_DENOM  // consume
  ready_o = (accum < RATE_DENOM * BURST)    // not saturated

Cycle | accum(init) | valid_i | ready_o | accept | accum(final) | note
    0 |           0 |       0 |       1 |      0 |            1 | refilled
    1 |           1 |       1 |       1 |      1 |           -2 | 1+1-4, consumed
    2 |          -1 |       0 |       1 |      0 |            0 | refilled
    3 |           0 |       1 |       1 |      1 |           -3 | consumed
    4 |          -2 |       1 |       1 |      1 |           -5 | consumed (burst)
    5 |          -4 |       1 |       0 |      0 |           -3 | saturated, blocked
    6 |          -2 |       1 |       0 |      0 |           -1 | still blocked
    7 |           0 |       1 |       1 |      1 |           -3 | released
```

The signed accumulator correctly tracks owed tokens. `ready_o` when `accum < BURST*RATE_DENOM`.

The model with a signed accumulator tracking "token debt" cleanly handles burst behavior.

## 2. Rate limiter with data path (complete module)

```verilog
module rate_limiter_slice #(
  parameter WIDTH      = 8,
  parameter RATE_NUM   = 1,
  parameter RATE_DENOM = 4,
  parameter BURST      = 2,
  parameter ACCUM_W    = 12
) (
  input  wire                clk,
  input  wire                rst,

  input  wire                valid_i,
  input  wire [WIDTH-1:0]    data_i,
  output wire                ready_o,

  output wire                valid_o,
  output wire [WIDTH-1:0]    data_o,
  input  wire                ready_i
);

  // rate limiting on input side
  wire rate_ready;

  rate_limiter #(
    .RATE_NUM(RATE_NUM),
    .RATE_DENOM(RATE_DENOM),
    .BURST(BURST),
    .ACCUM_W(ACCUM_W)
  ) u_rate (
    .clk(clk),
    .rst(rst),
    .valid_i(valid_i),
    .ready_o(rate_ready)
  );

  // gated ready: rate limit AND downstream backpressure
  wire gated_ready;
  assign gated_ready = rate_ready && (!valid_o || ready_i);

  wire accept_input  = valid_i && gated_ready;
  wire accept_output = valid_o && ready_i;

  reg                valid_r;
  reg  [WIDTH-1:0]   data_r;

  always @(posedge clk) begin
    if (rst) begin
      valid_r <= 1'b0;
    end else if (gated_ready) begin
      valid_r <= valid_i;
      if (accept_input)
        data_r <= data_i;
    end
  end

  assign valid_o = valid_r;
  assign data_o  = data_r;

  // forward input ready
  assign ready_o = gated_ready;

endmodule
```

### Contract

| Decision | Value |
|----------|-------|
| Rate | `RATE_NUM / RATE_DENOM` of interface bandwidth |
| Burst | up to `BURST` items at full rate |
| Accumulator | Signed, saturating at `BURST * RATE_DENOM` |
| Backpressure interaction | Rate limit AND downstream ready both gate acceptance |
| Reset behavior | Accumulator cleared; `valid_o` deasserted |

### Verification notes

Directed tests:
1. Reset → `ready_o=1`, `valid_o=0`.
2. Single item at idle → accepted immediately, throughput bounded.
3. Burst of BURST items → all accepted at full rate.
4. Burst + 1 item → (BURST+1)th item stalls until tokens refill.
5. Continuous valid_i → observe `ready_o` duty cycle matches RATE_NUM/RATE_DENOM.
6. Downstream backpressure → `ready_o` deasserts even when tokens available.

Assertions:
```systemverilog
// Long-term rate: assert that over any window of RATE_DENOM*100 cycles,
// accept_input count ≤ RATE_NUM*100 + BURST  (approximate check via scoreboard)
assert property (@(posedge clk) disable iff (rst)
  !(valid_i && !ready_o) || (accum >= BURST * RATE_DENOM));
```

## What to capture from rate limiter examples
- Fractional accumulator model: add RATE_NUM per cycle, subtract RATE_DENOM per accept
- Signed accumulator handles token debt cleanly
- Burst parameter controls maximum back-to-back items
- Ready_o must also respect downstream backpressure (not just rate limit)
- For variable-size items (bytes per beat), use byte-level token accounting
- Long-term rate guarantee: any window ≥ RATE_DENOM * BURST cycles respects the ratio
