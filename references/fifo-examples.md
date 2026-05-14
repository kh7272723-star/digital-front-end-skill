# FIFO example patterns

## Source policy
Use FIFO examples that make boundary behavior explicit.
Prefer simple Verilog that exposes pointers, occupancy, and simultaneous write/read behavior clearly.
Use `naming-guidelines.md` for signal names and `cycle-trace-guidelines.md` before selecting a FIFO implementation.

## 1. Occupancy-based FIFO skeleton

```verilog
wire wr_do;
wire rd_do;

assign wr_do = wr_en_i && !full_o;
assign rd_do = rd_en_i && !empty_o;

always @(posedge clk_i) begin
  if (rst_i) begin
    wr_ptr <= 3'd0;
    rd_ptr <= 3'd0;
    count  <= 4'd0;
  end else begin
    if (wr_do)
      wr_ptr <= wr_ptr + 3'd1;
    if (rd_do)
      rd_ptr <= rd_ptr + 3'd1;
    case ({wr_do, rd_do})
      2'b10: count <= count + 4'd1;
      2'b01: count <= count - 4'd1;
      default: count <= count;
    endcase
  end
end
```

Pattern rule:
- define write/read legality explicitly
- keep occupancy updates consistent with pointer updates
- simultaneous write/read behavior must be defined in the contract
- this conservative skeleton rejects `wr_en` when full even if `rd_en` is high in the same cycle
- if full+read should accept a new write, specify memory read-during-write behavior before coding

## 2. Full and empty generation idea

```verilog
assign empty_o = (count_q == 4'd0);
assign full_o  = (count_q == DEPTH[3:0]);
```

Pattern rule:
- full and empty should come from one consistent occupancy model
- do not allow a hidden second truth source for boundary state

## 3. Read/write memory access idea

```verilog
always @(posedge clk_i) begin
  if (wr_do)
    mem[wr_ptr] <= din;
  if (rd_do)
    dout <= mem[rd_ptr];
end
```

Pattern rule:
- memory access must follow the same write/read contract as the control logic
- define whether read data is registered or combinational in the contract
- define old-data versus new-data behavior for same-address read/write if the design permits it

## What to capture from FIFO examples
- how depth is represented
- how full and empty are derived
- what happens when write and read occur together
- whether data output is registered or immediate
- what overflow and underflow protections are required
