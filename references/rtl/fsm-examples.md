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
    cstate <= IDLE;
  end else begin
    cstate <= nstate;
  end
end

always @(*) begin
  nstate = cstate;
  done_o  = 1'b0;

  case (cstate)
    IDLE: begin
      if (start_i)
        nstate = RUN;
    end
    RUN: begin
      if (finish_i) begin
        nstate = DONE;
        done_o  = 1'b1;
      end
    end
    DONE: begin
      nstate = IDLE;
    end
    default: begin
      nstate = IDLE;
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
    cstate <= 3'b001;
  end else begin
    cstate <= nstate;
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
  nstate     = cstate;
  req_ready_o = 1'b0;
  rsp_valid_o = 1'b0;

  case (cstate)
    IDLE: begin
      req_ready_o = 1'b1;
      if (req_valid_i)
        nstate = BUSY;
    end
    BUSY: begin
      if (rsp_done_i)
        nstate = IDLE;
    end
    default: begin
      nstate = IDLE;
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
  nstate = IDLE;
  case (cstate)
    IDLE:  nstate = start_i ? RUN : IDLE;
    RUN:   nstate = finish_i ? DONE : RUN;
    DONE:  nstate = IDLE;
    default: nstate = IDLE;
  endcase
end
```

Pattern rule:

- recovery path should be obvious
- do not leave illegal-state handling implicit

## 5. Control/Datapath separation at module level

For complex modules where the FSM logic and datapath logic are both substantial, separate them into distinct submodules. The FSM becomes a pure control module that outputs enable signals; the datapath module owns registers, counters, and memories.

```
parent_module (datapath)
├── status registers (count_q, addr_q, flags)
├── counter logic
├── FIFO or memory
└── control_fsm (submodule)
    ├── state register (cstate, nstate)
    ├── next-state logic
    └── output enables (load, send, incr, done)
```

**FSM submodule template:**

```verilog
module control_fsm(
    input  clk_i,
    input  rst_i,
    // Status inputs (from datapath)
    input  cmd_ready_i,
    input  count_nonzero_i,
    input  boundary_hit_i,
    // Control outputs (to datapath)
    output reg load_cmd_o,
    output reg incr_addr_o,
    output reg send_o,
    output reg done_o
);
    localparam S_IDLE = 2'b00;
    localparam S_LOAD = 2'b01;
    localparam S_SEND = 2'b10;
    localparam S_DONE = 2'b11;
    reg [1:0] cstate, nstate;

    // Process 1: state register only
    always @(posedge clk_i) begin
        if (rst_i) cstate <= S_IDLE;
        else       cstate <= nstate;
    end

    // Process 2: next-state + outputs with defaults
    always @(*) begin
        nstate     = cstate;
        load_cmd_o  = 1'b0;
        incr_addr_o = 1'b0;
        send_o      = 1'b0;
        done_o      = 1'b0;
        case (cstate)
            S_IDLE: begin
                if (cmd_ready_i) begin
                    load_cmd_o = 1'b1;
                    nstate    = S_LOAD;
                end
            end
            S_LOAD: begin
                nstate = S_SEND;
            end
            S_SEND: begin
                send_o = 1'b1;
                if (boundary_hit_i) begin
                    nstate = S_DONE;
                end else if (count_nonzero_i) begin
                    incr_addr_o = 1'b1;
                    nstate     = S_SEND;
                end else begin
                    nstate = S_DONE;
                end
            end
            S_DONE: begin
                done_o  = 1'b1;
                nstate = S_IDLE;
            end
            default: nstate = S_IDLE;
        endcase
    end
endmodule
```

**Datapath module template:**

```verilog
module data_channel #(...)(...);
    // Registers
    reg [ADDR_W-1:0] addr_q;
    reg [7:0]        count_q;
    reg              active_q;

    // Status signals (to FSM)
    wire count_nonzero = (count_q != 8'd0);
    wire boundary_hit  = (addr_q[11:0] == 12'hFFF);

    // Control signals (from FSM)
    wire load_cmd, incr_addr, send, done;

    // FSM instance
    control_fsm u_fsm (
        .clk_i(clk_i), .rst_i(rst_i),
        .cmd_ready_i(cmd_valid_i),
        .count_nonzero_i(count_nonzero),
        .boundary_hit_i(boundary_hit),
        .load_cmd_o(load_cmd),
        .incr_addr_o(incr_addr),
        .send_o(send),
        .done_o(done)
    );

    // Datapath: registers update on control enables
    always @(posedge clk_i) begin
        if (rst_i) begin
            addr_q  <= {ADDR_W{1'b0}};
            count_q <= 8'd0;
        end else if (load_cmd) begin
            addr_q  <= cmd_addr_i;
            count_q <= cmd_count_i;
        end else if (incr_addr) begin
            addr_q  <= addr_q + BYTES_PER_BEAT;
            count_q <= count_q - 1'b1;
        end
    end

    // AXI output: qualified by control signals
    assign m_axi_valid = send && active_q;
    assign m_axi_addr  = addr_q;
endmodule
```

**When to use this pattern:**
- Multiple instances share the same FSM (e.g., AR and AW channels use the same FSM module)
- Datapath has many registers that would clutter the FSM code
- Need to verify FSM independently with simple status stimulus
- Module exceeds ~200 lines and mixing control/datapath hurts readability

**When NOT to use:**
- Simple modules (< 100 lines) where two-process always blocks are clear enough
- FSM outputs are data values, not enables (then the FSM IS the datapath)
- Only one instance — no reuse benefit

**Key rules:**
- FSM submodule has NO datapath registers (only cstate/nstate)
- **All FSM inputs and outputs are single-bit control signals** — no multi-bit data passes through the FSM
- Multi-bit register assignments (addr_q, count_q, data_q) happen in the parent module, outside the FSM, controlled by the FSM's single-bit enables
- All FSM outputs default to 0 at the top of the combinational block
- Datapath module owns all registers, counters, and memories
- Parent module wires status signals in and control signals out

**Wrong pattern (multi-bit in FSM):**
```verilog
// BAD: FSM assigns multi-bit data directly
always @(*) begin
    case (cstate)
        S_LOAD: addr_d = cmd_addr_i;  // multi-bit assignment inside FSM
        S_SEND: addr_d = addr_q + 1;  // multi-bit arithmetic inside FSM
    endcase
end
```

**Correct pattern (single-bit enables, multi-bit in parent):**
```verilog
// FSM: outputs single-bit enables
always @(*) begin
    load_addr_o  = 1'b0;  // single-bit
    incr_addr_o  = 1'b0;  // single-bit
    case (cstate)
        S_LOAD: load_addr_o = 1'b1;
        S_SEND: incr_addr_o = 1'b1;
    endcase
end

// Parent module: multi-bit register update, controlled by enables
always @(posedge clk_i) begin
    if (load_addr)      axi_addr <= cmd_addr_i;
    else if (incr_addr) axi_addr <= axi_addr + 1'b1;
end
```

## What to capture from FSM examples

- state list and state meaning
- legal transitions
- reset state
- output behavior per state
- illegal-state recovery
- whether outputs are Moore-like or Mealy-like
- whether outputs must be glitch-free registered outputs

## Mandatory FSM rules

### Two-process style

For any FSM with more than 3 states or multiple control paths, use two-process style:

```verilog
// Process 1: state register only
always @(posedge clk_i) begin
  if (rst_i) cstate <= IDLE;
  else        cstate <= nstate;
end

// Process 2: next-state + outputs with defaults
always @(*) begin
  nstate = cstate; done_o = 1'b0;
  case (cstate)
    IDLE: if (start_i)  nstate = RUN;
    RUN:  if (finish_i) begin nstate = DONE; done_o = 1'b1; end
    DONE: nstate = IDLE;
    default: nstate = IDLE;
  endcase
end
```

Do not mix state transitions and output assignments in a single clocked block. This makes outputs hard to audit and assertions hard to add.

### Single-bit control rule

All FSM inputs and outputs must be single-bit control signals (enables, qualifiers, flags). Multi-bit register assignments (address, counter, data, length) must happen outside the FSM, gated by the FSM's single-bit enables.

The FSM decides *when* to act; the datapath decides *what* value to load. This separation makes the FSM reusable, auditable, and independently verifiable.

For complex modules (>200 lines) or when multiple instances share the same control logic, separate the FSM into its own submodule with only single-bit I/O.

### Common violations of single-bit control

These patterns look idiomatic but violate the rule. They appear repeatedly in LLM-generated RTL.

**Violation 1: Multi-bit `_d` assignments inside the FSM combinational block.**

The `_d` suffix is conventionally used for next-state signals, which makes multi-bit assignments like `addr_d = cmd_addr_i` or `block_cnt_d = block_cnt_q - 1` look like legitimate "next-state logic". They are not. If the target is wider than 1 bit, it belongs in a synchronous block gated by a single-bit enable, not in the FSM's `always @(*)`.

```verilog
// WRONG: multi-bit _d in FSM block
always @(*) begin
    nstate = cstate;
    block_cnt_d = block_cnt_q;  // 24-bit — this is datapath, not FSM
    rd_addr_d = rd_addr_q;      // 32-bit — this is datapath, not FSM
    case (cstate)
        S_LOAD: begin
            block_cnt_d = total_beats[31:8];  // WRONG: multi-bit in FSM
            rd_addr_d = cmd_src_addr_i;        // WRONG: multi-bit in FSM
            nstate = S_SEND;
        end
    endcase
end
```

**Violation 2: Second `always @(*)` block for multi-bit `_d` signals (the "shadow datapath").**

When the FSM block correctly uses only single-bit outputs, the LLM sometimes creates a second `always @(*)` block to compute multi-bit `_d` values. This block is gated on `cstate` or handshake fire signals — it's combinational logic controlled by FSM state, just in a different block. The multi-bit computation must be synchronous.

```verilog
// WRONG: second combinational block for multi-bit _d
always @(*) begin
    w_beat_cnt_d = w_beat_cnt_q;  // 8-bit
    if (cstate == ST_LOAD)
        w_beat_cnt_d = cmd_len_q;  // WRONG: state-gated combinational multi-bit
end

// RIGHT: synchronous, gated by single-bit enable from FSM
always @(posedge clk_i) begin
    if (rst_i)          w_beat_cnt_q <= 8'd0;
    else if (load_cnt)  w_beat_cnt_q <= cmd_len_q;  // load_cnt is single-bit, from FSM
    else if (dec_cnt)   w_beat_cnt_q <= w_beat_cnt_q - 8'd1;
end
```

**How to tell if you're violating:** Open every `always @(*)` block in the module. For each assignment, ask: "Is the target wider than 1 bit?" If yes, and the assignment is inside a `case (cstate)` or gated on `cstate == S_*`, it belongs in a synchronous block with a single-bit enable.
