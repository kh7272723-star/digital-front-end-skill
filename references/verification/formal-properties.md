# Formal Property Templates

## Purpose

This file provides ready-to-use SVA property templates for common RTL patterns. Use these as starting points when adding formal verification to a design.

Sources: IEEE 1800-2017 SystemVerilog Standard (Section 16), "SystemVerilog Assertions Handbook" (Ben Cohen), "Formal Verification: An Essential Toolkit for Confident SoC Design" (Synopsys).

## Ready/valid properties

```systemverilog
// P1: Valid must hold until ready (no dropping valid)
property p_valid_hold;
  @(posedge clk) (valid_o && !ready_i) |-> ##1 valid_o;
endproperty

// P2: Data must hold while valid && !ready (stability)
property p_data_stable;
  @(posedge clk) (valid_o && !ready_i) |-> ##1 $stable(data_o);
endproperty

// P3: Transfer completes on valid && ready
property p_transfer;
  @(posedge clk) (valid_o && ready_i) |-> ##1 (!valid_o || valid_i);
endproperty

// P4: Ready can deassert at any time (no dependency on valid)
property p_ready_independent;
  @(posedge clk) 1'b1 |-> (ready_i == $past(ready_i) || !valid_o);
  // Simplified: ready can change freely
endproperty

// P5: No combinational loop through ready
// (Check with lint, not SVA — included for completeness)
```

## FIFO properties

```systemverilog
// F1: Full flag correct
property p_full_correct;
  @(posedge clk) full_o |-> (count == DEPTH);
endproperty

// F2: Empty flag correct
property p_empty_correct;
  @(posedge clk) empty_o |-> (count == 0);
endproperty

// F3: No write when full (unless also reading)
property p_no_overflow;
  @(posedge clk) (full_o && wr_en) |-> rd_en;
endproperty

// F4: No read when empty
property p_no_underflow;
  @(posedge clk) (empty_o && rd_en) |-> 1'b0;  // should never happen
endproperty

// F5: Count changes correctly on write only
property p_count_write;
  @(posedge clk) (wr_en && !rd_en && !full_o) |-> ##1 (count == $past(count) + 1);
endproperty

// F6: Count changes correctly on read only
property p_count_read;
  @(posedge clk) (rd_en && !wr_en && !empty_o) |-> ##1 (count == $past(count) - 1);
endproperty

// F7: Count stable on simultaneous read/write
property p_count_simultaneous;
  @(posedge clk) (wr_en && rd_en && !full_o && !empty_o) |-> ##1 (count == $past(count));
endproperty

// F8: Data appears on read after write
property p_data_latency;
  @(posedge clk) (wr_en && !full_o) |-> ##[1:$] (rd_en && rdata == $past(wdata, 1));
  // Note: exact latency depends on implementation
endproperty
```

## FSM properties

```systemverilog
// S1: Reset state
property p_reset_state;
  @(posedge clk) $rose(rst_n) |-> (state == IDLE);
endproperty

// S2: One-hot state encoding
property p_onehot;
  @(posedge clk) $onehot(state);
endproperty

// S3: Legal state transitions only
property p_legal_transition;
  @(posedge clk) (state == IDLE && start) |-> ##1 (state == ACTIVE);
endproperty

// S4: Eventually returns to idle
property p_eventually_idle;
  @(posedge clk) (state == ACTIVE) |-> (##[1:$] (state == IDLE));
endproperty

// S5: No illegal states
property p_no_illegal;
  @(posedge clk) (state inside {IDLE, ACTIVE, DONE, ERROR});
endproperty

// S6: Error recovery
property p_error_recovery;
  @(posedge clk) (state == ERROR) |-> ##[1:$] (state == IDLE);
endproperty
```

## Pipeline properties

```systemverilog
// PL1: Valid advances through pipeline
property p_valid_advance;
  @(posedge clk) (valid_s1 && ready_s2) |-> ##1 valid_s2;
endproperty

// PL2: Flush clears all valids
property p_flush_clear;
  @(posedge clk) flush_i |-> ##1 (!valid_s1 && !valid_s2 && !valid_s3);
endproperty

// PL3: Stall holds all values
property p_stall_hold;
  @(posedge clk) (valid_s1 && stall_s2) |-> ##1 ($stable(data_s1) && $stable(valid_s1));
endproperty

// PL4: Flush wins over stall
property p_flush_over_stall;
  @(posedge clk) (flush_i && stall_i) |-> ##1 (!valid_s1);
endproperty

// PL5: No bubble insertion without stall
property p_no_bubble;
  @(posedge clk) (!stall_i && !flush_i && valid_s1) |-> ##1 valid_s2;
endproperty
```

## Counter properties

```systemverilog
// C1: Counter increments correctly
property p_counter_incr;
  @(posedge clk) (en && !load && count < MAX) |-> ##1 (count == $past(count) + 1);
endproperty

// C2: Counter does not overflow
property p_no_overflow;
  @(posedge clk) (count == MAX && en && !load) |-> ##1 (count == MAX);
endproperty

// C3: Load overrides count
property p_load_priority;
  @(posedge clk) (load && en) |-> ##1 (count == $past(load_val));
endproperty

// C4: Counter resets correctly
property p_counter_reset;
  @(posedge clk) rst |-> ##1 (count == 0);
endproperty
```

## AXI properties

```systemverilog
// A1: AWVALID holds until AWREADY
property p_awvalid_hold;
  @(posedge clk) (awvalid && !awready) |-> ##1 awvalid;
endproperty

// A2: WVALID holds until WREADY
property p_wvalid_hold;
  @(posedge clk) (wvalid && !wready) |-> ##1 wvalid;
endproperty

// A3: WLAST on final beat
property p_wlast_correct;
  @(posedge clk) (wvalid && wready && w_beats_remaining == 1) |-> wlast;
endproperty

// A4: BVALID holds until BREADY
property p_bvalid_hold;
  @(posedge clk) (bvalid && !bready) |-> ##1 bvalid;
endproperty

// A5: RVALID holds until RREADY
property p_rvalid_hold;
  @(posedge clk) (rvalid && !rready) |-> ##1 rvalid;
endproperty

// A6: RLAST on final beat
property p_rlast_correct;
  @(posedge clk) (rvalid && rready && r_beats_remaining == 1) |-> rlast;
endproperty

// A7: No write data before address accepted
property p_w_after_aw;
  @(posedge clk) wvalid |-> awaccepted || awvalid;
endproperty
```

## Arbiter properties

```systemverilog
// AR1: At most one grant
property p_one_grant;
  @(posedge clk) $onehot0(grant_o);
endproperty

// AR2: Grant only when requested
property p_grant_when_requested;
  @(posedge clk) (grant_o != 0) |-> (req_i & grant_o) != 0;
endproperty

// AR3: Eventually each requester gets service
property p_fairness_req0;
  @(posedge clk) req_i[0] |-> ##[1:$] grant_o[0];
endproperty

// AR4: No starvation
property p_no_starvation;
  @(posedge clk) (req_i[0] && !grant_o[0]) |-> ##[1:16] grant_o[0];
endproperty
```

## CDC properties

```systemverilog
// CDC1: Multi-bit bus must use gray/handshake
// (Check with CDC tool, not SVA — included for documentation)

// CDC2: Synchronizer output stability
property p_sync_stable;
  @(posedge clk_b) $stable(sync_out);
  // Simplified: sync output should not glitch
endproperty

// CDC3: Handshake CDC completion
property p_cdc_handshake;
  @(posedge clk_a) req_a |-> ##[2:10] ack_a;
  // Request should be acknowledged within N cycles
endproperty
```

## Property categories for formal vs simulation

| Property type | Formal? | Simulation? | Notes |
|--------------|---------|-------------|-------|
| Safety (bad never happens) | Yes | Yes | Formal is exhaustive |
| Liveness (good eventually) | Yes (unbounded) | Yes (bounded) | Formal needs fairness constraint |
| Stability (value holds) | Yes | Yes | Both catch violations |
| Deadlock freedom | Yes | Yes | Formal proves for all states |
| Coverage (state reachable) | Yes (cover) | Yes (covergroup) | Formal proves reachability |

## Common formal pitfalls

1. Over-constraining inputs (false proof)
2. Under-constraining inputs (false counterexample)
3. BMC depth too short (bounded proof only)
4. Properties too weak (pass trivially)
5. No fairness constraints for liveness (stuttering counterexamples)
