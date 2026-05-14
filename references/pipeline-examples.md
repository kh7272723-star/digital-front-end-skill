# Pipeline example patterns

## Source policy
Use pipeline examples that show latency, stall, and alignment clearly.
Prefer plain Verilog register stages with visible control flow.
Use `cycle-trace-guidelines.md` to show how valid, payload, and sideband fields move or hold together.

## 1. Single-stage pipeline register

```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    valid_q <= 1'b0;
    data_q  <= 8'd0;
  end else if (!stall_i) begin
    valid_q <= valid_i;
    data_q  <= data_i;
  end
end
```

Pattern rule:
- data and valid move together
- stall freezes the whole stage
- reset behavior must be explicit for both data and control

## 2. Two-stage latency idea

```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    stage1_vld <= 1'b0;
    stage2_vld <= 1'b0;
  end else if (!stall_i) begin
    stage1_vld <= valid_i;
    stage2_vld <= stage1_vld;
  end
end
```

Pattern rule:
- latency must be named in the contract
- each stage should preserve alignment with its data and sideband fields

## 3. Flush behavior idea

```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    valid_q <= 1'b0;
  end else if (flush_i) begin
    valid_q <= 1'b0;
  end else if (!stall_i) begin
    valid_q <= valid_i;
  end
end
```

Pattern rule:
- flush must be distinct from stall
- define whether payload is discarded or merely hidden

## What to capture from pipeline examples
- latency per stage
- stall behavior
- flush behavior
- data/control alignment
- whether bypass is allowed
