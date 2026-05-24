# UVM Methodology Guidelines

## Purpose

This file covers UVM (Universal Verification Methodology) concepts for RTL verification. Use when the task involves constrained-random verification, coverage-driven closure, or UVM testbench architecture.

## Why UVM

- Directed tests catch known scenarios; UVM catches unknown corner cases
- Coverage-driven closure provides measurable verification completeness
- Reusable verification components (UVCs) reduce per-project effort

## UVM architecture overview

```
uvm_env
├── uvm_agent (per interface)
│   ├── uvm_driver      — drives DUT signals via virtual interface
│   ├── uvm_monitor     — observes DUT signals, sends transactions
│   └── uvm_sequencer   — arbitrates transaction sequences
├── uvm_scoreboard      — compares expected vs actual
├── uvm_coverage_collector — functional coverage
└── uvm_test            — top-level test configuration
```

## Key concepts

### Transactions

```systemverilog
class my_transaction extends uvm_sequence_item;
  rand bit [31:0] addr;
  rand bit [31:0] data;
  rand bit        write;
  `uvm_object_utils_begin(my_transaction)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(data, UVM_ALL_ON)
    `uvm_field_int(write, UVM_ALL_ON)
  `uvm_object_utils_end
endclass
```

### Sequences

```systemverilog
class my_sequence extends uvm_sequence #(my_transaction);
  `uvm_object_utils(my_sequence)
  task body();
    my_transaction tx;
    repeat(100) begin
      tx = my_transaction::type_id::create("tx");
      start_item(tx);
      assert(tx.randomize());
      finish_item(tx);
    end
  endtask
endclass
```

### Driver

```systemverilog
class my_driver extends uvm_driver #(my_transaction);
  virtual my_if vif;
  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      drive_transaction(req);
      seq_item_port.item_done();
    end
  endtask
endclass
```

### Scoreboard

```systemverilog
class my_scoreboard extends uvm_scoreboard;
  uvm_analysis_imp #(my_transaction, my_scoreboard) ap;
  function void write(my_transaction tx);
    // Compare against reference model
    if (tx.data !== expected)
      `uvm_error("MISMATCH", $sformatf("Got %h, expected %h", tx.data, expected))
  endfunction
endclass
```

## Functional coverage

```systemverilog
covergroup my_cg @(posedge clk);
  addr_cp: coverpoint tx.addr {
    bins low  = {[0:32'hFFFF]};
    bins high = {[32'h10000:32'hFFFFFFFF]};
  }
  write_cp: coverpoint tx.write;
  cross addr_cp, write_cp;
endgroup
```

### Coverage closure strategy

1. Define coverage model before writing tests
2. Run constrained-random to hit easy bins
3. Analyze holes, write directed sequences for hard bins
4. Close at 90%+ functional coverage before signoff

## Constrained-random vs directed

| Aspect | Constrained-random | Directed |
|--------|-------------------|----------|
| Coverage | Broad, finds unknowns | Narrow, targets known scenarios |
| Debug | Harder (random seed) | Easier (deterministic) |
| Reuse | High (new constraints) | Low (new test per scenario) |
| Best for | Corner discovery | Protocol compliance, error injection |

## UVM vs this skill's current verification

Current skill: directed tests + SVA assertions + pass/fail signals
UVM: constrained-random + coverage + scoreboard + reuse

Gap: the skill does not generate UVM testbenches. It generates directed tests and assertions, which are useful for basic verification but insufficient for signoff-level closure.

## When to use UVM

- Multi-protocol interfaces with many valid combinations
- Stateful designs with hard-to-reach corner cases
- Projects requiring coverage signoff metrics
- Verification environments that will be reused across designs

## When directed tests are enough

- Simple leaf modules (counters, register slices)
- Protocol adapters with limited state space
- Early bring-up and smoke tests
- Assertion-heavy designs where formal covers the gaps

## Common mistakes

1. Writing UVM without a coverage model (random without purpose)
2. Over-constraining random sequences (defeats the purpose)
3. No scoreboard (random stimulus without checking is useless)
4. Ignoring functional coverage holes (running more random seeds does not help)
5. Using UVM for trivial modules (overhead without benefit)
