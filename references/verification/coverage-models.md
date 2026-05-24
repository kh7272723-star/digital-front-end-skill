# Coverage Model Templates

## Purpose

This file provides functional coverage templates for common RTL patterns. Use these as starting points when defining coverage models for verification.

Sources: "SystemVerilog for Verification" (Chris Spear), "Coverage-Directed Verification Methodology" (Synopsys).

## FIFO coverage

```systemverilog
covergroup fifo_cg @(posedge clk);
  // Occupancy bins
  occupancy_cp: coverpoint fifo_count {
    bins empty = {0};
    bins almost_empty = {1};
    bins half = {DEPTH/2};
    bins almost_full = {DEPTH-1};
    bins full = {DEPTH};
    bins intermediate = {[2:DEPTH-2]};
  }

  // Operations
  wr_cp: coverpoint wr_en { bins write = {1}; bins no_write = {0}; }
  rd_cp: coverpoint rd_en { bins read = {1}; bins no_read = {0}; }

  // Simultaneous operations
  wr_rd_cross: cross wr_cp, rd_cp;

  // Boundary conditions
  full_wr: coverpoint (fifo_count == DEPTH && wr_en) { bins hit = {1}; }
  empty_rd: coverpoint (fifo_count == 0 && rd_en) { bins hit = {1}; }

  // Full + read (should allow read)
  full_rd: coverpoint (fifo_count == DEPTH && rd_en) { bins hit = {1}; }
  // Empty + write (should allow write)
  empty_wr: coverpoint (fifo_count == 0 && wr_en) { bins hit = {1}; }
endgroup
```

## Handshake (ready/valid) coverage

```systemverilog
covergroup handshake_cg @(posedge clk);
  // Transfer scenarios
  valid_cp: coverpoint valid_o { bins asserted = {1}; bins deasserted = {0}; }
  ready_cp: coverpoint ready_i { bins asserted = {1}; bins deasserted = {0}; }

  // Handshake combinations
  handshake_cross: cross valid_cp, ready_cp {
    bins transfer = binsof(valid_cp.asserted) && binsof(ready_cp.asserted);
    bins stall = binsof(valid_cp.asserted) && binsof(ready_cp.deasserted);
    bins idle = binsof(valid_cp.deasserted);
  }

  // Backpressure duration
  stall_duration_cp: coverpoint stall_cycles {
    bins short = {[1:3]};
    bins medium = {[4:10]};
    bins long = {[11:50]};
    bins very_long = {[51:$]};
  }

  // Back-to-back transfers
  back_to_back: coverpoint (valid_o && ready_i && $past(valid_o && ready_i)) {
    bins hit = {1};
  }
endgroup
```

## FSM coverage

```systemverilog
covergroup fsm_cg @(posedge clk);
  // State coverage
  state_cp: coverpoint state_q {
    bins idle = {IDLE};
    bins active = {ACTIVE};
    bins done = {DONE};
    bins error = {ERROR};
  }

  // State transitions
  state_transitions: coverpoint {state_q, state_d} {
    bins idle_to_active = {IDLE, ACTIVE};
    bins active_to_done = {ACTIVE, DONE};
    bins active_to_error = {ACTIVE, ERROR};
    bins error_to_idle = {ERROR, IDLE};
    bins done_to_idle = {DONE, IDLE};
  }

  // Stimulus coverage
  start_cp: coverpoint start_i { bins asserted = {1}; }
  error_cp: coverpoint error_i { bins asserted = {1}; }

  // Start from each state
  start_from_idle: coverpoint (start_i && state_q == IDLE) { bins hit = {1}; }
  error_from_active: coverpoint (error_i && state_q == ACTIVE) { bins hit = {1}; }
endgroup
```

## Arbiter coverage

```systemverilog
covergroup arbiter_cg @(posedge clk);
  // Grant coverage
  grant_cp: coverpoint grant_o {
    bins req0 = {4'b0001};
    bins req1 = {4'b0010};
    bins req2 = {4'b0100};
    bins req3 = {4'b1000};
    bins none = {4'b0000};
  }

  // Request patterns
  req_cp: coverpoint req_i {
    bins single0 = {4'b0001};
    bins single1 = {4'b0010};
    bins single2 = {4'b0100};
    bins single3 = {4'b1000};
    bins two_req = {[4'b0011:4'b1110]};
    bins all_req = {4'b1111};
  }

  // Fairness: each requester gets a grant within N cycles
  fairness_cp: coverpoint cycles_since_grant[0] {
    bins fast = {[1:4]};
    bins medium = {[5:16]};
    bins slow = {[17:$]};
  }

  // Simultaneous requests
  simultaneous: coverpoint ($countones(req_i) > 1) { bins hit = {1}; }
endgroup
```

## Pipeline coverage

```systemverilog
covergroup pipeline_cg @(posedge clk);
  // Pipeline occupancy
  valid_cp: coverpoint {valid_stage1, valid_stage2, valid_stage3} {
    bins empty = {3'b000};
    bins one_stage = {3'b100, 3'b010, 3'b001};
    bins two_stages = {3'b110, 3'b011, 3'b101};
    bins full = {3'b111};
  }

  // Stall scenarios
  stall_cp: coverpoint stall_stage {
    bins no_stall = {0};
    bins stage1 = {1};
    bins stage2 = {2};
    bins stage3 = {3};
  }

  // Flush scenarios
  flush_cp: coverpoint flush_i { bins asserted = {1}; }
  flush_stall: cross flush_cp, stall_cp;  // flush wins over stall

  // Bubble insertion
  bubble_cp: coverpoint (stall_stage > 0 && !flush_i) { bins hit = {1}; }
endgroup
```

## AXI protocol coverage

```systemverilog
covergroup axi_write_cg @(posedge clk);
  // Burst length
  awlen_cp: coverpoint awlen {
    bins len1 = {0};
    bins len2 = {1};
    bins len4 = {3};
    bins len8 = {7};
    bins len16 = {15};
    bins other = {[2:255]};
  }

  // Burst type
  awburst_cp: coverpoint awburst {
    bins fixed = {2'b00};
    bins incr = {2'b01};
    bins wrap = {2'b10};
  }

  // Response
  bresp_cp: coverpoint bresp {
    bins okay = {2'b00};
    bins exokay = {2'b01};
    bins slverr = {2'b10};
    bins decerr = {2'b11};
  }

  // Outstanding
  outstanding_cp: coverpoint outstanding_count {
    bins one = {1};
    bins few = {[2:4]};
    bins many = {[5:16]};
  }

  // Error response
  error_resp: coverpoint (bresp != 2'b00) { bins hit = {1}; }
endgroup
```

## Coverage closure checklist

- [ ] Coverage model defined before tests
- [ ] All bins have been hit (no unreachable bins)
- [ ] Cross coverage for important combinations
- [ ] Boundary conditions explicitly covered
- [ ] Error scenarios covered
- [ ] Coverage > 90% for functional coverage
- [ ] No vacuous assertions (antecedent always false)
- [ ] Coverage holes analyzed and either closed or excluded with rationale
