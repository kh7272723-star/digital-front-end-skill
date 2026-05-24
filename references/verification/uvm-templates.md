# UVM Testbench Templates

## Purpose

This file provides runnable UVM testbench templates for common RTL patterns. Adapt these templates to your specific module.

Sources: UVM 1.2 User Guide (Accellera), "SystemVerilog for Verification" (Chris Spear), "UVM Cookbook" (Mentor Graphics).

## Template: Ready/valid register slice

### Transaction

```systemverilog
class rv_transaction extends uvm_sequence_item;
  rand bit [31:0] data;
  rand bit        valid;

  `uvm_object_utils_begin(rv_transaction)
    `uvm_field_int(data, UVM_ALL_ON)
    `uvm_field_int(valid, UVM_ALL_ON)
  `uvm_object_utils_end

  constraint c_valid { valid dist {1 := 80, 0 := 20}; }
endclass
```

### Driver

```systemverilog
class rv_driver extends uvm_driver #(rv_transaction);
  `uvm_component_utils(rv_driver)

  virtual rv_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    rv_transaction tx;
    vif.valid_i <= 0;
    vif.data_i  <= 0;
    @(posedge vif.clk);

    forever begin
      seq_item_port.get_next_item(tx);
      drive_transaction(tx);
      seq_item_port.item_done();
    end
  endtask

  task drive_transaction(rv_transaction tx);
    vif.valid_i <= 1;
    vif.data_i  <= tx.data;
    @(posedge vif.clk);
    while (!vif.ready_o) @(posedge vif.clk);  // wait for ready
    vif.valid_i <= 0;
  endtask
endclass
```

### Monitor

```systemverilog
class rv_monitor extends uvm_monitor;
  `uvm_component_utils(rv_monitor)

  virtual rv_if vif;
  uvm_analysis_port #(rv_transaction) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    rv_transaction tx;
    forever begin
      @(posedge vif.clk);
      if (vif.valid_i && vif.ready_o) begin
        tx = rv_transaction::type_id::create("tx");
        tx.data = vif.data_i;
        tx.valid = 1;
        ap.write(tx);
      end
    end
  endtask
endclass
```

### Scoreboard

```systemverilog
class rv_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(rv_scoreboard)

  uvm_analysis_imp #(rv_transaction, rv_scoreboard) exp_imp;
  uvm_analysis_imp #(rv_transaction, rv_scoreboard) act_imp;

  rv_transaction exp_queue[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    exp_imp = new("exp_imp", this);
    act_imp = new("act_imp", this);
  endfunction

  function void write(rv_transaction tx);
    exp_queue.push_back(tx);
  endfunction

  task run_phase(uvm_phase phase);
    rv_transaction exp, act;
    forever begin
      wait(exp_queue.size() > 0);
      exp = exp_queue.pop_front();
      // Compare with actual output
      // act = get_actual_from_monitor();
      // if (exp.data !== act.data)
      //   `uvm_error("MISMATCH", $sformatf("Exp %h, got %h", exp.data, act.data))
    end
  endtask
endclass
```

### Environment

```systemverilog
class rv_env extends uvm_env;
  `uvm_component_utils(rv_env)

  rv_agent    agent;
  rv_scoreboard sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = rv_agent::type_id::create("agent", this);
    sb    = rv_scoreboard::type_id::create("sb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.monitor.ap.connect(sb.exp_imp);
  endfunction
endclass
```

### Test

```systemverilog
class rv_base_test extends uvm_test;
  `uvm_component_utils(rv_base_test)

  rv_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = rv_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    rv_sequence seq;
    phase.raise_objection(this);
    seq = rv_sequence::type_id::create("seq");
    seq.start(env.agent.sequencer);
    #100;
    phase.drop_objection(this);
  endtask
endclass
```

## Template: FIFO testbench

### Sequence (constrained-random)

```systemverilog
class fifo_sequence extends uvm_sequence #(fifo_transaction);
  `uvm_object_utils(fifo_sequence)

  task body();
    fifo_transaction tx;
    repeat(1000) begin
      tx = fifo_transaction::type_id::create("tx");
      start_item(tx);
      assert(tx.randomize() with {
        tx.wr_en dist {1 := 60, 0 := 40};
        tx.rd_en dist {1 := 40, 0 := 60};
      });
      finish_item(tx);
    end
  endtask
endclass
```

### Directed sequences for boundary conditions

```systemverilog
class fifo_fill_sequence extends uvm_sequence #(fifo_transaction);
  `uvm_object_utils(fifo_fill_sequence)

  task body();
    fifo_transaction tx;
    // Fill FIFO completely
    repeat(DEPTH) begin
      tx = fifo_transaction::type_id::create("tx");
      tx.wr_en = 1;
      tx.rd_en = 0;
      start_item(tx);
      finish_item(tx);
    end
    // Try to write when full
    tx = fifo_transaction::type_id::create("tx");
    tx.wr_en = 1;
    tx.rd_en = 0;
    start_item(tx);
    finish_item(tx);
  endtask
endclass

class fifo_drain_sequence extends uvm_sequence #(fifo_transaction);
  `uvm_object_utils(fifo_drain_sequence)

  task body();
    fifo_transaction tx;
    // Empty FIFO completely
    repeat(DEPTH) begin
      tx = fifo_transaction::type_id::create("tx");
      tx.wr_en = 0;
      tx.rd_en = 1;
      start_item(tx);
      finish_item(tx);
    end
    // Try to read when empty
    tx = fifo_transaction::type_id::create("tx");
    tx.wr_en = 0;
    tx.rd_en = 1;
    start_item(tx);
    finish_item(tx);
  endtask
endclass
```

## Template: FSM testbench

### Stimulus strategy

```systemverilog
class fsm_sequence extends uvm_sequence #(fsm_transaction);
  `uvm_object_utils(fsm_sequence)

  task body();
    // Happy path: idle -> active -> done -> idle
    send_start();
    wait_done();

    // Error injection: active -> error -> idle
    send_start();
    inject_error();
    wait_idle();

    // Rapid start/done cycles
    repeat(10) begin
      send_start();
      wait_done();
    end

    // Start while active (should be ignored)
    send_start();
    send_start();  // second start during active
    wait_done();
  endtask
endclass
```

## Coverage integration

```systemverilog
class rv_coverage extends uvm_subscriber #(rv_transaction);
  `uvm_component_utils(rv_coverage)

  covergroup rv_cg;
    data_cp: coverpoint tx.data {
      bins zero = {0};
      bins max = {32'hFFFFFFFF};
      bins others = {[1:32'hFFFFFFFE]};
    }
    valid_cp: coverpoint tx.valid;
  endgroup

  rv_transaction tx;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rv_cg = new();
  endfunction

  function void write(rv_transaction t);
    tx = t;
    rv_cg.sample();
  endfunction
endclass
```

## Test selection strategy

| Test | Sequence | Purpose |
|------|----------|---------|
| smoke_test | Happy path sequence | Basic functionality |
| backpressure_test | Random stall sequence | Stall handling |
| boundary_test | Fill/drain sequences | FIFO full/empty |
| random_test | Constrained-random (1000+ txns) | Coverage closure |
| error_test | Error injection sequences | Error handling |
| timing_test | Minimum interval sequences | Timing edge cases |

## Common UVM mistakes

1. No scoreboard (stimulus without checking)
2. Over-constraining random sequences (defeats purpose)
3. No coverage model (random without measurement)
4. Using UVM for trivial modules (overhead without benefit)
5. Not using `uvm_field macros for debug printing
6. Forgetting `raise_objection`/`drop_objection` in test
