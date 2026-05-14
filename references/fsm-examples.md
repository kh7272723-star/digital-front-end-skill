# FSM example patterns

## Source policy

Use FSM examples that make state behavior obvious, keep outputs aligned with state, and avoid hidden side effects.
Prefer simple, readable Verilog FSMs that are easy to review and easy to simulate.
For this skill's default RTL style, prefer two-process FSMs for multi-stage control unless the project style requires otherwise.
When glitch-free outputs or clean timing boundaries matter, prefer registered outputs and state/output updates that are visible after the clock edge.

## 1. Two-process FSM skeleton

```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    state_q <= IDLE;
  end else begin
    state_q <= state_d;
  end
end

always @(*) begin
  state_d = state_q;
  done_o  = 1'b0;

  case (state_q)
    IDLE: begin
      if (start_i)
        state_d = RUN;
    end
    RUN: begin
      if (finish_i) begin
        state_d = DONE;
        done_o  = 1'b1;
      end
    end
    DONE: begin
      state_d = IDLE;
    end
    default: begin
      state_d = IDLE;
    end
  endcase
end
```

Pattern rule:

- separate state register from next-state logic
- give every output a default value
- define a safe default state
- document whether outputs are combinational from current state or registered for next-cycle visibility

## 2. One-hot control FSM idea

```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    state_q <= 3'b001;
  end else begin
    state_q <= state_d;
  end
end
```

Pattern rule:

- encoding choice must be explicit
- keep the encoding stable across the design or explain why it is not
- do not rely on hidden synthesis behavior

## 3. FSM with wait-state and handshake

```verilog
always @(*) begin
  state_d     = state_q;
  req_ready_o = 1'b0;
  rsp_valid_o = 1'b0;

  case (state_q)
    IDLE: begin
      req_ready_o = 1'b1;
      if (req_valid_i)
        state_d = BUSY;
    end
    BUSY: begin
      if (rsp_done_i)
        state_d = IDLE;
    end
    default: begin
      state_d = IDLE;
    end
  endcase
end
```

Pattern rule:

- handshake outputs must be tied to the state contract
- describe whether acceptance happens in the same cycle or next cycle
- verify backpressure explicitly

## 4. Recovery from illegal state

```verilog
always @(*) begin
  state_d = IDLE;
  case (state_q)
    IDLE:  state_d = start_i ? RUN : IDLE;
    RUN:   state_d = finish_i ? DONE : RUN;
    DONE:  state_d = IDLE;
    default: state_d = IDLE;
  endcase
end
```

Pattern rule:

- recovery path should be obvious
- do not leave illegal-state handling implicit

## What to capture from FSM examples

- state list and state meaning
- legal transitions
- reset state
- output behavior per state
- illegal-state recovery
- whether outputs are Moore-like or Mealy-like
- whether outputs must be glitch-free registered outputs
