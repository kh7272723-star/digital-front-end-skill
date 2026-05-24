# Assertion example patterns

## Source policy
Keep assertion examples simple and directly tied to the design contract.
Use them to protect protocol behavior, state integrity, and reset assumptions.

## 1. Data stable while waiting

SystemVerilog assertion form:

```systemverilog
property p_data_stable_while_waiting;
  @(posedge clk_i) disable iff (rst_i)
    valid_q && !ready_i |=> valid_q && $stable(data_q);
endproperty

assert property (p_data_stable_while_waiting);
```

Pattern rule:
- protect data-hold behavior during backpressure
- check the exact condition that should freeze the payload
- include sideband fields in the same check when the protocol protects them

## 2. No overflow / no underflow idea

```systemverilog
assert property (@(posedge clk_i) disable iff (rst_i) !(wr_en_i && full_o));
assert property (@(posedge clk_i) disable iff (rst_i) !(rd_en_i && empty_o));
```

Pattern rule:
- guard the storage contract
- make illegal protocol events visible early
- if the contract says illegal attempts are ignored rather than forbidden, turn these into scoreboard checks instead of assertions

## 3. Reset contract

```systemverilog
assert property (@(posedge clk_i) rst_i |-> state_q == IDLE);
```

Pattern rule:
- assert the intended reset state explicitly
- verify visible outputs if the contract requires it

## 4. FSM legal state check

```systemverilog
assert property (@(posedge clk_i) disable iff (rst_i)
  state_q inside {IDLE, BUSY, DONE});
```

Pattern rule:
- enumerate allowed states in the verification layer
- fail loudly on unknown encodings

## What to capture from assertion examples
- the protected contract
- the triggering condition
- the expected behavior when the contract is broken
- whether the check belongs in testbench, RTL, or both

## Procedural fallback

If the user asks for plain Verilog only, use a small monitor register instead of SVA:

```verilog
reg        prev_waiting;
reg [7:0]  prev_data;

always @(posedge clk_i) begin
  if (rst_i) begin
    prev_waiting <= 1'b0;
    prev_data    <= 8'd0;
  end else begin
    if (prev_waiting && data_q !== prev_data)
      $display("Data changed while waiting at %0t", $time);
    prev_waiting <= valid_q && !ready_i;
    prev_data    <= data_q;
  end
end
```
