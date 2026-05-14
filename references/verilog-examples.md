# Verilog example patterns

## Source policy

These examples are meant to be representative Verilog RTL patterns, not copy-paste coding toys.
Use them only when they preserve synthesizability, readability, and explicit cycle behavior.
Prefer plain Verilog-style RTL unless SystemVerilog is required by the user.

## 1. Register with synchronous reset

```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    q_o <= 1'b0;
  end else if (en_i) begin
    q_o <= d_i;
  end
end
```

Pattern rule:

- reset value must be explicit
- enable must be part of the state update condition
- this style is appropriate for a single-bit or single-register update

## 2. Combinational next-state logic

```verilog
always @(*) begin
  state_d = state_q;
  done_o  = 1'b0;

  case (state_q)
    IDLE: begin
      if (start_i)
        state_d = BUSY;
    end
    BUSY: begin
      if (finish_i) begin
        state_d = IDLE;
        done_o  = 1'b1;
      end
    end
    default: begin
      state_d = IDLE;
    end
  endcase
end
```

Pattern rule:

- assign safe defaults first
- cover every state
- keep outputs and next-state behavior explicit

## 3. Ready/valid acceptance rule

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

- name the handshake condition explicitly
- preserve data while valid is waiting
- separate input acceptance from output consumption
- this example is a one-entry registered slice; input becomes visible after the active edge

## 4. Simple counter

```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    count <= 8'd0;
  end else if (enable_i) begin
    count <= count + 8'd1;
  end
end
```

Pattern rule:

- reset, enable, and width must be explicit
- wrap or saturation behavior must be stated if it matters

## 5. One-hot style state update skeleton

```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    state_q <= IDLE;
  end else begin
    state_q <= state_d;
  end
end
```

Pattern rule:

- keep state register separate from combinational next-state logic
- document state encoding choice if it matters to synthesis or debug

## 6. FIFO occupancy example

```verilog
wire wr_do;
wire rd_do;

assign wr_do = wr_en_i && !full_o;
assign rd_do = rd_en_i && !empty_o;

always @(posedge clk_i) begin
  if (rst_i) begin
    wr_ptr_q <= 4'd0;
    rd_ptr_q <= 4'd0;
    count_q  <= 5'd0;
  end else begin
    if (wr_do)
      wr_ptr_q <= wr_ptr_q + 4'd1;
    if (rd_do)
      rd_ptr_q <= rd_ptr_q + 4'd1;
    case ({wr_do, rd_do})
      2'b10: count_q <= count_q + 5'd1;
      2'b01: count_q <= count_q - 5'd1;
      default: count_q <= count_q;
    endcase
  end
end
```

Pattern rule:

- define simultaneous write/read behavior
- keep pointer and occupancy updates consistent
- make full and empty conditions derived from the same contract
- this conservative example does not accept a write on a full+read cycle; add that policy only when memory semantics are specified

## 7. Pipeline register stage

```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    vld_q <= 1'b0;
  end else if (!stall_i) begin
    vld_q <= vld_i;
    data_q <= data_i;
  end
end
```

Pattern rule:

- data and valid must move together
- stall behavior must freeze both signals consistently
- flush behavior must be defined separately if needed

## 8. Simple arbiter skeleton

```verilog
always @(*) begin
  grant = 3'b000;
  case (1'b1)
    req[0]: grant = 3'b001;
    req[1]: grant = 3'b010;
    req[2]: grant = 3'b100;
    default: grant = 3'b000;
  endcase
end
```

Pattern rule:

- arbitration policy must be obvious from the code
- fairness or priority must be stated explicitly
- if hold behavior matters, add state or registered grant logic

## What the agent should extract from examples

- the condition that causes a state update
- the exact cycle when outputs change
- whether data must be held, advanced, or discarded
- whether reset forces a visible output state or just an internal state
- the simplest readable form that still preserves the contract
