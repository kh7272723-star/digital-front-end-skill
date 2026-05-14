# Handshake example patterns

## Source policy
Use handshake examples that spell out acceptance, holding, and release in cycle terms.
Avoid examples that hide protocol behavior inside complex logic.

## Naming convention

Use these names in examples unless the user's project has its own convention:

- `valid_i`, `data_i`: upstream producer into this block.
- `ready_o`: this block can accept upstream input.
- `valid_o`, `data_o`: this block drives downstream.
- `ready_i`: downstream can accept this block's output.
- `accept_input = valid_i && ready_o`: this block accepts an input item.
- `accept_output = valid_o && ready_i`: downstream accepts an output item.

For multiple interfaces, add a short interface prefix before the suffix, for example `req_valid_i`, `req_ready_o`, `rsp_valid_o`, and `rsp_ready_i`.

## 1. One-entry ready/valid register slice

```verilog
wire accept_input;
wire accept_output;

assign accept_output = valid_o && ready_i;
assign ready_o       = !valid_o || accept_output;
assign accept_input  = valid_i && ready_o;

always @(posedge clk_i) begin
  if (rst_i) begin
    valid_o <= 1'b0;
  end else if (ready_o) begin
    valid_o <= valid_i;
    if (accept_input)
      data_o <= data_i;
  end
end
```

Pattern rule:
- `ready_o` is high when the slice is empty or the downstream consumes the stored item
- while `valid_o && !ready_i`, the slice holds `valid_o` and `data_o`
- accepted input becomes visible on `valid_o/data_o` after the active clock edge
- use this for a registered one-cycle boundary, not for zero-latency pass-through

## 2. Backpressure propagation

```verilog
always @(*) begin
  ready_o = 1'b0;
  if (!full)
    ready_o = 1'b1;
end
```

Pattern rule:
- backpressure must be derived from the storage or pipeline state
- do not allow hidden combinational loops through ready logic

## 3. Request/ack style control

```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    req_q <= 1'b0;
  end else if (start) begin
    req_q <= 1'b1;
  end else if (ack) begin
    req_q <= 1'b0;
  end
end
```

Pattern rule:
- define the lifetime of the request signal
- define whether ack is level-based or pulse-based
- hold req until the protocol says it is complete

## 4. Skid buffer idea

```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    full_q <= 1'b0;
  end else if (accept_input && !accept_output) begin
    full_q <= 1'b1;
  end else if (!accept_input && accept_output) begin
    full_q <= 1'b0;
  end
end
```

Pattern rule:
- represent buffering state explicitly
- define the pass-through cycle and the stored cycle
- verify no duplicate or lost transactions

## 5. Source holds data under stall

```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    valid_q <= 1'b0;
  end else if (!valid_q || ready_i) begin
    valid_q <= have_data;
    if (have_data)
      data_q <= next_data;
  end
end
```

Pattern rule:
- while `valid_q && !ready_i`, neither `valid_q` nor `data_q` changes
- a stall must not silently advance payload state

## What to capture from handshake examples
- what counts as a completed transfer
- what must be held while waiting
- what propagates backpressure
- what happens if both sides are ready in the same cycle
- whether the protocol is source-synchronous or destination-controlled
