# Credit-based flow control patterns

## Source authority

This file distills patterns from **PULP `common_cells` `credit_counter`** (v1.37.0, July 2024, `github.com/pulp-platform/common_cells`) and the **ARM AMBA AXI outstanding transaction model** (ARM IHI0022). The RTL here is adapted to the skill's plain-Verilog convention and ready/valid naming standard.

## When to use credit-based flow control

Use when:
- The round-trip backpressure latency exceeds the pipeline depth — simple ready/valid would leave the pipe empty waiting for `ready` to propagate back.
- The sender needs to know the exact number of free buffer slots downstream (e.g., multi-cycle link, NoC router, DDR command queue).
- The design needs to bound outstanding transactions to a known limit.

Do NOT use when:
- The downstream can respond with `ready` in the same cycle — ready/valid is simpler and sufficient.
- The credit return path has unbounded latency and no flow control of its own — credit exhaustion is a deadlock if credits can be lost.

## Naming convention

| Signal | Direction | Meaning |
|--------|-----------|---------|
| `valid_i`, `data_i` | Input | Upstream presents data |
| `ready_o` | Output | This block can accept (credits_avail > 0) |
| `credit_return_i` | Input | Downstream returns N consumed credits (sideband) |
| `credit_return_valid_i` | Input | credit_return_i is valid this cycle |
| `credits_avail_o` | Output | Current available credits (optional, for debug) |

Use `accept_input = valid_i && ready_o` exactly as in the ready/valid convention.
`credit_return_valid_i && ready_o` returns credits in the same cycle as a possible accept.

## 1. Credit counter base module

The core building block: an up/down counter that tracks available credits.
Initialized to a parameterized maximum. Decremented on send. Incremented on credit return.

```verilog
module credit_counter #(
  parameter MAX_CREDITS = 16,
  parameter CREDIT_W    = 5   // ceil(log2(MAX_CREDITS+1))
) (
  input  wire                clk,
  input  wire                rst,

  input  wire                credit_consume,    // one credit consumed this cycle
  input  wire                credit_return,     // one credit returned this cycle
  input  wire [CREDIT_W-1:0] credit_return_cnt, // bulk return count (0 = use credit_return single-bit)

  output wire                credits_avail,     // at least 1 credit available
  output wire [CREDIT_W-1:0] credits_count      // current available credits
);

  reg [CREDIT_W-1:0] credits;

  wire credit_return_any = credit_return || (credit_return_cnt > 0);

  always @(posedge clk) begin
    if (rst) begin
      credits <= MAX_CREDITS[CREDIT_W-1:0];
    end else begin
      case ({credit_consume, credit_return_any})
        2'b10: credits <= credits - {{CREDIT_W-1{1'b0}}, 1'b1};
        2'b01: credits <= credits + credit_return_cnt + {{CREDIT_W-1{1'b0}}, credit_return};
        2'b11: credits <= credits + credit_return_cnt + {{CREDIT_W-1{1'b0}}, credit_return}
                          - {{CREDIT_W-1{1'b0}}, 1'b1};
        default: credits <= credits;
      endcase
    end
  end

  assign credits_avail = (credits > 0);
  assign credits_count = credits;

endmodule
```

Pattern rule:
- `credit_consume` and `credit_return_any` may be asserted simultaneously.
- Credits are never negative (consume is gated by `credits_avail` externally).
- The counter does NOT saturate — overflow protection is the caller's responsibility.
- Use `credit_return_cnt` for bulk returns (e.g., a FIFO draining N entries at once).

## 2. Credit-based ready/valid register slice

Wraps `credit_counter` with a standard ready/valid data path. This is the most common usage pattern.

```verilog
module credit_slice #(
  parameter WIDTH        = 8,
  parameter MAX_CREDITS  = 16,
  parameter CREDIT_W     = 5
) (
  input  wire                clk,
  input  wire                rst,

  input  wire                valid_i,
  input  wire [WIDTH-1:0]    data_i,
  output wire                ready_o,

  output wire                valid_o,
  output wire [WIDTH-1:0]    data_o,
  input  wire                ready_i,

  // credit return from downstream
  input  wire                credit_return_i,
  input  wire [CREDIT_W-1:0] credit_return_cnt_i,

  output wire [CREDIT_W-1:0] credits_avail_o
);

  wire credit_avail;
  wire accept_input;
  wire accept_output;

  assign accept_output = valid_o && ready_i;
  assign accept_input  = valid_i && ready_o;
  assign ready_o       = credit_avail;   // gate: only accept when credits remain

  credit_counter #(
    .MAX_CREDITS(MAX_CREDITS),
    .CREDIT_W(CREDIT_W)
  ) u_credits (
    .clk              (clk),
    .rst              (rst),
    .credit_consume   (accept_input),
    .credit_return    (credit_return_i),
    .credit_return_cnt(credit_return_cnt_i),
    .credits_avail    (credit_avail),
    .credits_count    (credits_avail_o)
  );

  // data path — standard register slice
  reg                 valid_r;
  reg  [WIDTH-1:0]    data_r;

  always @(posedge clk) begin
    if (rst) begin
      valid_r <= 1'b0;
    end else if (ready_o) begin
      valid_r <= valid_i;
      if (accept_input)
        data_r <= data_i;
    end
  end

  assign valid_o = valid_r;
  assign data_o  = data_r;

endmodule
```

### Contract encoded in this slice

| Decision | Value | Why |
|----------|-------|-----|
| Credit initialization | `MAX_CREDITS` after reset | Assumes downstream buffer starts empty |
| Credit consumption | 1 per `accept_input` | One item consumes one downstream slot |
| Credit return | `credit_return_i` or `credit_return_cnt_i` | Supports single and bulk return |
| Simultaneous consume + return | Both applied same cycle (credits += return - 1) | No priority — arithmetic handles it |
| Ready gate | `ready_o = credit_avail` only | No additional stall; credits IS the backpressure |
| Data holding | Standard: hold while `valid_o && !ready_i` | Inherited from register slice pattern |

### Verification notes

Directed tests:
1. Reset → `credits_avail_o == MAX_CREDITS`, `valid_o == 0`, `ready_o == 1`.
2. Normal transfer: send 1, downstream consumes 1 → credits decrement then return.
3. Credit exhaustion: send MAX_CREDITS items → `ready_o` deasserts, further `valid_i` blocked.
4. Credit return resumes flow: downstream returns 1 credit → `ready_o` reasserts, next item accepted.
5. Simultaneous consume+return: `accept_input && credit_return_i` → credits unchanged.
6. Bulk credit return: `credit_return_cnt_i = 4` → credits += 4 in one cycle.

Assertions:
```systemverilog
assert property (@(posedge clk) disable iff (rst)
  credits_avail_o <= MAX_CREDITS);
assert property (@(posedge clk) disable iff (rst)
  !accept_input || credits_avail_o > 0);
assert property (@(posedge clk) disable iff (rst)
  credit_return_i |-> credits_avail_o < MAX_CREDITS);
```

## 3. Credit return on output consumption (auto-return)

When the credit return comes from the downstream consumer's `accept_output` itself — the consumer implicitly frees a slot each time it accepts:

```verilog
// Connect credit return directly to downstream accept:
wire credit_return_i   = accept_output;   // each downstream consume frees one credit
wire [CREDIT_W-1:0] credit_return_cnt_i = 0;  // single-item auto-return
```

This is the simplest credit loop: the credit slice and its downstream form a closed credit cycle. No separate credit return channel needed.

## 4. Multi-credit initialization for elastic buffers

When the credit slice sits before a FIFO of known depth:

```verilog
// FIFO with DEPTH=8 → MAX_CREDITS = 8+1 = 9 (8 FIFO slots + 1 in-flight slice)
credit_slice #(
  .WIDTH(32),
  .MAX_CREDITS(9),
  .CREDIT_W(4)
) u_slice (...);
```

Credits are returned from the FIFO's read side: each `rd_do` returns one credit.

## What to capture from credit-based examples
- Credit counter as the single source of truth for flow control
- `ready_o` gated by credit availability — not by local storage
- Credit return path must be reliable (no lost credits = no deadlock)
- Simultaneous consume+return handled without priority
- MAX_CREDITS sizing: downstream buffer depth + in-flight pipeline depth
- Credit return scheme: auto-return (implicit) vs sideband channel (explicit)
