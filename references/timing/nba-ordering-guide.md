# NBA Ordering Guide — Non-Blocking Assignment Hazards

## Purpose

Non-blocking assignment (`<=`) is the single most common source of subtle RTL bugs in this skill's projects. Across CDMA R6, NVMe Phase 3, pipeline validation, and UART projects, **NBA ordering hazards account for the dominant share of simulation failures that pass structural review**.

This document consolidates NBA knowledge that was previously scattered across 7 files into one reference with three layers: **Concept → Rules → Traps**.

**When to read:** Mandatory before Step 7 (RTL generation). Re-read during Step 9 Phase 4 (failure analysis) when symptoms match any trap below.

**Authority:** IEEE 1364-2001 §5.3 (stratified event queue), Cummings SNUG 2000 "Nonblocking Assignments in Verilog Synthesis" §4 (queue mechanics) + §8 (NBA guidelines), IEEE 1800-2017 §4.7 (scheduling semantics).

---

## Layer 1: Concept — The Stratified Event Queue

### What happens on a posedge

IEEE 1364 §5.3 defines the Verilog event queue as ordered regions within a single time step:

```
┌─────────────────────────────────────────────┐
│ ACTIVE region                                │
│   assign statements evaluate                 │
│   always @(*) blocks evaluate                │
│   $display executes                          │
│   pure blocking (=) assignments execute      │  ← All use pre-update values
├─────────────────────────────────────────────┤
│ INACTIVE region                              │
│   #0 delayed assignments                     │
├─────────────────────────────────────────────┤
│ NBA region                                   │
│   non-blocking (<=) assignments update       │  ← Registers get new values here
├─────────────────────────────────────────────┤
│ POSTPONED region                             │
│   $monitor, $strobe sample                   │
└─────────────────────────────────────────────┘
```

**The critical fact:** ALL RHS expressions in ALL `<=` assignments evaluate using the values BEFORE the NBA region. If `a <= a + 1` and `b <= (a == 7)`, both use the SAME old value of `a`. `b` does NOT see the incremented `a`.

### The mental model mismatch

```verilog
// What the agent writes (sequential thinking):
a <= a + 1;           // "a is now a+1"
b <= (a == 7);        // "so b checks if a is 7"

// What the hardware does (parallel semantics):
// RHS(a) = old_a       RHS(a == 7) = (old_a == 7)
// Both update simultaneously in the NBA region.
// b captures whether old_a was 7, NOT whether old_a+1 was 7.
```

This is the single cognitive failure that caused 6 of the 13 bugs in NVMe Phase 3 (B2-B6, B11). The agent wrote Verilog as if `<=` were sequential statements. In hardware, they are parallel register transfers.

### Concrete example: WLAST lags beat counter (NVMe B2)

```verilog
// ❌ BROKEN — agent expects sequential evaluation
always @(posedge clk_i) begin
    if (w_valid && w_ready) begin
        w_beat_q    <= w_beat_q + 1'b1;          // NBA: scheduled for update
        w_last_o    <= (w_beat_q == burst_len);   // NBA: uses OLD w_beat_q!
    end
end
// Result: w_last_o asserts one beat AFTER the last beat.
// w_beat_q == 3 on beat 3, w_last_o samples old w_beat_q (2), not asserted.
// On beat 4: w_beat_q == 4 (from NBA), w_last_o samples old w_beat_q (3), asserted.
// But there IS no beat 4 — the burst ended at beat 3.

// ✅ FIX — WLAST is combinational from the registered counter
always @(posedge clk_i) begin
    if (w_valid && w_ready)
        w_beat_q <= w_beat_q + 1'b1;
end
assign w_last_o = (w_beat_q == burst_len);  // combinational — evaluates in ACTIVE
```

**Key rule:** Outputs that depend on counter values must be combinational (`assign` or `always @(*)`). Registered outputs lag by 1 cycle.

---

## Layer 2: Rules — Consolidated NBA Discipline

### R1: Use `<=` in sequential blocks, `=` in combinational blocks (E4)

Never mix. Verilog allows it, but mixing creates simulation/synthesis mismatch.

```verilog
// ❌ BROKEN
always @(posedge clk_i) begin
    tmp     = a + b;       // blocking — updates immediately
    result <= tmp + c;     // non-blocking — uses updated tmp
end
// tmp uses blocking: other always blocks see intermediate value. Race condition.

// ✅ CORRECT
always @(posedge clk_i) begin
    result <= a + b + c;   // all RHS evaluated with pre-edge values
end
```

### R2: Cross-block NBA order is non-deterministic (G1, B4)

Two different `always @(posedge clk_i)` blocks execute in **unspecified order** within the NBA region (IEEE 1364 §5.5). If block A's output is block B's input:

```verilog
// ❌ BROKEN — ordering race between two always blocks
always @(posedge clk_i)   // Block A
    w_beat_q <= w_beat_q + 1;

always @(posedge clk_i)   // Block B — reads w_beat_q
    if (w_beat_q == len)  // May see old OR new value depending on execution order
        w_done <= 1;
```

**Fix:** Move dependent logic into the same always block, or use combinational outputs for derived signals.

### R3: Combinational consumers read pre-NBA values (B1)

`assign` and `always @(*)` execute in the ACTIVE region, before the NBA region. They always see **old** register values.

```verilog
// Correct pattern: combinational output from registered state
assign w_last_o = (w_beat_q == burst_len);  // active-region read of NBA-updated value
```

This is CORRECT because `w_beat_q` was updated in the NBA region of the PREVIOUS time step. The active region reads the value that has already settled.

### R4: AXI WDATA must be combinational or pre-fetched (B3)

Data from a FIFO's read port is indexed by `rd_ptr_q`. If WDATA is registered:

```verilog
// ❌ BROKEN — WDATA registers old FIFO data
always @(posedge clk_i) begin
    if (w_ready) begin
        rd_ptr_q   <= rd_ptr_q + 1;      // NBA: advances pointer
        w_data_o   <= fifo_mem[rd_ptr_q]; // NBA: uses OLD rd_ptr_q
    end
end
// Result: beat N outputs data from FIFO slot N-1. All data shifted by 1.

// ✅ FIX — combinational data path
assign w_data_o = fifo_mem[rd_ptr_q];  // active region: reads pointer after last NBA
// OR: pre-fetch next data
always @(posedge clk_i)
    w_data_o <= fifo_mem[rd_ptr_q + 1];  // uses pre-advance pointer
```

### R5: Gated counter advance (B4)

```verilog
// ❌ BROKEN — counter advances on ready alone
if (w_ready)                    // valid may be 0 (NBA not yet applied)
    w_beat_q <= w_beat_q + 1;

// ✅ FIX — gate on valid AND ready
if (w_valid && w_ready)         // both conditions evaluated in same region
    w_beat_q <= w_beat_q + 1;
```

### R6: Advance on issue, not on arrival (B5)

Address/offset counters should advance when a command is **issued** (request sent), not when data **arrives** (response received). Issuing and receiving are different time steps.

```verilog
// ✅ CORRECT — advance on issue
if (cmd_issue)                  // command sent this cycle
    offset_q <= offset_q + len;
```

### R7: Don't gate consumer enable with producer valid (B6)

```verilog
// ❌ BROKEN — fifo_wr_en gated by rd_en
assign fifo_wr_en = nvm_rvalid_i && nvm_rd_en_o;
// When nvm_rd_en_o deasserts (last data consumed), any late-arriving data is dropped.

// ✅ FIX — simple forwarding
assign fifo_wr_en = nvm_rvalid_i;  // write everything that arrives
```

### R8: Large always blocks hide NBA hazards (C5/C6)

An `always @(posedge clk_i)` block with >8 registers or >50 lines makes NBA ordering hazards invisible. Split by register function.

---

## Layer 3: Traps — 6 NBA Failure Modes

### Trap 1: Registered counter → registered dependent output (NVMe B2)

**Symptom:** WLAST/RLAST asserts one beat late. Counter says N but condition fires at N+1.

**Root cause:** Dependent output registered in same block as counter. Uses old counter value.

**Detection:** If a registered output's RHS contains a register that is also updated in the same always block, flag it.

**Fix:** Make the dependent output combinational: `assign dependent = (counter == threshold)`.

```verilog
// ❌
always @(posedge clk_i) begin
    if (incr) cnt_q <= cnt_q + 1;
    done_o       <= (cnt_q == N);  // uses old cnt_q
end

// ✅
always @(posedge clk_i)
    if (incr) cnt_q <= cnt_q + 1;
assign done_o = (cnt_q == N);      // combinational, correct
```

### Trap 2: Registered FIFO data + advancing read pointer (NVMe B3)

**Symptom:** Output data shifted by 1 beat. All beats present but wrong position.

**Root cause:** `data_o <= fifo[rd_ptr_q]; rd_ptr_q <= rd_ptr_q + 1;` — data samples pre-advance pointer.

**Fix:** Combinational data output from FIFO: `assign data_o = fifo[rd_ptr_q];`

### Trap 3: Counter gated on ready only (NVMe B4)

**Symptom:** First beat (beat 0) skipped. Counter starts at 1 instead of 0.

**Root cause:** `if (w_ready) cnt <= cnt + 1;` — when w_valid is 0 (NBA-pending), ready alone advances the counter.

**Fix:** `if (w_valid && w_ready) cnt <= cnt + 1;`

### Trap 4: Address advances on data arrival (NVMe B5)

**Symptom:** Duplicate reads from the same address.

**Root cause:** `offset <= offset + step` triggered by data-valid, not by read-issue. Data arrives in a different time step from the read command.

**Fix:** Advance on issue strobe: `if (issue_cmd) offset <= offset + step;`

### Trap 5: Consumer enable gated by producer (NVMe B6)

**Symptom:** Last data beat lost. Consumer stops accepting before producer stops sending.

**Root cause:** `fifo_wr_en = valid_i && rd_en;` — rd_en deasserts before the final valid_i arrives.

**Fix:** Don't gate consumer input with its own output: `fifo_wr_en = valid_i;`

### Trap 6: Cross-block NBA dependency (generic)

**Symptom:** Non-deterministic simulation — sometimes passes, sometimes fails.

**Root cause:** Two `always @(posedge clk)` blocks where block B's condition depends on block A's output. IEEE 1364 §5.5: execution order is undefined.

**Fix:** Merge into one always block, or use combinational intermediate signal.

---

## Integration with Skill Workflow

| Workflow step | NBA relevance |
|---------------|---------------|
| **Step 7 (RTL generation)** | Read this guide BEFORE writing any `always @(posedge clk)` block. Apply R1-R8. |
| **Step 7b (yosys synthesis)** | Latch/loop detection catches some NBA issues (E2, E7). |
| **Step 8 (self-review)** | NBA ordering hazard check — see SKILL.md Step 8 for mandatory pre-simulation gate. |
| **Step 9 Phase 4 (failure analysis)** | Match symptoms to Traps 1-6. Check simulation-loop.md §3.5 for structured NBA diagnosis flow. |
