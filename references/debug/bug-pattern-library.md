# Bug pattern library

## Purpose

This file encodes known RTL bug patterns so the agent can warn during generation, not only after failure.
When writing or reviewing RTL, match the module type and pattern category to these patterns.
For each matched pattern, cite the pattern ID, include the prevention assertion, and explain how the code avoids (or does not avoid) the bug.

## Sources

| ID | Document | Publisher |
|----|----------|-----------|
| IEEE1364 | IEEE Std 1364-2005 (Verilog) | IEEE |
| IEEE1800 | IEEE Std 1800-2017 (SystemVerilog) | IEEE |
| IHI0022E | AMBA AXI and ACE Protocol Specification | Arm |
| IHI0024 | AMBA APB Protocol Specification | Arm |
| IHI0051 | AMBA AXI4-Stream Protocol Specification | Arm |
| SNUG | Cummings SNUG papers (CDC, FSM, NB assignments) | Sunburst Design |
| CDMA | Real project experience: CDMA 6-round review (2026-05-19~22) | Project |
| TIMER | Real project experience: Timer subsystem (2026-05-23) | Project |
| INTC | Real project experience: Interrupt controller (2026-05-23) | Project |
| CRC | Real project experience: CRC AXI-Stream generator (2026-05-23) | Project |

## Pattern structure

Each pattern has:
- **Category**: handshake / boundary / reset / pipeline / protocol / counter / state-machine
- **Frequency**: high / medium / low — how often this appears in real RTL work
- **Applies to**: which module types or structures are at risk
- **Symptom**: what the user or simulation observes
- **Root cause**: the RTL structure that creates the bug
- **Trigger conditions**: what causes the bug to manifest
- **Bug code pattern**: typical wrong code
- **Correct code pattern**: typical fix
- **First divergent cycle**: how to locate the bug in a waveform
- **Prevention assertion**: SVA or Verilog check to catch the bug
- **Regression test**: minimal directed test

---

## Handshake patterns

### H1: Payload changes during downstream stall

**Category:** handshake
**Frequency:** high
**Applies to:** any ready/valid path

**Symptom:** output data changes while `valid_o` is high and `ready_i` is low. Downstream receives corrupted or duplicated data.

**Root cause:** the data register is updated whenever new input arrives, regardless of whether the output has been consumed.

**Trigger conditions:** upstream asserts `valid_i` with new data while downstream is backpressuring (`ready_i = 0`).

**Bug code pattern:**
```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    valid_o <= 1'b0;
    data_o  <= {DATA_W{1'b0}};
  end else begin
    if (valid_i) begin       // BUG: captures new data even when output is stalled
      valid_o <= 1'b1;
      data_o  <= data_i;
    end else if (ready_i) begin
      valid_o <= 1'b0;
    end
  end
end
```

**Correct code pattern:**
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

**First divergent cycle:** the cycle where `valid_o && !ready_i` and `data_o` changes value on the next clock edge.

**VCD detection:**
```bash
python scripts/vcd_extract.py dump.vcd --signals valid_o,ready_i,data_o --range 0:100000
# Look for: valid_o=1, ready_i=0, then data_o changes on next line
# Or: find transitions of data_o, then check if valid_o=1 && ready_i=0 at that time
```
Manual VCD check: grep for the signal ID of `data_o`, find value changes, then cross-reference `valid_o` and `ready_i` at the same timestamp.

**Prevention assertion:**
```systemverilog
property p_payload_stable_under_stall;
  @(posedge clk_i) disable iff (rst_i)
    (valid_o && !ready_i) |=> (valid_o && $stable(data_o));
endproperty
assert property (p_payload_stable_under_stall);
```

**Regression test:** send one item, deassert `ready_i`, assert new `valid_i` with different data, check `data_o` does not change.

---

### H2: Ready combinational loop

**Category:** handshake
**Frequency:** medium
**Applies to:** any multi-module ready/valid chain

**Symptom:** simulation hangs or produces X-propagation. Synthesis may create combinational loops that fail timing or oscillate.

**Root cause:** `ready_o` of one module depends combinationally on `ready_i` of the next, which depends on its `ready_o`, forming a loop through multiple modules.

**Trigger conditions:** two or more modules in series where each module's ready output is a combinational function of the downstream ready, with no registered stage in between.

**Bug code pattern:**
```verilog
// Module A
assign ready_o_a = !valid_o_a || (ready_i_a && ready_o_b);  // depends on Module B's ready
// Module B
assign ready_o_b = !valid_o_b || ready_i_b;                  // clean
// But if Module B also combinational-gates on ready_o_c, the chain grows
```

**Correct code pattern:**
```verilog
// Break the combinational chain with a register slice or skid buffer
// Or use registered ready output:
always @(posedge clk_i) begin
  if (rst_i)
    ready_o_q <= 1'b1;
  else
    ready_o_q <= !valid_o || ready_i;
end
assign ready_o = ready_o_q;
```

**First divergent cycle:** no single cycle — the loop exists combinationally. Detect by lint or synthesis tool reporting combinational loops.

**Prevention assertion:** no SVA for this — use lint/synthesis checks. Add a comment: "ready path must not form combinational loop across module boundary."

**Regression test:** connect three modules in series, verify throughput is not zero, run lint.

---

### H3: Valid rises before data is stable

**Category:** handshake
**Frequency:** medium
**Applies to:** any ready/valid source

**Symptom:** downstream samples incorrect data on the first cycle `valid_o` is high.

**Root cause:** `valid_o` is set combinationally from an input condition, but `data_o` is registered and arrives one cycle later.

**Trigger conditions:** the source derives `valid_o` from a combinational path while `data_o` passes through a register.

**Bug code pattern:**
```verilog
assign valid_o = start_condition;  // combinational, immediate
always @(posedge clk_i) begin
  data_o <= data_i;                // registered, one cycle delayed
end
```

**Correct code pattern:**
```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    valid_o <= 1'b0;
    data_o  <= {DATA_W{1'b0}};
  end else begin
    valid_o <= start_condition;
    if (start_condition)
      data_o <= data_i;
  end
end
```

**First divergent cycle:** the first cycle where `valid_o` is high — check whether `data_o` has the expected value at the same edge.

**Prevention assertion:**
```systemverilog
property p_valid_and_data_aligned;
  @(posedge clk_i) disable iff (rst_i)
    $rose(valid_o) |-> $stable(data_o);
endproperty
assert property (p_valid_and_data_aligned);
```

**Regression test:** assert `valid_i`, check `valid_o` and `data_o` on the same and next cycle.

---

### H4: Handshake deadlock

**Category:** handshake
**Frequency:** low
**Applies to:** any bidirectional handshake (ready/valid, req/ack)

**Symptom:** simulation hangs — neither side makes progress.

**Root cause:** both sides wait for the other to act first. For example, producer waits for `ready` before asserting `valid`, consumer waits for `valid` before asserting `ready`.

**Trigger conditions:** the contract does not specify which side may assert first, and both sides implement a "wait for the other" policy.

**Bug code pattern:**
```verilog
// Producer
assign valid_o = ready_i;  // waits for ready first
// Consumer
assign ready_o = valid_i;  // waits for valid first
// Deadlock: neither asserts first
```

**Correct code pattern:**
```verilog
// Producer: assert valid when data is available, regardless of ready
assign valid_o = data_available;
// Consumer: assert ready when it can accept, regardless of valid
assign ready_o = can_accept;
```

**First divergent cycle:** no cycle fires — detect by timeout in simulation.

**Prevention assertion:** use a liveness assertion or timeout monitor:
```verilog
reg [15:0] stall_counter;
always @(posedge clk_i) begin
  if (rst_i || (valid_o && ready_i))
    stall_counter <= 0;
  else if (valid_o || ready_i)
    stall_counter <= stall_counter + 1;
  if (stall_counter > 1000)
    $fatal(1, "Handshake timeout");
end
```

**Regression test:** connect producer and consumer, verify transfer completes within bounded cycles.

---

### H5: Lost transfer (incomplete accept condition)

**Category:** handshake
**Frequency:** medium
**Applies to:** any ready/valid path with enable or conditional logic

**Symptom:** valid data is presented but never consumed, or consumed but not counted.

**Root cause:** the accept condition (`accept_input = valid_i && ready_o`) is incomplete — it misses an enable, a grant, or a capacity check.

**Trigger conditions:** the missing condition is occasionally false even when valid and ready are both asserted.

**Bug code pattern:**
```verilog
// Missing enable gate
assign accept_input = valid_i && ready_o;
// Should be:
assign accept_input = valid_i && ready_o && enable_i;
```

**Correct code pattern:**
```verilog
assign accept_input = valid_i && ready_o && enable_i;
```

**First divergent cycle:** the cycle where `valid_i && ready_o` is true but the expected state update does not occur.

**Prevention assertion:**
```systemverilog
property p_accept_triggers_update;
  @(posedge clk_i) disable iff (rst_i)
    (valid_i && ready_o) |=> /* expected state change */;
endproperty
```

**Regression test:** present valid data with `enable_i` toggling, verify no transfer is lost.

---

## Boundary patterns

### B1: FIFO accepts write when full

**Category:** boundary
**Frequency:** high
**Applies to:** any FIFO

**Symptom:** FIFO count exceeds depth, or stored data is corrupted.

**Root cause:** `wr_do` includes a condition that bypasses the full check, such as `!full_o || rd_en_i`.

**Trigger conditions:** write and read are asserted simultaneously when the FIFO is full.

**Bug code pattern:**
```verilog
assign wr_do = wr_en_i && (!full_o || rd_en_i);  // BUG: accepts write on full+read
```

**Correct code pattern:**
```verilog
assign wr_do = wr_en_i && !full_o;  // conservative: reject write when full
// Or if the contract allows full+read:
assign wr_do = wr_en_i && (!full_o || (rd_en_i && full_o));
```

**First divergent cycle:** the cycle where `full_o && wr_en_i && rd_en_i` — check whether count increases beyond depth.

**Prevention assertion:**
```systemverilog
property p_no_overflow;
  @(posedge clk_i) disable iff (rst_i)
    !(wr_do && full_o);
endproperty
assert property (p_no_overflow);
```

**Regression test:** fill FIFO to depth, assert simultaneous write+read, verify count does not exceed depth.

---

### B2: FIFO accepts read when empty

**Category:** boundary
**Frequency:** medium
**Applies to:** any FIFO

**Symptom:** FIFO returns stale or garbage data when empty.

**Root cause:** `rd_do` does not check `empty_o`, or `empty_o` is derived incorrectly.

**Trigger conditions:** read is asserted when count is zero.

**Bug code pattern:**
```verilog
assign rd_do = rd_en_i;  // BUG: no empty check
```

**Correct code pattern:**
```verilog
assign rd_do = rd_en_i && !empty_o;
```

**First divergent cycle:** the cycle where `empty_o && rd_en_i` — check whether `rdata_o` changes or count goes negative.

**Prevention assertion:**
```systemverilog
property p_no_underflow;
  @(posedge clk_i) disable iff (rst_i)
    !(rd_do && empty_o);
endproperty
assert property (p_no_underflow);
```

**Regression test:** read from empty FIFO, verify no state change.

---

### B3: Counter off-by-one at full/empty boundary

**Category:** boundary
**Frequency:** high
**Applies to:** any FIFO or counter-based occupancy tracker

**Symptom:** FIFO reports full one entry early or accepts one write too many.

**Root cause:** the full/empty comparison uses the wrong value (e.g., `count_o == DEPTH - 1` instead of `count_o == DEPTH`), or the count update and flag derivation use different timing.

**Trigger conditions:** the counter reaches the boundary value.

**Bug code pattern:**
```verilog
assign full_o = (count_o == DEPTH - 1);  // BUG: off by one
```

**Correct code pattern:**
```verilog
assign full_o  = (count_o == DEPTH);
assign empty_o = (count_o == 0);
```

**First divergent cycle:** the cycle where count reaches `DEPTH - 1` — check whether `full_o` asserts prematurely.

**Prevention assertion:**
```systemverilog
property p_full_at_depth;
  @(posedge clk_i) disable iff (rst_i)
    (count_o == DEPTH) |-> full_o;
endproperty
assert property (p_full_at_depth);
```

**Regression test:** write exactly DEPTH items, verify full_o asserts on the last write, not before.

---

### B4: Simultaneous read/write count error

**Category:** boundary
**Frequency:** medium
**Applies to:** any FIFO with simultaneous read/write support

**Symptom:** count drifts — increases when it should stay constant, or vice versa.

**Root cause:** the count update case statement does not handle the simultaneous read+write case correctly, or uses blocking assignment while pointers use nonblocking.

**Trigger conditions:** `wr_do && rd_do` on the same cycle.

**Bug code pattern:**
```verilog
// BUG: only handles one-at-a-time
if (wr_do) count_o <= count_o + 1;
if (rd_do) count_o <= count_o - 1;
// Both branches execute on same cycle with nonblocking: net +0, which is correct
// But if using blocking: second assignment overwrites first
```

**Correct code pattern:**
```verilog
case ({wr_do, rd_do})
  2'b10:   count_o <= count_o + 1;
  2'b01:   count_o <= count_o - 1;
  2'b11:   count_o <= count_o;  // simultaneous: net zero
  default: count_o <= count_o;
endcase
```

**First divergent cycle:** the cycle where both `wr_do` and `rd_do` are true — check count on the next edge.

**Prevention assertion:**
```systemverilog
property p_simultaneous_rw_count_stable;
  @(posedge clk_i) disable iff (rst_i)
    (wr_do && rd_do) |=> $stable(count_o);
endproperty
assert property (p_simultaneous_rw_count_stable);
```

**Regression test:** fill FIFO half, assert simultaneous write+read repeatedly, verify count stays constant.

---

## Reset patterns

### R1: FSM reset to wrong state

**Category:** reset
**Frequency:** medium
**Applies to:** any FSM

**Symptom:** controller appears busy or produces a done pulse immediately after reset, with no input stimulus.

**Root cause:** the reset clause assigns the state register to a non-idle state (e.g., BUSY instead of IDLE).

**Trigger conditions:** reset deassertion.

**Bug code pattern:**
```verilog
always @(posedge clk_i) begin
  if (rst_i)
    state_q <= BUSY;  // BUG: should be IDLE
  else
    state_q <= state_d;
end
```

**Correct code pattern:**
```verilog
always @(posedge clk_i) begin
  if (rst_i)
    state_q <= IDLE;
  else
    state_q <= state_d;
end
```

**First divergent cycle:** the first cycle after `rst_i` deasserts — check `state_q` value.

**Prevention assertion:**
```systemverilog
property p_fsm_reset_to_idle;
  @(posedge clk_i) rst_i |-> (state_q == IDLE);
endproperty
assert property (p_fsm_reset_to_idle);
```

**Regression test:** assert reset, release, check state is IDLE and outputs are idle for one cycle with no input.

---

### R2: Valid-like output not cleared on reset

**Category:** reset
**Frequency:** medium
**Applies to:** any module with valid/ready output

**Symptom:** downstream sees a spurious valid item immediately after reset release.

**Root cause:** the reset clause clears the state register but not the `valid_o` output register, or `valid_o` is derived from a register that is not reset.

**Trigger conditions:** reset deassertion with downstream ready.

**Bug code pattern:**
```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    state_q <= IDLE;
    // BUG: valid_o not cleared
  end else begin
    valid_o <= next_valid;
  end
end
```

**Correct code pattern:**
```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    state_q <= IDLE;
    valid_o <= 1'b0;
  end else begin
    valid_o <= next_valid;
  end
end
```

**First divergent cycle:** the first cycle after reset release — check `valid_o`.

**Prevention assertion:**
```systemverilog
property p_valid_cleared_on_reset;
  @(posedge clk_i) rst_i |-> !valid_o;
endproperty
assert property (p_valid_cleared_on_reset);
```

**Regression test:** assert reset, release, check `valid_o` is low for at least one cycle.

---

### R3: Async reset deassertion not synchronized

**Category:** reset
**Frequency:** low
**Applies to:** any module using asynchronous reset

**Symptom:** metastability-like behavior on reset release, intermittent failures.

**Root cause:** the asynchronous reset signal is deasserted near a clock edge, violating the recovery/removal time of the flip-flop.

**Trigger conditions:** reset deassertion coincides with the active clock edge.

**Bug code pattern:**
```verilog
always @(posedge clk_i or posedge rst_ni) begin
  if (!rst_ni)
    state_q <= IDLE;
  else
    state_q <= state_d;
end
// rst_ni is not synchronized to clk_i
```

**Correct code pattern:**
```verilog
// Synchronize reset deassertion
reg rst_ni_sync1, rst_ni_sync2;
always @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    rst_ni_sync1 <= 1'b0;
    rst_ni_sync2 <= 1'b0;
  end else begin
    rst_ni_sync1 <= 1'b1;
    rst_ni_sync2 <= rst_ni_sync1;
  end
end

always @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni)
    state_q <= IDLE;
  else
    state_q <= state_d;
end
```

**First divergent cycle:** random — depends on when reset deasserts relative to clock edge.

**Prevention assertion:** no SVA for this — requires CDC review tool or static timing analysis.

**Regression test:** toggle reset deassertion timing relative to clock edge, verify no metastability.

---

## Pipeline patterns

### P1: Valid advances during stall

**Category:** pipeline
**Frequency:** high
**Applies to:** any stallable pipeline stage

**Symptom:** valid data appears at the output one cycle after a stall, even though no new input was accepted.

**Root cause:** the stall condition gates the data update but not the valid update.

**Trigger conditions:** `stall_i` is asserted while `valid_i` is also asserted.

**Bug code pattern:**
```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    valid_o <= 1'b0;
  end else if (flush_i) begin
    valid_o <= 1'b0;
  end else begin
    valid_o <= valid_i;       // BUG: valid advances even during stall
    if (!stall_i)
      data_o <= data_i;
  end
end
```

**Correct code pattern:**
```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    valid_o <= 1'b0;
    data_o  <= {DATA_W{1'b0}};
  end else if (flush_i) begin
    valid_o <= 1'b0;
  end else if (!stall_i) begin
    valid_o <= valid_i;
    data_o  <= data_i;
  end
  // When stall_i: valid_o and data_o hold
end
```

**First divergent cycle:** the cycle after stall is asserted — check whether `valid_o` changes without a matching `data_o` update.

**Prevention assertion:**
```systemverilog
property p_valid_holds_during_stall;
  @(posedge clk_i) disable iff (rst_i)
    (stall_i && !flush_i) |=> $stable(valid_o);
endproperty
assert property (p_valid_holds_during_stall);
```

**Regression test:** send one item, assert stall for 3 cycles, verify `valid_o` and `data_o` hold.

---

### P2: Flush and stall priority error

**Category:** pipeline
**Frequency:** medium
**Applies to:** any pipeline with both flush and stall

**Symptom:** data is not flushed when both flush and stall are asserted simultaneously, or data leaks through during flush.

**Root cause:** the RTL checks `stall_i` before `flush_i`, so stall blocks the flush. The correct priority is flush wins over stall.

**Trigger conditions:** `flush_i && stall_i` on the same cycle.

**Bug code pattern:**
```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    valid_o <= 1'b0;
  end else if (!stall_i) begin   // BUG: stall checked before flush
    if (flush_i)
      valid_o <= 1'b0;
    else begin
      valid_o <= valid_i;
      data_o  <= data_i;
    end
  end
end
```

**Correct code pattern:**
```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    valid_o <= 1'b0;
    data_o  <= {DATA_W{1'b0}};
  end else if (flush_i) begin    // flush wins
    valid_o <= 1'b0;
  end else if (!stall_i) begin
    valid_o <= valid_i;
    data_o  <= data_i;
  end
end
```

**First divergent cycle:** the cycle where both `flush_i` and `stall_i` are high — check `valid_o` on the next edge.

**Prevention assertion:**
```systemverilog
property p_flush_wins_over_stall;
  @(posedge clk_i) disable iff (rst_i)
    (flush_i && stall_i) |=> !valid_o;
endproperty
assert property (p_flush_wins_over_stall);
```

**Regression test:** assert both flush and stall, verify `valid_o` clears.

---

### P3: Data/control misalignment across pipeline stages

**Category:** pipeline
**Frequency:** medium
**Applies to:** multi-stage pipelines

**Symptom:** output data does not match the expected transaction, or sideband fields belong to a different beat.

**Root cause:** data and control (valid, sideband, last, keep) are not gated by the same enable condition, so they advance at different rates.

**Trigger conditions:** a stall or bubble occurs mid-pipeline.

**Bug code pattern:**
```verilog
// Stage 1
always @(posedge clk_i) begin
  if (!stall_i) begin
    valid_s1 <= valid_i;
    data_s1  <= data_i;
  end
  // BUG: sideband always advances
  sideband_s1 <= sideband_i;
end
```

**Correct code pattern:**
```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    valid_s1 <= 1'b0;
  end else if (!stall_i) begin
    valid_s1    <= valid_i;
    data_s1     <= data_i;
    sideband_s1 <= sideband_i;
  end
end
```

**First divergent cycle:** the cycle after a stall — check whether sideband fields match the data they accompany.

**Prevention assertion:**
```systemverilog
property p_sideband_aligned_with_data;
  @(posedge clk_i) disable iff (rst_i)
    valid_s1 |-> /* sideband fields match expected transaction */;
endproperty
```

**Regression test:** stall mid-pipeline, verify all fields (data, sideband, last, keep) hold together.

---

## Protocol patterns

### P4: AXI completion on last W beat, not B response

**Category:** protocol
**Frequency:** high
**Applies to:** any AXI write master or DMA

**Symptom:** DMA reports completion before the write response arrives. If B response is delayed or returns an error, the completion is premature.

**Root cause:** the completion signal is asserted when the last W beat is accepted (`wvalid && wready && wlast`), without waiting for the B response.

**Trigger conditions:** the slave delays the B response or returns a non-OKAY BRESP.

**Bug code pattern:**
```verilog
// BUG: completion on last W beat
assign done = wvalid && wready && wlast;
```

**Correct code pattern:**
```verilog
// Track outstanding write responses
reg [7:0] outstanding_w;
always @(posedge clk_i) begin
  if (rst_i)
    outstanding_w <= 0;
  else begin
    case ({aw_valid && aw_ready, b_valid && b_ready})
      2'b10: outstanding_w <= outstanding_w + 1;
      2'b01: outstanding_w <= outstanding_w - 1;
      2'b11: outstanding_w <= outstanding_w;  // simultaneous
      default: ;
    endcase
  end
end
assign done = all_w_sent && (outstanding_w == 0) && b_valid && b_ready;
```

**First divergent cycle:** the cycle after the last W beat is accepted — check whether done asserts before B arrives.

**VCD detection:**
```bash
python scripts/vcd_extract.py dump.vcd --signals wvalid,wready,wlast,bvalid,bready,done
# Find the timestamp where WLAST fires (wvalid=1, wready=1, wlast=1)
# Check if 'done' asserts at the same timestamp or before bvalid=1, bready=1
```
If `done` goes high before `bvalid=1 && bready=1`, this pattern is violated.

**Prevention assertion:**
```systemverilog
property p_completion_after_b_response;
  @(posedge clk_i) disable iff (rst_i)
    done |-> (outstanding_w == 0);
endproperty
assert property (p_completion_after_b_response);
```

**Regression test:** delay B response by 5 cycles after last W beat, verify done does not assert early.

---

### P5: AXI AW/W channel order assumption

**Category:** protocol
**Frequency:** medium
**Applies to:** any AXI slave or interconnect

**Symptom:** write data is lost or applied to the wrong address.

**Root cause:** the slave assumes AW always arrives before W, but the AXI protocol allows them in either order.

**Trigger conditions:** W arrives before AW.

**Bug code pattern:**
```verilog
// BUG: assumes AW arrives first
always @(posedge clk_i) begin
  if (aw_valid && aw_ready) begin
    addr_q <= aw_addr;
  end
  if (w_valid && w_ready) begin
    mem[addr_q] <= w_data;  // addr_q may not be valid yet
  end
end
```

**Correct code pattern:**
```verilog
// Buffer both independently, apply when both are valid
reg aw_pending, w_pending;
reg [ADDR_W-1:0] aw_addr_q;
reg [DATA_W-1:0] w_data_q;

always @(posedge clk_i) begin
  if (rst_i) begin
    aw_pending <= 0;
    w_pending  <= 0;
  end else begin
    if (aw_valid && aw_ready && !aw_pending) begin
      aw_addr_q <= aw_addr;
      aw_pending <= 1;
    end
    if (w_valid && w_ready && !w_pending) begin
      w_data_q <= w_data;
      w_pending <= 1;
    end
    if (aw_pending && w_pending) begin
      mem[aw_addr_q] <= w_data_q;
      aw_pending <= 0;
      w_pending  <= 0;
    end
  end
end
```

**First divergent cycle:** the cycle where W arrives before AW — check whether the write uses a stale address.

**Prevention assertion:** check that the write occurs with the correct address regardless of channel order.

**Regression test:** send W before AW, verify write lands at the correct address.

---

### P6: AXI multi-ID response ordering not tracked

**Category:** protocol
**Frequency:** medium
**Applies to:** any AXI master with multiple outstanding IDs

**Symptom:** responses for different IDs are mixed, or a second burst for the same ID starts before the first completes.

**Root cause:** the master does not track per-ID outstanding state, allowing responses to be consumed out of order or a new command to overwrite in-flight state.

**Trigger conditions:** two bursts with different IDs are outstanding, and responses arrive out of order.

**Bug code pattern:**
```verilog
// BUG: single outstanding counter, no per-ID tracking
reg [7:0] outstanding;
// Cannot distinguish which ID a response belongs to
```

**Correct code pattern:**
```verilog
// Per-ID tracking
reg [7:0] outstanding_per_id [0:MAX_ID];
// Block new command for an already-active ID
wire id_blocked = outstanding_per_id[ar_id] > 0;
```

**First divergent cycle:** the cycle where a response arrives for an ID that has no outstanding burst, or a new command starts for an active ID.

**Prevention assertion:**
```systemverilog
property p_no_response_for_inactive_id;
  @(posedge clk_i) disable iff (rst_i)
    (r_valid && r_ready && r_last) |-> (outstanding_per_id[r_id] > 0);
endproperty
assert property (p_no_response_for_inactive_id);
```

**Regression test:** issue two bursts with different IDs, deliver responses out of order, verify no data corruption.

---

### P7: APB register update during wait state

**Category:** protocol
**Frequency:** medium
**Applies to:** any APB slave

**Symptom:** register value changes during a PREADY=0 cycle, or multiple updates occur for one access.

**Root cause:** the slave updates registers whenever PSEL and PENABLE are high, regardless of PREADY.

**Trigger conditions:** the slave inserts wait states (PREADY=0).

**Bug code pattern:**
```verilog
// BUG: updates on PSEL && PENABLE regardless of PREADY
always @(posedge clk_i) begin
  if (psel_i && penable_i) begin
    reg_q <= pwdata_i;  // updates even when PREADY=0
  end
end
```

**Correct code pattern:**
```verilog
always @(posedge clk_i) begin
  if (psel_i && penable_i && pready_o) begin
    reg_q <= pwdata_i;
  end
end
```

**First divergent cycle:** a cycle where PSEL=1, PENABLE=1, PREADY=0 — check whether the register changes.

**Prevention assertion:**
```systemverilog
property p_no_update_during_wait;
  @(posedge clk_i)
    (psel_i && penable_i && !pready_o) |=> $stable(reg_q);
endproperty
assert property (p_no_update_during_wait);
```

**Regression test:** insert 3 wait states, verify register does not update until PREADY=1.

---

### P8: AHB address/data phase misalignment

**Category:** protocol
**Frequency:** medium
**Applies to:** any AHB-Lite slave

**Symptom:** write data is stored at the wrong address, or read data returns from the wrong address.

**Root cause:** the slave uses the current-cycle HADDR for the data phase, but AHB-Lite data belongs to the previous address phase.

**Trigger conditions:** back-to-back transfers with different addresses.

**Bug code pattern:**
```verilog
// BUG: uses current HADDR for data phase
always @(posedge clk_i) begin
  if (hwrite_i && hready_i)
    mem[haddr_i] <= hwdata_i;  // haddr_i may already be the next address
end
```

**Correct code pattern:**
```verilog
// Register address from address phase
reg [ADDR_W-1:0] addr_phase_q;
always @(posedge clk_i) begin
  if (hready_i)
    addr_phase_q <= haddr_i;
end
always @(posedge clk_i) begin
  if (hwrite_i && hready_i)
    mem[addr_phase_q] <= hwdata_i;  // use registered address
end
```

**First divergent cycle:** the cycle after a back-to-back transfer — check whether the write uses the address from the current or previous phase.

**Prevention assertion:** check that the write address matches the registered address phase, not the current HADDR.

**Regression test:** back-to-back writes to different addresses, verify both land correctly.

---

## Counter and FSM patterns

### C1: Counter overflow/underflow not protected

**Category:** counter
**Frequency:** high
**Applies to:** any counter (occupancy, outstanding, beat, credit)

**Symptom:** counter wraps around, causing FIFO to report wrong full/empty, or outstanding counter to lose track.

**Root cause:** the counter has no saturation or overflow check, and the width is just enough for the expected range.

**Trigger conditions:** more writes than expected, or more responses than expected.

**Bug code pattern:**
```verilog
// BUG: no overflow protection
always @(posedge clk_i) begin
  if (wr_do) count_o <= count_o + 1;
  if (rd_do) count_o <= count_o - 1;
  // If count_o reaches max and wr_do fires, it wraps to 0
end
```

**Correct code pattern:**
```verilog
always @(posedge clk_i) begin
  if (rst_i) begin
    count_o <= 0;
  end else begin
    case ({wr_do && !full_o, rd_do && !empty_o})
      2'b10: count_o <= count_o + 1;
      2'b01: count_o <= count_o - 1;
      default: count_o <= count_o;
    endcase
  end
end
```

**First divergent cycle:** the cycle where the counter wraps — check whether full_o or empty_o changes incorrectly.

**Prevention assertion:**
```systemverilog
property p_no_counter_overflow;
  @(posedge clk_i) disable iff (rst_i)
    (count_o == DEPTH) |-> !wr_do;
endproperty
assert property (p_no_counter_overflow);
```

**Regression test:** drive the counter to its maximum and minimum, verify no wrap.

---

### C2: FSM illegal state not recovered

**Category:** state-machine
**Frequency:** low
**Applies to:** any FSM with encoded states

**Symptom:** controller gets stuck in an undefined state and never recovers.

**Root cause:** the combinational case statement does not have a default branch, or the default branch does not transition to a known state.

**Trigger conditions:** a radiation event, simulation X-propagation, or a coding error causes the state register to hold an illegal value.

**Bug code pattern:**
```verilog
// BUG: no default branch
always @(*) begin
  case (state_q)
    IDLE: begin ... end
    BUSY: begin ... end
    DONE: begin ... end
    // missing default: state_d = IDLE
  endcase
end
```

**Correct code pattern:**
```verilog
always @(*) begin
  state_d = IDLE;  // default
  case (state_q)
    IDLE: begin ... end
    BUSY: begin ... end
    DONE: begin ... end
    default: state_d = IDLE;
  endcase
end
```

**First divergent cycle:** the cycle where `state_q` holds an illegal value — check whether `state_d` transitions to a known state.

**Prevention assertion:**
```systemverilog
property p_fsm_legal_state;
  @(posedge clk_i) disable iff (rst_i)
    state_q inside {IDLE, BUSY, DONE};
endproperty
assert property (p_fsm_legal_state);
```

**Regression test:** force `state_q` to an illegal value, verify it recovers to IDLE within one cycle.

---

### C3: Combinational case missing default (latch inference)

**Category:** state-machine
**Frequency:** high
**Applies to:** any combinational always block

**Symptom:** synthesis tool infers latches, causing unexpected hold behavior and lint warnings.

**Root cause:** the combinational case or if-else chain does not assign a value to every output in every branch.

**Trigger conditions:** synthesis or lint tool processes the code.

**Bug code pattern:**
```verilog
// BUG: no default for out_a
always @(*) begin
  case (sel_i)
    2'b00: out_a = a;
    2'b01: out_a = b;
    // 2'b10 and 2'b11 not covered: latch inferred
  endcase
end
```

**Correct code pattern:**
```verilog
always @(*) begin
  out_a = a;  // default
  case (sel_i)
    2'b00: out_a = a;
    2'b01: out_a = b;
    2'b10: out_a = c;
    default: out_a = d;
  endcase
end
```

**First divergent cycle:** not a simulation issue — detected by lint or synthesis.

**Prevention assertion:** no SVA — use lint tool. Add a coding rule: "every combinational block must assign defaults before conditional branches."

**Regression test:** run lint, verify no latch warnings.

---

### SM1: Combinational `_d` block assigns multi-bit datapath values

**Category:** state-machine
**Frequency:** high
**Applies to:** any FSM with multi-bit registers (counters, addresses, data lengths, strobes)

**Symptom:** the FSM's combinational block (`always @(*)`) directly computes and assigns multi-bit values like addresses, counters, lengths, or strobes using `_d` suffix signals. This violates the single-bit control rule — the FSM becomes a monolithic control+datapath block that is hard to audit, reuse, or verify independently.

**Exception:** `state_d` (the FSM next-state register) is always assigned in the FSM combinational block — this is correct and expected in two-process FSMs. The rule targets datapath `_d` signals (counters, addresses, data, strobes), not the state register itself. If the only multi-bit `_d` signal in the FSM block is `state_d`, the design is compliant.

**Scope:** SM1/SM2 apply only to designs with an FSM (a `case(state_q)` combinational block). Designs using pure combinational logic with registered outputs (e.g., arbiters, priority encoders, combinational datapaths) are not FSMs and are exempt from SM1/SM2. The multi-bit output register (`grant_q`, `data_q`) is updated in a synchronous block gated by a single-bit enable — this is the standard registered-output pattern, not an FSM violation.

**Root cause:** the `_d` suffix is conventionally used for "next-state" signals in two-process FSMs. The LLM extends this convention to multi-bit datapath registers, treating `addr_d = cmd_addr_i` or `block_cnt_d = block_cnt_q - 1` as legitimate "next-state logic" inside the FSM's combinational block. The suffix makes the violation look idiomatic.

**Trigger conditions:** any module where the FSM needs to load, increment, or compute a multi-bit value (address, counter, length, strobe mask). The LLM puts the computation in the `always @(*)` case statement under the appropriate state.

**Bug code pattern:**
```verilog
// BUG: FSM combinational block computes multi-bit values directly
always @(*) begin
    state_d = state_q;
    block_cnt_d = block_cnt_q;     // 24-bit — NOT a single-bit control
    rd_addr_d = rd_addr_q;         // 32-bit — NOT a single-bit control
    rd_cmd_len_d = 8'd0;           // 8-bit — NOT a single-bit control

    case (state_q)
        S_LOAD: begin
            block_cnt_d = total_beats[31:8];   // multi-bit computation in FSM
            rd_addr_d = cmd_src_addr_i;         // multi-bit assignment in FSM
            rd_cmd_len_d = total_beats[7:0] - 1; // multi-bit arithmetic in FSM
        end
        S_SEND: begin
            if (rd_cmd_ready_i) begin
                block_cnt_d = block_cnt_q - 24'd1;  // multi-bit arithmetic in FSM
                rd_addr_d = rd_addr_q + 256;         // multi-bit arithmetic in FSM
            end
        end
    endcase
end
```

**Correct code pattern:**
```verilog
// FSM: outputs ONLY single-bit enables
always @(*) begin
    state_d = state_q;
    load_cmd = 1'b0;       // single-bit
    incr_addr = 1'b0;      // single-bit
    issue_cmd = 1'b0;      // single-bit

    case (state_q)
        S_LOAD: begin
            load_cmd = 1'b1;
            state_d = S_SEND;
        end
        S_SEND: begin
            issue_cmd = 1'b1;
            if (rd_cmd_ready_i) begin
                incr_addr = 1'b1;
                if (block_cnt_q == 24'd1)
                    state_d = S_DONE;
            end
        end
        default: state_d = S_IDLE;
    endcase
end

// Datapath: multi-bit registers updated in synchronous block, gated by enables
always @(posedge clk_i) begin
    if (rst_i) begin
        block_cnt_q <= 24'd0;
        rd_addr_q <= {ADDR_WIDTH{1'b0}};
    end else if (load_cmd) begin
        block_cnt_q <= total_beats[31:8];
        rd_addr_q <= cmd_src_addr_i;
    end else if (incr_addr) begin
        block_cnt_q <= block_cnt_q - 24'd1;
        rd_addr_q <= rd_addr_q + 256;
    end
end
```

**First divergent cycle:** the cycle where the FSM enters S_LOAD or S_SEND — inspect the combinational block and count multi-bit assignments. Any `*_d = <expression>` where the target is wider than 1 bit is a violation.

**Prevention assertion:** no SVA — use a code review rule. Scan every `always @(*)` block: if any assignment target is wider than 1 bit AND the assignment is inside a `case` statement that also assigns `state_d`, the block violates single-bit control.

**Regression test:** code review. Count multi-bit `*_d` assignments inside the FSM combinational block. Zero is the pass criterion.

---

### SM2: Multi-bit `_d` signals in separate combinational block (the "shadow datapath")

**Category:** state-machine
**Frequency:** high
**Applies to:** any FSM module with multi-bit registers that uses two-process style

**Symptom:** the module has two `always @(*)` blocks — one for FSM state transitions + single-bit outputs, and a second one that computes multi-bit `_d` signals (`w_beat_cnt_d`, `b_outstanding_d`, `addr_d`, etc.) gated on `state_q` or handshake fire signals. The second block looks clean because it's "separate from the FSM", but it's still combinational logic gated on state — the same violation as SM1, just split across two blocks.

**Root cause:** the LLM reads the skill's "two-process" rule and interprets it as "one `always @(posedge clk)` + one `always @(*)`". When the module has both FSM control and datapath registers, the LLM creates a second `always @(*)` for the multi-bit `_d` signals and considers this acceptable because it's "not in the FSM block". But the second block is still combinational logic that depends on state and handshakes — it should be synchronous.

**Trigger conditions:** any module where the FSM controls multi-bit registers (beat counters, outstanding counters, burst length registers). The LLM creates a "shadow datapath" combinational block that computes `_d` values, then registers them in a separate `always @(posedge clk)`.

**Bug code pattern:**
```verilog
// Block 1: FSM — looks correct (single-bit outputs)
always @(*) begin
    state_d = state_q;
    aw_pending_d = aw_pending_q;  // 1-bit, OK
    w_active_d = w_active_q;      // 1-bit, OK
    comp_push_d = 1'b0;           // 1-bit, OK
    case (state_q)
        ST_LOAD: begin aw_pending_d = 1'b1; w_active_d = 1'b1; state_d = ST_SEND; end
        ST_SEND: if (w_fire && w_beat_cnt_q == 0) begin w_active_d = 1'b0; comp_push_d = 1'b1; state_d = ST_IDLE; end
        default: state_d = ST_IDLE;
    endcase
end

// Block 2: "shadow datapath" — BUG: multi-bit combinational logic gated on state
always @(*) begin
    w_beat_cnt_d = w_beat_cnt_q;      // 8-bit
    b_outstanding_d = b_outstanding_q; // 8-bit
    comp_burst_cnt_d = comp_burst_cnt_q; // 8-bit

    if (state_q == ST_LOAD)
        w_beat_cnt_d = cmd_len_q;     // state-gated multi-bit assignment
    else if (state_q == ST_SEND && w_fire)
        w_beat_cnt_d = w_beat_cnt_q - 1; // state-gated multi-bit arithmetic

    if (aw_fire & ~b_fire)
        b_outstanding_d = b_outstanding_q + 1; // handshake-gated multi-bit
end

// Block 3: registers — looks clean but is just hiding the problem
always @(posedge clk_i) begin
    w_beat_cnt_q <= w_beat_cnt_d;
    b_outstanding_q <= b_outstanding_d;
end
```

**Correct code pattern:**
```verilog
// FSM: single-bit enables only
always @(*) begin
    state_d = state_q;
    load_beat_cnt = 1'b0;
    dec_beat_cnt = 1'b0;
    aw_pending_d = 1'b0;
    w_active_d = 1'b0;
    comp_push_d = 1'b0;

    case (state_q)
        ST_LOAD: begin
            load_beat_cnt = 1'b1;   // single-bit enable
            aw_pending_d = 1'b1;
            w_active_d = 1'b1;
            state_d = ST_SEND;
        end
        ST_SEND: begin
            if (w_fire) begin
                dec_beat_cnt = 1'b1; // single-bit enable
                if (w_beat_cnt_q == 0) begin
                    w_active_d = 1'b0;
                    comp_push_d = 1'b1;
                    state_d = ST_IDLE;
                end
            end
        end
        default: state_d = ST_IDLE;
    endcase
end

// Datapath: synchronous, gated by single-bit enables
always @(posedge clk_i) begin
    if (rst_i) begin
        w_beat_cnt_q <= 8'd0;
    end else if (load_beat_cnt) begin
        w_beat_cnt_q <= cmd_len_q;
    end else if (dec_beat_cnt) begin
        w_beat_cnt_q <= w_beat_cnt_q - 8'd1;
    end
end

// Outstanding counter: independent synchronous logic (not FSM-gated)
always @(posedge clk_i) begin
    if (rst_i)
        b_outstanding_q <= 8'd0;
    else if (aw_fire & ~b_fire)
        b_outstanding_q <= b_outstanding_q + 8'd1;
    else if (~aw_fire & b_fire)
        b_outstanding_q <= b_outstanding_q - 8'd1;
end
```

**First divergent cycle:** the cycle where the second `always @(*)` block evaluates. Inspect: if any `_d` target is wider than 1 bit AND the assignment is gated on `state_q` or a handshake fire signal, it's a violation.

**Prevention assertion:** no SVA — use a code review rule. If a module has two `always @(*)` blocks and the second one computes multi-bit `_d` values, merge the enable signals into the FSM block and move the multi-bit computation to synchronous `always @(posedge clk)` blocks.

**Regression test:** code review. Every multi-bit register must have its next-value computed either (a) inline in its own `always @(posedge clk)` block, or (b) in a dedicated combinational block that is NOT gated on FSM state. Zero multi-bit `_d` signals gated on `state_q` is the pass criterion.

---

## CDC patterns

### D1: Multi-bit bus synchronized with independent flops

**Category:** handshake
**Frequency:** high
**Applies to:** any multi-bit signal crossing clock domains

**Symptom:** bits of the bus arrive at different cycles, causing transient incorrect values.

**Root cause:** each bit is independently synchronized, but the bits change at different times relative to the destination clock.

**Trigger conditions:** multi-bit value changes while being sampled by destination clock.

**Bug code pattern:**
```verilog
// BUG: independent 2-flop sync per bit
always @(posedge clk_b) begin
  sync_0 <= data_a;
  sync_1 <= sync_0;  // each bit may arrive on different cycles
end
```

**Correct code pattern:**
```verilog
// Use gray coding, handshake, or async FIFO for multi-bit CDC
// Gray coding for counters:
wire [3:0] gray_a = bin_a ^ (bin_a >> 1);
always @(posedge clk_b) begin
  gray_sync_0 <= gray_a;
  gray_sync_1 <= gray_sync_0;
  bin_b <= gray_to_bin(gray_sync_1);
end
```

**First divergent cycle:** the cycle where destination clock samples a partially-updated multi-bit value.

**Prevention assertion:**
```systemverilog
// Flag any multi-bit signal crossing domains without gray/handshake
assert property (@(posedge clk_b) !$changed(data_a, @(posedge clk_b)));
```

**Regression test:** change data_a while clk_b is running, verify data_b never shows a transient incorrect value.

---

### D2: Async FIFO gray code pointer violation

**Category:** handshake
**Frequency:** medium
**Applies to:** async FIFO implementations

**Symptom:** FIFO shows full when empty, or vice versa; data corruption at boundary.

**Root cause:** gray code conversion is incorrect (not a single-bit change between adjacent values) or pointer width is wrong.

**Trigger conditions:** pointer wraps around the FIFO depth boundary.

**Bug code pattern:**
```verilog
// BUG: not gray code — multiple bits change at wrap
assign gray_ptr = bin_ptr ^ (bin_ptr >> 1);
// If bin_ptr width is wrong, gray code wraps with multi-bit change
```

**Correct code pattern:**
```verilog
// Ensure pointer width matches address space + 1 bit for full/empty
reg [ADDR_W:0] bin_ptr;  // one extra bit for wrap detection
wire [ADDR_W:0] gray_ptr = bin_ptr ^ (bin_ptr >> 1);
```

**First divergent cycle:** the cycle where the pointer wraps from max to 0.

**Prevention assertion:**
```systemverilog
// Check gray code transitions have at most 1-bit change
assert property (@(posedge clk) $countones(gray_ptr ^ $past(gray_ptr)) <= 1);
```

**Regression test:** fill FIFO to depth-1, write one more, verify full flag; then read all, verify empty flag.

---

## Memory patterns

### M1: Write-during-read hazard on inferred RAM

**Category:** boundary
**Frequency:** medium
**Applies to:** inferred block RAM with simultaneous read and write to same address

**Symptom:** read returns old data or new data inconsistently across simulation and synthesis.

**Root cause:** the RTL does not specify read-during-write behavior, leaving it tool-dependent.

**Trigger conditions:** simultaneous read and write to the same address.

**Bug code pattern:**
```verilog
// BUG: no read-during-write policy
always @(posedge clk) begin
  if (wen) mem[addr] <= wdata;
  rdata <= mem[addr];  // what does this return if wen && same addr?
end
```

**Correct code pattern:**
```verilog
// Option 1: return new data (write-first)
always @(posedge clk) begin
  if (wen) mem[addr] <= wdata;
  rdata <= wen ? wdata : mem[addr];
end

// Option 2: return old data (read-first)
always @(posedge clk) begin
  rdata <= mem[addr];
  if (wen) mem[addr] <= wdata;
end
```

**First divergent cycle:** the cycle of simultaneous read-write to the same address.

**Prevention assertion:**
```systemverilog
// Document the chosen policy
assert property (@(posedge clk) (wen && addr == raddr) |-> (rdata == wdata)); // write-first
```

**Regression test:** write to address, read same address in same cycle, verify expected data.

---

## Arbitration patterns

### A1: Arbiter grant not stable under backpressure

**Category:** handshake
**Frequency:** medium
**Applies to:** any arbiter driving a ready/valid output

**Symptom:** grant changes while valid is high and downstream is not ready, causing data misrouting.

**Root cause:** arbiter re-arbitrates on every cycle regardless of output backpressure.

**Trigger conditions:** downstream deasserts ready while arbiter has granted a requester.

**Bug code pattern:**
```verilog
// BUG: re-arbitrates every cycle
always @(*) begin
  grant = 0;
  if (req[0]) grant = 3'b001;
  else if (req[1]) grant = 3'b010;
  else if (req[2]) grant = 3'b100;
end
```

**Correct code pattern:**
```verilog
// Hold grant until transfer completes
always @(posedge clk) begin
  if (rst)
    grant_q <= 0;
  else if (!valid_o || ready_i)  // re-arbitrate only on transfer
    grant_q <= next_grant;
end
```

**First divergent cycle:** the cycle where ready_i is low but grant changes.

**Prevention assertion:**
```systemverilog
assert property (@(posedge clk) (valid_o && !ready_i) |-> (grant == $past(grant)));
```

**Regression test:** assert grant, deassert ready, verify grant holds for multiple cycles.

---

## Data path patterns

### DP1: Width converter partial-word data loss

**Category:** boundary
**Frequency:** medium
**Applies to:** streaming width converters (narrow to wide)

**Symptom:** last partial word of a packet is lost or corrupted.

**Root cause:** the converter does not flush accumulated data when TLAST arrives before a full wide word is assembled.

**Trigger conditions:** packet length is not an exact multiple of the conversion ratio.

**Bug code pattern:**
```verilog
// BUG: only outputs when accumulator is full
if (accum_count == RATIO - 1) begin
  valid_o <= 1;
  data_o <= accumulated_data;
  accum_count <= 0;
end
// TLAST with partial accumulator is lost
```

**Correct code pattern:**
```verilog
// Flush on TLAST regardless of accumulator state
if (accum_count == RATIO - 1 || (tlast_i && accum_count > 0)) begin
  valid_o <= 1;
  data_o <= accumulated_data;
  // Set keep bits for valid bytes
  keep_o <= (accum_count == RATIO - 1) ? {KEEP_W{1'b1}} : partial_keep;
  last_o <= tlast_i;
  accum_count <= 0;
end
```

**First divergent cycle:** the cycle where TLAST arrives with partial accumulator.

**Prevention assertion:**
```systemverilog
// After TLAST, accumulator must be empty
assert property (@(posedge clk) tlast_i && tvalid_i |-> ##1 accum_count == 0);
```

**Regression test:** send packet with length = RATIO * N + 1, verify all data arrives.

---

### DP2: Mux select glitch during transition

**Category:** state-machine
**Frequency:** low
**Applies to:** large muxes with registered select

**Symptom:** output glitches during select transition, causing downstream errors.

**Root cause:** the mux output changes before the new select is stable, or the select path has combinational delay.

**Trigger conditions:** select signal transitions between two valid states.

**Correct code pattern:**
```verilog
// Register the mux output to absorb glitches
always @(posedge clk) begin
  if (accept_output)
    data_o <= mux_out;  // registered output
end
```

**Prevention assertion:**
```systemverilog
// Output should only change when valid
assert property (@(posedge clk) (!valid_o) |-> ($stable(data_o) || $past(!valid_o)));
```

**Regression test:** rapid select changes with valid output, verify no spurious data.

---

### F1: FIFO registered output causes one-beat data shift in protocol data paths

**Category:** data-path
**Frequency:** high
**Applies to:** any FIFO feeding a protocol data path (AXI W/R, streaming interfaces, handshake data)

**Symptom:** every data beat received by the slave is the previous beat's data. Beat 0 gets stale/garbage data, beat 1 gets beat 0's data, etc. Silent data corruption — no assertion fires, no error signal.

**Root cause:** the FIFO uses a registered read output (`rdata_q <= mem[rd_ptr]` in `always @(posedge clk)`), adding one cycle of read latency. The consumer reads data combinationally from the FIFO output (`assign wdata = fifo_rdata`), but the output register hasn't updated yet from the current read. The data is shifted by one beat.

**Trigger conditions:** any FIFO with registered output used in a data path where the consumer expects data on the same cycle as the read-enable. Common in AXI W channel, streaming data paths, and any ready/valid data path.

**Bug code pattern:**
```verilog
// FIFO with registered output (WRONG for data paths)
reg [DATA_WIDTH:0] rdata_q;
always @(posedge clk_i) begin
    if (rd_do)
        rdata_q <= mem[rd_ptr_q];  // ONE CYCLE LATENCY
end
assign rdata_o = rdata_q;

// Consumer: reads from FIFO output combinationally
assign m_axi_wdata_o = rdata_o[DATA_WIDTH-1:0];  // STALE on first beat
assign dfifo_rd_en_o = w_fire;
```

**Timeline showing the shift:**
```
Cycle N:   w_fire → dfifo_rd_en=1, rd_ptr advances
           rdata_o = rdata_q (stale — from previous read or reset)
           Slave captures STALE data
Cycle N+1: rdata_q updates with mem[rd_ptr] (the data we wanted at cycle N)
           w_fire → Slave captures data that was meant for cycle N
```

**Correct code pattern:**
```verilog
// FWFT FIFO: combinational read output (NO latency)
wire [DATA_WIDTH:0] rdata = mem[rd_ptr_q];  // combinational
assign rdata_o = rdata;
assign empty_o = (count_q == 0);

// Consumer: data is valid same cycle as empty_o deasserts
assign m_axi_wdata_o = rdata_o[DATA_WIDTH-1:0];  // VALID immediately
assign dfifo_rd_en_o = w_fire;
```

**First divergent cycle:** the first w_fire after burst start. Check whether WDATA matches the expected first beat of the transfer.

**Prevention assertion:**
```systemverilog
// On first W fire of a burst, WDATA must not be stale (check against known pattern)
property p_wdata_not_stale_on_first_beat;
    @(posedge clk_i) disable iff (rst_i)
        (m_axi_wvalid_o && m_axi_wready_i && first_beat) |->
            (m_axi_wdata_o == expected_first_beat_data);
endproperty
```

**Regression test:** send a known data pattern (e.g., incrementing 0x00, 0x01, 0x02, ...) through the DMA, verify each beat arrives correctly at the slave. Any one-beat shift is immediately visible.

---

### F2: Registered output race condition in protocol bridges

**Category:** data-path
**Frequency:** medium
**Applies to:** any protocol bridge or converter connecting to a module with registered outputs (APB slave with registered PRDATA, AXI slave with registered RDATA, etc.)

**Symptom:** bridge captures stale data from downstream module. Read data is off by one transaction, or error status is missed.

**Root cause:** the downstream module's output is registered — it updates on the same clock edge as the handshake completion (e.g., PREADY=1). The bridge samples the output on the same edge, but the registered value hasn't updated yet. The bridge gets the previous transaction's data.

**Trigger conditions:** downstream module uses registered outputs AND bridge samples on the handshake completion edge.

**Bug code pattern:**
```verilog
// BUG: sample PRDATA on same edge as PREADY=1
S_ACCESS: begin
    if (m_apb_pready_i) begin
        prdata_q <= m_apb_prdata_i;  // STALE — APB slave's register is updating NOW
        state_d  = S_RESP;
    end
end
```

**Correct code pattern:**
```verilog
// Add a dedicated sample state after ACCESS completes
S_ACCESS: begin
    if (m_apb_pready_i)
        state_d = S_RDATA;  // wait one cycle for PRDATA to stabilize
end
S_RDATA: begin
    prdata_q <= m_apb_prdata_i;  // PRDATA is now stable (registered in slave)
    state_d  = S_RESP;
end
```

**First divergent cycle:** the cycle where PREADY=1 — check whether PRDATA on the next edge matches expected data.

**Prevention assertion:**
```systemverilog
// PRDATA must be stable one cycle after PREADY
property p_prdata_stable_after_pready;
    @(posedge clk_i) disable iff (rst_i)
        (m_apb_psel_o && m_apb_penable_o && m_apb_pready_i) |=> $stable(m_apb_prdata_i);
endproperty
```

**Regression test:** read a known value from APB slave, verify RDATA matches. If the slave uses registered output, the test will fail without the extra sample state.

---

## Clock/power patterns

### CL1: Clock gating creates glitch

**Category:** reset
**Frequency:** medium
**Applies to:** any clock-gated design

**Symptom:** flip-flops receive a glitched clock edge, causing metastability or incorrect sampling.

**Root cause:** the enable signal changes while the clock is high, creating a runt pulse.

**Trigger conditions:** clock enable changes during clock high phase.

**Bug code pattern:**
```verilog
// BUG: enable can glitch the clock
wire gated_clk = clk & en;  // en changing during clk=1 creates glitch
```

**Correct code pattern:**
```verilog
// Latch enable on clock low phase
reg en_latch;
always @(*) begin
  if (!clk) en_latch = en;
end
wire gated_clk = clk & en_latch;
```

**First divergent cycle:** the cycle where enable changes during clock high.

**Prevention assertion:**
```systemverilog
assert property (@(posedge clk) en |-> ##1 en);  // simplified: enable should be stable
```

**Regression test:** toggle enable randomly, verify no glitched clock edges.

---

## Protocol patterns (additional)

### P9: AXI write data before address accepted

**Category:** protocol
**Frequency:** medium
**Applies to:** AXI write masters

**Symptom:** slave receives write data before knowing the write address, may reject or misroute.

**Root cause:** W channel starts sending before AW handshake completes.

**Trigger conditions:** WVALID asserted before AWREADY is seen.

**Bug code pattern:**
```verilog
// BUG: starts W without waiting for AW acceptance
always @(posedge clk) begin
  wvalid <= 1;  // sends data immediately
  awvalid <= 1;
end
```

**Correct code pattern:**
```verilog
// Wait for AW acceptance before starting W (or ensure slave handles out-of-order)
always @(posedge clk) begin
  if (awaccepted)
    wvalid <= 1;
end
```

**First divergent cycle:** the cycle where WVALID is high but AW has not been accepted.

**Prevention assertion:**
```systemverilog
assert property (@(posedge clk) wvalid |-> awaccepted || awvalid);
```

**Regression test:** delay AWREADY, verify W does not start prematurely.

---

### P10: AXI read data accepted without tracking outstanding beats

**Category:** protocol
**Frequency:** medium
**Applies to:** AXI read masters

**Symptom:** master accepts more R beats than expected, or misses RLAST.

**Root cause:** no counter tracking expected R beats after AR acceptance.

**Trigger conditions:** R channel delivers unexpected number of beats.

**Correct code pattern:**
```verilog
// Track expected beats
reg [7:0] r_beats_remaining;
always @(posedge clk) begin
  if (araccepted)
    r_beats_remaining <= arlen + 1;
  else if (rvalid && rready)
    r_beats_remaining <= r_beats_remaining - 1;
end
// done when r_beats_remaining == 0 after last R beat
```

**First divergent cycle:** the cycle where R beats exceed or fall short of ARLEN+1.

**Prevention assertion:**
```systemverilog
assert property (@(posedge clk) rlast |-> r_beats_remaining == 1);
```

**Regression test:** send burst with ARLEN=3, verify exactly 4 R beats accepted.

---

### P11: AXI-Lite B response not held under backpressure

**Category:** protocol
**Frequency:** medium
**Applies to:** AXI-Lite slaves

**Symptom:** slave drops BVALID before BREADY, losing the write response.

**Root cause:** BVALID is deasserted on the cycle after the write completes, regardless of BREADY.

**Trigger conditions:** downstream is not ready to accept B response.

**Correct code pattern:**
```verilog
// Hold BVALID until BREADY
always @(posedge clk) begin
  if (rst)
    bvalid <= 0;
  else if (write_accepted && !bvalid)
    bvalid <= 1;
  else if (bvalid && bready)
    bvalid <= 0;
end
```

**VCD detection:**
```bash
python scripts/vcd_extract.py dump.vcd --find-violation valid-drop --signals bvalid,bready
```
If any violation found (bvalid drops while bready=0), this pattern is triggered.

**Prevention assertion:**
```systemverilog
assert property (@(posedge clk) bvalid && !bready |-> ##1 bvalid);
```

**Regression test:** delay BREADY for 3 cycles after write, verify BVALID holds.

---

### P12: WVALID deasserted mid-burst

**Category:** protocol
**Frequency:** high
**Applies to:** any AXI write master that sources W data from a FIFO or buffer

**Symptom:** WVALID asserts for the first few beats of a write burst, then deasserts mid-burst because the data source (FIFO) empties. Slave receives an incomplete burst. May cause protocol violation, data corruption, or slave hang.

**Root cause:** WVALID is gated on data availability (`~fifo_empty`), not on burst completion. The design starts issuing W beats as soon as the first data arrives, without guaranteeing that all beats for the burst are available. If the upstream data source is slower than the W channel consumption rate, the FIFO drains mid-burst and WVALID drops.

**AXI specification reference:** IHI0022E Section A3.3.1 — "Once VALID is asserted, it must not be deasserted until the handshake occurs." For burst transfers, this means WVALID must remain asserted for every beat of the burst once the first beat is presented. There is no provision for "pause and resume" within a burst.

**Trigger conditions:** data FIFO depth < maximum burst length, or upstream read latency > downstream write throughput.

**Bug code pattern:**
```verilog
// BUG: WVALID gated on FIFO emptiness — can drop mid-burst
assign m_axi_wvalid_o = w_active_q & ~data_fifo_empty_i;

// w_active_q set when first data arrives, not when full burst is ready
always @(posedge clk_i) begin
    if (rst_i)
        w_active_q <= 1'b0;
    else if (w_fire && m_axi_wlast_o)
        w_active_q <= 1'b0;
    else if (!data_fifo_empty_i)
        w_active_q <= 1'b1;  // BUG: arms on first beat, not on burst readiness
end
```

**Correct code pattern (option 1 — FIFO depth >= max burst):**
```verilog
// If FIFO depth is guaranteed >= max burst length, the FIFO cannot drain
// mid-burst because the full burst is buffered before W starts.
// Add a parameter assertion:
initial begin
    if (C_DATA_FIFO_DEPTH < C_AXI_MAX_BURST_LEN)
        $error("Data FIFO depth must be >= max burst length");
end
// Then WVALID = w_active_q & ~fifo_empty is safe (FIFO never drains mid-burst)
```

**Correct code pattern (option 2 — burst-ready gating):**
```verilog
// Gate WVALID on burst readiness, not just data availability
wire burst_ready = (fifo_count >= expected_beats);
assign m_axi_wvalid_o = w_active_q & burst_ready;

// w_active_q only arms when the full burst is buffered
always @(posedge clk_i) begin
    if (rst_i)
        w_active_q <= 1'b0;
    else if (w_fire && m_axi_wlast_o)
        w_active_q <= 1'b0;
    else if (burst_ready && !w_active_q)
        w_active_q <= 1'b1;
end
```

**First divergent cycle:** the cycle where WVALID was high on the previous edge but is now low, while WLAST has not been asserted. Check waveform: WVALID high → low without WLAST = violation.

**VCD detection:**
```bash
python scripts/vcd_extract.py dump.vcd --signals wvalid,wlast,wready
# Find all wvalid transitions: 1->0
# For each 1->0 transition, check if wlast was 1 at the same timestamp
# If wlast=0 when wvalid drops, this is a mid-burst violation
```
Manual check: grep VCD for WVALID signal ID, find `0<wvalid_id>` lines, then check WLAST value at same timestamp.

**Prevention assertion:**
```systemverilog
// WVALID must not deassert mid-burst (before WLAST)
property p_wvalid_holds_until_wlast;
    @(posedge clk_i) disable iff (rst_i)
        (m_axi_wvalid_o && !m_axi_wready_i) |-> ##1 m_axi_wvalid_o;
endproperty
assert property (p_wvalid_holds_until_wlast);

// Once WVALID is asserted, it must stay high until WLAST fires
property p_wvalid_no_gap_in_burst;
    @(posedge clk_i) disable iff (rst_i)
        (m_axi_wvalid_o && !m_axi_wlast_o) |-> ##1 m_axi_wvalid_o;
endproperty
assert property (p_wvalid_no_gap_in_burst);
```

**Regression test:** configure FIFO depth = max_burst_len / 2. Issue a write burst. Verify WVALID stays high from first beat to WLAST. If WVALID drops mid-burst, the test fails.

---

### P13: Sequential AW→W→B FSM couples AXI write channels

**Category:** protocol
**Frequency:** high
**Applies to:** any AXI write master with burst support

**Symptom:** write engine uses a single FSM with states like S_IDLE→S_AW→S_WDATA→S_BRESP. This forces AW, W, and B to operate sequentially: the FSM blocks in S_WDATA waiting for all W beats, then blocks in S_BRESP waiting for the B response. No new AW can be issued until the entire burst (AW+W+B) completes. Throughput is limited to one burst at a time, despite the AXI protocol supporting multiple outstanding writes.

**Root cause:** the LLM copies the read engine's FSM pattern (S_IDLE→S_AR→S_RDATA) to the write engine. For reads, this pattern works because R data naturally follows AR — the FSM only needs to wait for R data to arrive. For writes, the B response may arrive long after WLAST, and the FSM should not block on B. The LLM also treats "AW→W→B" as a natural sequential flow because that's the transaction order, but AXI channels are independent — they have separate valid/ready handshakes and can overlap.

**AXI specification reference:** IHI0022E Section A3.3 — each channel has independent handshake. AW, W, and B are not required to complete in strict sequence across bursts. Multiple AW commands can be outstanding before their W data or B responses arrive.

**Trigger conditions:** any write engine that needs to support MAX_OUTSTANDING > 1, or where write throughput matters. The sequential FSM limits throughput to `1 / (AW_latency + W_latency + B_latency)` bursts per cycle, while independent controllers achieve `1 / max(AW_latency, W_throughput, B_latency)`.

**Bug code pattern:**
```verilog
// BUG: single FSM forces AW→W→B sequential operation
localparam S_IDLE  = 4'b0001;
localparam S_AW    = 4'b0010;
localparam S_WDATA = 4'b0100;
localparam S_BRESP = 4'b1000;

case (state_q)
    S_IDLE: if (cmd_valid) state_d = S_AW;
    S_AW:   if (aw_fire)   state_d = S_WDATA;  // waits for AW
    S_WDATA: if (w_fire && wlast) state_d = S_BRESP; // waits for ALL W beats
    S_BRESP: if (b_fire)   state_d = S_IDLE;    // waits for B — blocks next AW!
endcase
```

**Correct code pattern:** See `references/axi-dma/axi-dma-channel-guidelines.md` "Complete write engine module template". The key is three independent controllers:
1. AW controller: `aw_pending_q` register, fires independently when outstanding allows
2. W controller: `w_active_q` + `w_beat_cnt_q`, starts when data available, holds until WLAST
3. B counter: `b_outstanding_q`, increments on AW fire, decrements on B fire, never blocks AW or W

**First divergent cycle:** the cycle where S_BRESP is active and a new burst command is available in the FIFO but cannot be accepted because the FSM is waiting for B. Check: `cmd_valid && !cmd_ready && state_q == S_BRESP`.

**VCD detection:**
```bash
python scripts/vcd_extract.py dump.vcd --protocol axi-write
# Look for: sequential AW→W→B pattern where next AW only appears AFTER B response
# Independent controllers show overlapping: AW1, AW2, W1, W2, B1, B2
# Sequential FSM shows: AW1, W1, B1, AW2, W2, B2 (no overlap)
```
Check if `awvalid` can assert while `bvalid` is pending (outstanding > 0). If AW only appears after B completes, the channels are coupled.

**Prevention assertion:**
```systemverilog
// A new burst should not be blocked by B response wait
property p_aw_not_blocked_by_b;
    @(posedge clk_i) disable iff (rst_i)
        (cmd_valid_i && b_outstanding_q < MAX_OUTSTANDING)
        |-> ##[1:3] m_axi_awvalid_o;
endproperty
assert property (p_aw_not_blocked_by_b);
```

**Regression test:** issue 4 consecutive write bursts. Measure cycles from first AW to last B. With independent controllers, the 4 bursts should overlap (total time ≈ single burst time + 3 B latencies). With sequential FSM, total time ≈ 4 × (AW + W + B latency).

---

### R4: Async reset recovery not handled

**Category:** reset
**Frequency:** medium
**Applies to:** any design with asynchronous reset

**Symptom:** FSM or logic enters an unexpected state when async reset deasserts near a clock edge.

**Root cause:** async reset deassertion can violate recovery/removal timing, causing metastability.

**Trigger conditions:** reset deassertion occurs within the recovery/removal window of a clock edge.

**Correct code pattern:**
```verilog
// Synchronize reset deassertion
reg rst_sync_0, rst_sync_1;
always @(posedge clk or posedge rst_async) begin
  if (rst_async) begin
    rst_sync_0 <= 1;
    rst_sync_1 <= 1;
  end else begin
    rst_sync_0 <= 0;
    rst_sync_1 <= rst_sync_0;
  end
end
wire rst_safe = rst_sync_1;
```

**Prevention assertion:**
```systemverilog
// Verify reset deassertion is synchronized
assert property (@(posedge clk) $fell(rst_async) |-> ##[1:2] $fell(rst_safe));
```

**Regression test:** deassert reset at random times relative to clock edge, verify clean recovery.

---

### B5: FIFO pointer not initialized on reset

**Category:** boundary
**Frequency:** medium
**Applies to:** any FIFO with pointers

**Symptom:** FIFO reports incorrect full/empty state after reset.

**Root cause:** write or read pointer is not reset to zero.

**Trigger conditions:** first operation after reset.

**Correct code pattern:**
```verilog
always @(posedge clk) begin
  if (rst) begin
    wr_ptr <= 0;
    rd_ptr <= 0;
  end else begin
    if (wr_do) wr_ptr <= wr_ptr + 1;
    if (rd_do) rd_ptr <= rd_ptr + 1;
  end
end
```

**Prevention assertion:**
```systemverilog
assert property (@(posedge clk) $rose(rst_done) |-> (wr_ptr == 0 && rd_ptr == 0));
```

**Regression test:** reset FIFO, verify empty flag is asserted immediately.

---

### C4: Counter load and count simultaneous

**Category:** counter
**Frequency:** medium
**Applies to:** loadable counters

**Symptom:** counter value is incorrect when load and count happen in the same cycle.

**Root cause:** the RTL does not define priority between load and increment.

**Trigger conditions:** load and count_en both asserted in the same cycle.

**Bug code pattern:**
```verilog
// BUG: ambiguous priority
always @(posedge clk) begin
  if (load) counter <= load_val;
  if (count_en) counter <= counter + 1;  // overwrites load?
end
```

**Correct code pattern:**
```verilog
// Define explicit priority: load wins
always @(posedge clk) begin
  if (load)
    counter <= load_val;
  else if (count_en)
    counter <= counter + 1;
end
```

**First divergent cycle:** the cycle where load and count_en are both high.

**Prevention assertion:**
```systemverilog
assert property (@(posedge clk) load && count_en |-> ##1 counter == $past(load_val));
```

**Regression test:** assert load and count_en simultaneously, verify counter takes loaded value.

---

### H6: Valid/assertion after valid deasserted

**Category:** handshake
**Frequency:** low
**Applies to:** any ready/valid path with combinational valid logic

**Symptom:** valid glitches low for one cycle then returns high, causing downstream to miss a transfer.

**Root cause:** valid is driven combinationally from a condition that briefly becomes false.

**Trigger conditions:** combinational path to valid has a brief false pulse.

**Correct code pattern:**
```verilog
// Register valid to prevent glitches
always @(posedge clk) begin
  if (rst)
    valid_o <= 0;
  else
    valid_o <= next_valid;
end
```

**Prevention assertion:**
```systemverilog
// Valid should not glitch (deassert for exactly 1 cycle between two assertions)
assert property (@(posedge clk) valid_o && !ready_i |-> ##1 valid_o);
```

**Regression test:** stress test with random backpressure, verify valid never glitches.

---

### DP3: Signed/unsigned comparison error

**Category:** state-machine
**Frequency:** medium
**Applies to:** any RTL with mixed signed/unsigned arithmetic

**Symptom:** comparison or arithmetic produces wrong result when one operand is signed and the other is unsigned.

**Root cause:** Verilog promotes the unsigned operand to signed, changing the comparison result.

**Trigger conditions:** comparing a signed counter to an unsigned threshold.

**Bug code pattern:**
```verilog
// BUG: signed counter compared to unsigned constant
reg signed [7:0] counter;
wire done = (counter >= 8'd100);  // promotes counter to unsigned!
```

**Correct code pattern:**
```verilog
// Use explicit signed cast
wire done = (counter >= $signed(8'd100));
// Or use unsigned counter if negative values are not needed
reg [7:0] counter;
```

**First divergent cycle:** the cycle where counter is negative and compared to an unsigned value.

**Prevention assertion:**
```systemverilog
// Lint check: no mixed signed/unsigned comparisons
```

**Regression test:** let counter go negative, verify comparison result is correct.

---

### DP4: Bit-slicing truncation in burst/beat calculation

**Category:** data-path
**Frequency:** medium
**Applies to:** burst calculators, beat counters, address increment logic

**Symptom:** A transfer of exactly 256 beats (or any power-of-2 count) produces zero remainder, causing the design to skip the final burst entirely. Transfer silently loses data.

**Root cause:** Using bit-slicing `total_beats[7:0]` to extract the remainder instead of a proper `if/else` branch. When `total_beats = 256`, `total_beats[7:0] = 0`, and the design concludes there is no partial burst.

**Trigger conditions:** Transfer size is an exact multiple of the maximum burst length (256 beats), or total beats equals any 2^n boundary.

**Bug code pattern:**
```verilog
// BUG: bit-slicing gives 0 when total_beats = 256
wire [23:0] block_cnt    = total_beats_raw[31:8];
wire [7:0]  remain_beats = total_beats_raw[7:0];  // = 0 when total_beats = 256
wire        has_remain   = |total_beats_raw[7:0];  // = 0, burst skipped!
```

**Correct code pattern:**
```verilog
// FIXED: explicit branch handles 256-beat boundary
always @(*) begin
    if (total_beats_raw <= 256) begin
        block_cnt    = 0;
        remain_beats = total_beats_raw[7:0];
        has_remain   = 1'b1;  // always has a burst when <= 256
    end else begin
        block_cnt    = total_beats_raw[31:8];
        remain_beats = total_beats_raw[7:0];
        has_remain   = |total_beats_raw[7:0];
    end
end
```

**First divergent cycle:** the cycle where `load_addr` captures burst parameters, `has_remain` is 0, and FSM goes directly to IDLE without issuing any burst.

**Prevention assertion:**
```systemverilog
// If total_beats > 0, at least one burst must be issued
assert property (@(posedge clk_i) load_addr |-> (total_beats_raw > 0) |-> ##[1:4] (axi_valid_o));
```

**Regression test:** set `data_len = BUS_BYTES * 256` (exactly 256 beats), verify at least one burst is issued.

---

### DP5: Error path not reaching completion tracker

**Category:** data-path
**Frequency:** medium
**Applies to:** multi-channel designs with per-channel error capture (DMA, bus bridges, protocol adapters)

**Symptom:** One channel's error response is captured locally but never appears in the top-level error output. Completion reports success when it should report error.

**Root cause:** During integration, per-channel error flags are captured in local registers but not OR'd into the global error signal fed to the completion tracker. Common in designs where read and write paths are implemented independently.

**Trigger conditions:** Slave returns SLVERR on R channel (read data) while B channel responses are all OKAY.

**Bug code pattern:**
```verilog
// BUG: only B error reaches completion tracker
completion_tracker u_comp (
    .b_error_i(bresp_err[1]),   // only write error!
    // rresp_err is captured in rd_data_channel but never connected
);
```

**Correct code pattern:**
```verilog
// FIXED: all error paths merged before completion tracker
completion_tracker u_comp (
    .b_error_i(rresp_err[1] | bresp_err[1]),  // read OR write error
);
```

**First divergent cycle:** the cycle where `b_error_i` is sampled as 0 despite `rresp_err[1]` being 1.

**Prevention assertion:**
```systemverilog
// If any channel has an error, completion must report error
assert property (@(posedge clk_i) done_o |-> (rresp_err[1] || bresp_err[1]) |-> error_o);
```

**Regression test:** inject SLVERR on R channel only, verify `cdma_done_o & cdma_error_o` on completion.

---

### M2: Register file write port not gated

**Category:** boundary
**Frequency:** low
**Applies to:** multi-ported register files

**Symptom:** power waste or write conflict when write port is always active.

**Root cause:** write port drives the register file every cycle regardless of write enable.

**Trigger conditions:** synthesis or power analysis shows unnecessary switching.

**Correct code pattern:**
```verilog
// Gate write with explicit enable
always @(posedge clk) begin
  if (wr_en)
    regfile[addr] <= wdata;
end
```

**Prevention assertion:** use lint to verify write ports have explicit enables.

**Regression test:** verify write enable gates the write port correctly.

---

### H7: Backpressure bypassed by combinational ready path

**Category:** handshake
**Frequency:** medium
**Applies to:** ready/valid adapters with combinational ready logic

**Symptom:** downstream receives data even when it has deasserted ready, causing overflow or corruption.

**Root cause:** ready_o is a combinational function of ready_i without registering, creating a path where data passes through when it should not.

**Trigger conditions:** ready_i deasserts on the same cycle that valid_i asserts.

**Bug code pattern:**
```verilog
// BUG: combinational ready passthrough
assign ready_o = ready_i;  // data can pass through in same cycle
```

**Correct code pattern:**
```verilog
// Register ready to break combinational path
always @(posedge clk) begin
  if (rst)
    ready_o <= 0;
  else
    ready_o <= !valid_o || ready_i;  // only ready when output is empty or being consumed
end
```

**First divergent cycle:** the cycle where ready_i and valid_i change simultaneously.

**Prevention assertion:**
```systemverilog
// Data must not pass through in the same cycle as ready deassertion
assert property (@(posedge clk) $fell(ready_i) |-> ##1 !accept_input);
```

**Regression test:** deassert ready_i while valid_i is high, verify no data passes through.

---

### H8: VALID gated by non-protocol condition

**Category:** handshake
**Frequency:** high
**Applies to:** any FSM driving AXI VALID (ARVALID, AWVALID, WVALID, RVALID, BVALID)

**Symptom:** AXI handshake violates protocol: VALID deasserts before READY, or VALID is held but the handshake doesn't complete because a non-protocol condition blocks it. May cause duplicate bursts or lost transfers.

**Root cause:** The FSM combines protocol handshake (`valid & ready`) with flow control logic (`can_send`, `outstanding_ok`, `fifo_not_full`) in the same condition: `if (ready_i && can_send_i)`. When `can_send_i` goes low, the handshake is blocked even though VALID is asserted and READY arrives.

**Trigger conditions:** Outstanding counter reaches maximum, or downstream FIFO becomes full, while VALID is asserted and slave asserts READY.

**Bug code pattern:**
```verilog
// BUG: can_send_i gates the handshake
S_SEND: begin
    valid_o = 1'b1;
    if (ready_i && can_send_i) begin  // can_send_i blocks handshake
        send_next_o = 1'b1;
        nstate = S_NEXT;
    end else begin
        nstate = S_SEND;
    end
end
```

**Correct code pattern:**
```verilog
// FIXED: handshake independent of flow control
S_SEND: begin
    valid_o = 1'b1;
    if (ready_i) begin              // handshake completes regardless
        send_next_o = 1'b1;
        if (can_send_i) begin       // flow control only affects next action
            nstate = S_SEND;        // issue next burst
        end else begin
            nstate = S_IDLE;        // wait for outstanding to drain
        end
    end else begin
        nstate = S_SEND;            // hold VALID until READY
    end
end
```

**First divergent cycle:** the cycle where READY arrives but `can_send_i` is low, causing the handshake to miss.

**VCD detection:**
```bash
python scripts/vcd_extract.py dump.vcd --find-violation valid-drop --signals valid_o,ready_i
# Then check if can_send_i was low at the violation timestamp
python scripts/vcd_extract.py dump.vcd --signals can_send_i --range <violation_time>:<violation_time+10>
```
Look for: `valid_o=1, ready_i=1` but FSM stays in same state (no handshake completion). This indicates a non-protocol condition blocked the handshake.

**Prevention assertion:**
```systemverilog
// VALID must not deassert without a completed handshake
assert property (@(posedge clk_i) (valid_o && !ready_i) |=> valid_o);
// When VALID is high, only protocol signals (ready_i) may affect the handshake
assert property (@(posedge clk_i) valid_o |-> !$isunknown(ready_i));
```

**Regression test:** assert VALID, hold READY low, toggle `can_send_i` low then high, then assert READY — verify handshake completes exactly once.

---

## Counter patterns

### P14: Auto-reload and event trigger race at count=0

**Category:** counter
**Frequency:** medium
**Applies to:** count-down timers with auto-reload and event triggers (DMA, interrupt, PWM)
**Source:** TIMER project (2026-05-23). Principle: synchronous design — when multiple concurrent events share a condition, explicit priority must be defined (Wakerly, "Digital Design Principles and Practices", §7.3; IEEE 1364-2005 §5.4 on concurrent event evaluation).

**Symptom:** Event trigger (DMA cmd_valid, interrupt pulse) never asserts even though the counter reaches zero. Auto-reload silently prevents the trigger from firing.

**Root cause:** When the counter reaches zero, auto-reload and the event trigger both evaluate in the same cycle. Auto-reload immediately sets `count_d = LOAD_VAL`, making `count_is_zero` false on the next cycle. The trigger condition `count_is_zero && !triggered` never holds long enough to assert.

**Trigger conditions:** Free-run mode with auto-reload AND a count-zero event trigger (DMA, IRQ, etc.) active simultaneously.

**Correct code pattern:**
```verilog
// dma_fired_q blocks reload until handshake completes
reg dma_fired_q;
wire dma_handshake = dma_trig_o && dma_trig_ready_i;
wire auto_reload   = ctrl_en_i && !ctrl_mode_i && count_is_zero &&
                     !dma_trig_o && !dma_fired_q;
wire dma_fire      = ctrl_en_i && dma_en_i && count_is_zero && !dma_fired_q;
```

**Regression test:** enable timer with DMA trigger, LOAD=1. Verify dma_trig_o asserts when count reaches 0. Verify it holds until dma_trig_ready_i=1. Verify counter reloads after handshake.

---

## Status register patterns

### P15: Dedicated clear register does not directly clear status bit

**Category:** register
**Frequency:** medium
**Applies to:** any register file with both W1C status bits and dedicated clear registers
**Source:** TIMER project (2026-05-23). Principle: register file design — clear paths must be direct, not indirect through functional logic (ARM Cortex-M NVIC design, RISC-V CLINT spec — both use direct memory-mapped clear registers).

**Symptom:** Writing a dedicated INT_CLEAR register does not clear the corresponding STATUS bit. The status bit remains set.

**Root cause:** The dedicated clear path goes through the functional block rather than directly clearing the status register. If the functional condition is still active, the status bit is re-captured immediately after the indirect clear.

**Correct code pattern:**
```verilog
// FIXED: int_clear_fire directly clears irq_status_q
if (irq_w1c || int_clear_fire)
    irq_status_q <= 1'b0;
```

**Regression test:** set IRQ (let count reach 0), write INT_CLEAR=1, read STATUS — verify irq_status=0.

---

### P16: Core output deassert does not release status register

**Category:** register
**Frequency:** medium
**Applies to:** any register file that captures core output status
**Source:** TIMER project (2026-05-23). Principle: symmetric edge handling — if a status register captures a 0→1 transition, it must also handle 1→0 (standard register design practice, cf. ARM GIC ICPENDR/ICACTIVER registers).

**Symptom:** Core output deasserts after feed/recovery, but the STATUS register bit remains set.

**Root cause:** Status register implements capture (0→1) but not release (1→0). The capture condition `core_out && !status_q` only sets the bit; there's no corresponding clear when `core_out` goes low.

**Correct code pattern:**
```verilog
// FIXED: capture AND release
if (wdt_timeout_i && !wdt_timeout_q)
    wdt_timeout_q <= 1'b1;
if (!wdt_timeout_i && wdt_timeout_q)
    wdt_timeout_q <= 1'b0;  // auto-clear when core output deasserts
```

**Regression test:** trigger condition, then recover (feed watchdog), read STATUS — verify status bit cleared.

---

### P17: Status capture re-sets immediately after clear

**Category:** register
**Frequency:** medium
**Applies to:** any status register with capture and clear in the same always block
**Source:** TIMER project (2026-05-23). Principle: interrupt handling — "disable source before clearing status" (ARM GIC Architecture Specification §3.3, RISC-V PLIC spec §6).

**Symptom:** Writing W1C or INT_CLEAR clears the status bit, but it's re-set on the next cycle because the trigger condition is still active.

**Fix principle:** "Close the source before clearing the status." Either disable the trigger condition before clearing, or make clear have priority over capture.

---

## Pipeline timing patterns

### P18: Combinational output reads stale registered value (pipeline latency)

**Category:** pipeline
**Frequency:** medium
**Applies to:** any design where combinational output depends on a register that was updated in the same cycle
**Source:** IEEE 1364-2005 §5.4.4 (nonblocking assignment scheduling: NBA updates happen after the current time step, so combinational reads see the old value), SNUG 2000 (Cummings, "Nonblocking Assignments in Verilog Synthesis")

**Symptom:** Output data is one cycle behind — shows the previous value instead of the current one. Functional verification fails (wrong CRC, wrong checksum, wrong result).

**Root cause:** A combinational output (`crc_val`, `sum_o`, `result_o`) reads a register (`crc_q`, `acc_q`) that was updated by a synchronous enable (`crc_en_i`) on the SAME clock edge. In Verilog, the register update happens AFTER the clock edge, so the combinational output sees the OLD value. The output is captured into another register on the same edge, locking in the stale value.

**Trigger conditions:** A pipeline where: (1) data input triggers a register update, (2) combinational output reads that register, (3) the output is captured into a holding register — all on the same clock edge.

**Bug code pattern:**
```verilog
// BUG: crc_out_load fires on same cycle as crc_en, but crc_val reads OLD crc_q
wire crc_out_load = (accept_in && tlast);  // fires on data beat

always @(posedge clk_i) begin
    if (crc_en_i)    crc_q <= crc_next;     // updates on next edge
    if (crc_out_load) crc_out_q <= crc_val;  // captures OLD crc_q (stale!)
end
assign crc_val = crc_q ^ OUTPUT_XOR;  // reads current crc_q (before update)
```

**Correct code pattern (add pipeline stage):**
```verilog
// FIXED: add CRC_WAIT state to let crc_q update before capturing
localparam ST_IDLE     = 2'b01;
localparam ST_CRC_WAIT = 2'b10;  // wait 1 cycle for crc_q to update
localparam ST_CRC_OUT  = 2'b11;

// FSM: IDLE → (tlast) → CRC_WAIT → CRC_OUT → (handshake) → IDLE
case (state_q)
    ST_IDLE: if (accept_in && tlast) state_d = ST_CRC_WAIT;
    ST_CRC_WAIT: state_d = ST_CRC_OUT;  // crc_q now updated
    ST_CRC_OUT: if (accept_out) state_d = ST_IDLE;
endcase

wire crc_out_load = (state_q == ST_CRC_WAIT);  // capture AFTER update
always @(posedge clk_i) begin
    if (crc_out_load) crc_out_q <= crc_val;  // reads UPDATED crc_q
end
```

**First divergent cycle:** the cycle where `crc_out_load` fires — check whether `crc_val` reflects the data that was just accepted. If it shows the previous CRC state, the pipeline is one cycle short.

**Prevention assertion:**
```systemverilog
// After tlast beat accepted, CRC output must reflect the new data (not stale)
// This requires a known-good CRC model in the testbench
assert property (@(posedge clk_i)
    (accept_in && tlast) |-> ##2 m_valid_q && (crc_out_q !== stale_value));
```

**Regression test:** send a single-beat packet (tlast on first beat), check CRC output — verify it matches the expected CRC of that single beat. If it matches the INIT_VALUE instead, the pipeline is one cycle short.

---

## Verification blind spot patterns

### V1: Structural PASS but functional FAIL

**Category:** verification
**Frequency:** high (3 of 19 trial projects)
**Applies to:** any module where Step 8 structural review passes but functional tests are absent or insufficient

**Source:** CRC project (2026-05-23): 66 checklist items PASS, single-beat CRC output = 0. Crossbar project: routing logic broken. DMA project: transfer never completed.

**Symptom:** Step 8 self-review reports PASS for all items. Module compiles and lint passes. But simulation with known inputs produces wrong outputs, zero outputs, or no output at all.

**Root cause:** The Step 8 checklist verifies structural correctness (naming, FSM style, protocol compliance, reset). It does NOT verify that the module produces correct output values. A module can have perfect naming, correct FSM style, compliant protocol, and proper reset — yet compute the wrong result because of a datapath logic error.

**Trigger conditions:**
- Module has computation logic not covered by structural checks
- Module has state transitions that are syntactically correct but semantically wrong
- Module has pipeline latency causing stale output (see P18)
- Module has routing/mux logic selecting the wrong source
- Step 8 checklist passes but no functional test was run

**Detection method:** After Step 8, always run at least one golden reference test:
- Computation modules: known I/O pairs from authoritative sources (IEEE 802.3 for CRC, Hsiao paper for ECC)
- Data movement modules: end-to-end data integrity scoreboard
- Protocol modules: write-readback verification
- Stateful modules: invariant checking (one-hot, credit bounds, counter overflow)
- Pipeline modules: output latency verification

See `references/verification/golden-reference-guide.md` for the full methodology and testbench templates.

**Bug code pattern (example — CRC pipeline):**
```verilog
// BUG: structural checks PASS, but crc_out_q captures stale crc_q
wire crc_out_load = (accept_in && tlast);  // fires same cycle as crc_en
always @(posedge clk_i) begin
    if (crc_en_i)    crc_q <= crc_next;     // NBA: updates NEXT cycle
    if (crc_out_load) crc_out_q <= crc_val;  // reads OLD crc_q (stale!)
end
```

**Correct approach (golden reference catches this):**
```verilog
// In testbench: send single-beat data, check CRC output
// Golden reference: CRC-8 of 0xAB = 0x58 (from IEEE 802.3 polynomial)
// If DUT outputs 0x00 (INIT_VALUE) instead of 0x58, P18 bug confirmed
check_golden(8'hAB, 8'h58, "crc8_single_beat");
```

**Prevention:** Add golden reference checks to the testbench before claiming the design is correct. A design that passes structural review but has no functional test is at maturity level "Structural Sketch", not "Reviewable RTL".

**Regression:** For each module type, include at least one golden reference test that verifies output values, not just structural properties.

---

## Low-power patterns

### LP1: Isolation enable timing violation

**Category:** Low Power
**Frequency:** High (every power-gated design)
**Symptom:** Bus contention or metastability at power domain boundary during power-off
**Root cause:** Isolation enable deasserted too late (after power-off) or asserted too early (before power-on stable)

**Bug code:**
```verilog
// BAD: isolation and power switch controlled by same signal
assign isolation_en = !power_switch;  // simultaneous → contention window
```

**Correct code:**
```verilog
// GOOD: isolation asserts BEFORE power-off, deasserts AFTER power-on
// PSM state sequence: ISOLATING → SAVE → OFF → WAKING → RESTORE → DEISOLATING
assign isolation_en = (state == S_ISOLATING) || (state == S_SAVE_RETAIN) ||
                      (state == S_POWER_OFF) || (state == S_SLEEP) ||
                      (state == S_WAKING) || (state == S_RESTORE);
assign power_switch = (state != S_POWER_OFF) && (state != S_SLEEP);
// Isolation is ON for 2 extra states before power-off and after power-on
```

**Prevention:** In self-review, verify isolation enable timing against power state machine. Isolation MUST be asserted at least 1 cycle before power-off.

---

### LP2: Retention save/restore handshake race

**Category:** Low Power
**Frequency:** Medium
**Symptom:** Retention register contains stale or corrupted data after power-on
**Root cause:** Save overlaps with power-off, or restore overlaps with de-isolation

**Bug code:**
```verilog
// BAD: save and power-off in same cycle
always @(posedge clk_i) begin
    if (power_off_req) begin
        shadow_q <= data_q;      // save
        power_switch <= 1'b0;    // power off — same cycle! save may not complete
    end
end
```

**Correct code:**
```verilog
// GOOD: save completes BEFORE power-off (separate states)
// PSM: SAVE state (1+ cycles) → OFF state (power off after save done)
always @(posedge clk_i) begin
    if (retain_save_i)      // asserted by PSM in SAVE state
        shadow_q <= data_q; // save completes in SAVE state
    else if (retain_restore_i)  // asserted by PSM in RESTORE state
        data_q <= shadow_q;     // restore in RESTORE state
    else
        data_q <= data_d;
end
```

**Prevention:** Retention save and power-off MUST be in separate FSM states with at least 1 cycle gap.

---

### LP3: Power state machine illegal state transition

**Category:** Low Power
**Frequency:** Medium
**Symptom:** Unexpected power domain behavior, contention, or data loss
**Root cause:** PSM has unreachable states or transitions that skip required steps

**Bug code:**
```verilog
// BAD: can go directly from SLEEP to S_ON (skips WAKING, RESTORE, DEISOLATING)
case (state_q)
    S_SLEEP: begin
        if (wake_req_i)
            state_d = S_ON;  // illegal: skips isolation release, retention restore
    end
end
```

**Correct code:**
```verilog
// GOOD: all transitions go through required intermediate states
case (state_q)
    S_SLEEP: begin
        if (wake_req_i)
            state_d = S_WAKING;  // must go through WAKING → RESTORE → DEISOLATING
    end
end
// Two-process FSM with default: state_d = S_ON (safe default)
```

**Prevention:** Draw PSM state diagram before coding. Verify every transition. Use `default: state_d = S_ON` for illegal states.

---

### LP4: Gated clock domain crossing without synchronizer

**Category:** Low Power / CDC
**Frequency:** High
**Symptom:** Metastability or data loss when gated clock stops
**Root cause:** Signal crosses from gated domain to ungated domain using level synchronizer (which fails when gated clock stops)

**Bug code:**
```verilog
// BAD: level synchronizer fails when gated_clk stops
reg [1:0] sync_q;
always @(posedge ungated_clk_i)
    sync_q <= {sync_q[0], signal_in_gated_domain};
```

**Correct code:**
```verilog
// GOOD: pulse synchronizer handles stopped clock
// Convert to pulse in gated domain first
reg signal_d;
always @(posedge gated_clk_i)
    signal_d <= signal_in_gated_domain;
wire pulse = signal_in_gated_domain & ~signal_d;

// Double-flop pulse synchronizer in ungated domain
reg [2:0] sync_q;
always @(posedge ungated_clk_i)
    sync_q <= {sync_q[1:0], pulse};
wire pulse_out = sync_q[1] & ~sync_q[2];
```

**Prevention:** Never gate clocks used for CDC synchronizers. Use pulse synchronizers when source clock may stop.

---

### LP5: DVFS frequency change during active transfer

**Category:** Low Power
**Frequency:** Low
**Symptom:** Protocol violation, data corruption during frequency transition
**Root cause:** Frequency change requested while bus transfer is in progress

**Bug code:**
```verilog
// BAD: frequency change can happen mid-transfer
always @(posedge clk_i) begin
    if (sw_freq_change)
        freq_reg <= sw_new_freq;  // may change during AXI burst
end
```

**Correct code:**
```verilog
// GOOD: frequency change gated by bus idle
wire bus_idle = !axi_valid && !axi_ready && !outstanding;
always @(posedge clk_i) begin
    if (sw_freq_change && bus_idle)  // only change when bus is idle
        freq_reg <= sw_new_freq;
end
```

**Prevention:** DVFS controller MUST check bus idle before frequency change. Document this in the timing contract.

---

### LP6: Operand isolation not applied to wide combinational logic

**Category:** Low Power
**Frequency:** High (common oversight)
**Symptom:** Unnecessary switching power in wide combinational blocks
**Root cause:** Multiplier, barrel shifter, or other wide logic switches even when output is unused

**Bug code:**
```verilog
// BAD: multiplier always computes even when result is not needed
wire [63:0] product = a_i * b_i;  // 32x32 multiplier always switching
assign result = use_product ? product : other_result;
```

**Correct code:**
```verilog
// GOOD: isolate inputs to stop switching
wire [31:0] a_iso = use_product ? a_i : 32'b0;
wire [31:0] b_iso = use_product ? b_i : 32'b0;
wire [63:0] product = a_iso * b_iso;
assign result = use_product ? product : other_result;
```

**Prevention:** For any combinational block wider than 32 bits, check if output is always used. If not, apply operand isolation.

---

## Physical awareness patterns

### PH1: Hierarchical boundary on critical path

**Category:** Physical
**Frequency:** High
**Symptom:** Timing failure on cross-module combinational path
**Root cause:** Combinational logic spans two modules that are placed far apart in the floorplan

**Bug code:**
```verilog
// BAD: combinational path crosses hierarchy (long wire)
module block_a (
    output [31:0] data_o
);
    assign data_o = complex_computation;  // output is combinational
endmodule

module block_b (
    input  [31:0] data_i,
    output [31:0] result_o
);
    assign result_o = data_i + offset;  // combinational input from block_a
endmodule
```

**Correct code:**
```verilog
// GOOD: registered boundary at hierarchy
module block_a (
    input  clk_i,
    output reg [31:0] data_o
);
    always @(posedge clk_i)
        data_o <= complex_computation;  // registered output
endmodule

module block_b (
    input  clk_i,
    input  [31:0] data_i,
    output reg [31:0] result_o
);
    always @(posedge clk_i)
        result_o <= data_i + offset;    // registered input
endmodule
```

**Prevention:** Every module boundary should have registered I/O. If a combinational path must cross hierarchy, document it in the timing contract as a potential critical path.

---

### PH2: High-fanout net without register replication

**Category:** Physical
**Frequency:** High
**Symptom:** Congestion hotspot, timing failure on high-fanout net
**Root cause:** Single register drives too many destinations, creating routing congestion

**Bug code:**
```verilog
// BAD: single valid signal drives 200 consumers
reg valid_q;
always @(posedge clk_i) valid_q <= valid_d;
// 200 modules read valid_q → routing congestion, slow arrival at far consumers
```

**Correct code:**
```verilog
// GOOD: guide synthesis to replicate
(* max_fanout = 50 *)
reg valid_q;
always @(posedge clk_i) valid_q <= valid_d;
// Tool replicates to 4 copies, each driving ~50 consumers
```

**Prevention:** Any signal with fanout >50 should have `max_fanout` attribute or be manually replicated in RTL. Check with `yosys -p "stat"` for fanout information.

---

### PH3: Memory macro too far from data path consumer

**Category:** Physical
**Frequency:** Medium
**Symptom:** Timing failure on memory read path, large area overhead for routing
**Root cause:** Memory macro and its data path consumer are in different floorplan regions

**Bug code:**
```verilog
// BAD: memory in one module, consumer in another, far apart
module memory_block (...);
    sram_1024x32 u_mem (...);  // placed in region A
endmodule

module data_processor (...);
    // placed in region B, 3mm away
    always @(posedge clk_i)
        processed <= transform(mem_data_i);  // long wire from mem
endmodule
```

**Correct code:**
```verilog
// GOOD: memory and consumer in same module (same floorplan region)
module data_path_with_mem (...);
    sram_1024x32 u_mem (...);  // placed together
    always @(posedge clk_i)
        processed <= transform(u_mem.rdata_o);  // short wire
endmodule
```

**Prevention:** Keep memory macros and their primary consumers in the same module hierarchy. Document macro placement intent in RTL comments.

---

### PH4: Bus signals not grouped at partition boundaries

**Category:** Physical
**Frequency:** Medium
**Symptom:** Routing congestion at partition ports, bus signals scattered across metal layers
**Root cause:** Related bus signals are declared as separate ports rather than grouped arrays

**Bug code:**
```verilog
// BAD: bus signals scattered across port list
module my_block (
    input        axi_awvalid,
    input [31:0] axi_awaddr,
    input        axi_wvalid,
    input [31:0] axi_wdata,
    // ... other signals interleaved ...
    input        axi_arvalid,
    input [31:0] axi_araddr
);
```

**Correct code:**
```verilog
// GOOD: bus signals grouped, related signals adjacent
module my_block (
    // Write address channel
    input        axi_awvalid_i,
    input [31:0] axi_awaddr_i,
    input        axi_awready_o,
    // Write data channel
    input        axi_wvalid_i,
    input [31:0] axi_wdata_i,
    input        axi_wready_o,
    // Read address channel
    input        axi_arvalid_i,
    input [31:0] axi_araddr_i,
    input        axi_arready_o
);
```

**Prevention:** Group related bus signals in port declarations. Use channel-based grouping (AW, W, B, AR, R for AXI). This guides physical designer to route buses together.

---

## Self-review limitation rule

**Important:** The Step 8 self-review checklist checks STRUCTURAL correctness (naming, FSM style, protocol compliance, reset). It does NOT verify FUNCTIONAL correctness (output values, computation results, data integrity). See V1 above for the full pattern.

**Rule:** After structural self-review, always run a functional test with known inputs and expected outputs using the golden reference methodology (`references/verification/golden-reference-guide.md`). A design can pass all checklist items and still produce wrong results. The checklist catches style violations; simulation catches logic bugs.

---

## Pattern usage rule

When generating or reviewing RTL:
1. Identify the module type (FIFO, FSM, pipeline, handshake adapter, protocol block, counter).
2. Match against the applicable patterns above.
3. For each matched pattern, add a one-line warning in the output.
4. Include the prevention assertion in the verification notes.
5. If the generated code does not avoid a matched pattern, fix the code before finalizing.
