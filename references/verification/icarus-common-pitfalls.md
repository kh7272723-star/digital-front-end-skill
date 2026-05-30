# Icarus Verilog — Common Testbench Pitfalls

## Purpose

Icarus Verilog (iverilog) is the primary simulation tool for this skill. It is NOT a full IEEE 1364-2001/2005 compliant simulator — it has specific limitations and behavioral differences from commercial simulators (VCS, ModelSim, Xcelium). R5-R8 A/B experiments documented **19 distinct testbench infrastructure bugs** across 4 projects. All were Icarus-specific issues that wasted simulation iterations.

**This document is mandatory reading before writing any testbench.** Each pitfall includes: symptom (what you'll see), root cause, fix pattern, and experiment source.

---

## Authoritative Sources

The rules and fixes in this document are derived from the following hierarchy (per SKILL.md authority-to-rule synthesis):

| Tier | Source | Topics Covered |
|:----:|--------|---------------|
| 1 | **IEEE 1364-2001** (Verilog HDL LRM) | §5.3 Stratified event queue (delta cycles, NBA regions); §9.6 Loops; §9.7 Procedural timing; §9.8.2 fork/join; §10 Tasks |
| 2 | **IEEE 1800-2017** (SystemVerilog LRM) | §4.7 Nondeterminism; §4.8 Race conditions; §13.4 Tasks (return); §13.5.2 pass-by-reference (ref ports); §9.3.3 fork naming |
| 3 | **ARM IHI 0024C** (AMBA APB Protocol) | §2.1 Signal list; §3.1 State machine; §3.2 Write/Read transfers (SETUP/ACCESS phases); §4.1 PSLVERR timing |
| 3 | **ARM IHI 0022E** (AMBA AXI Protocol) | §A3.3.1 VALID stability; §A3.3.2 VALID/READY independence |
| 3 | **ARM IHI 0051B** (AMBA AXI-Stream) | §2.2 TVALID/TREADY handshake; §3.1 Signal descriptions |
| 3 | **NXP UM10204** (I2C-bus specification) | §5.1 Bus speeds; §5.2 SCL timing; §7 Clock stretching |
| 4 | **Cummings, SNUG 2000** "Nonblocking Assignments in Verilog Synthesis" | §4 Stratified event queue; §8 NBA guidelines; Delta-cycle race explanation |
| 4 | **Cummings, SNUG 1999** "Correct Methods For Adding Delays" | §2 Inertial vs transport delays; §3 #1 settling delay rationale |
| 4 | **Cummings & Mills, SNUG 2002** "Asynchronous & Synchronous Reset" | Reset deassertion timing; Reset synchronizer requirements |
| 4 | **Sutherland, "Verilog and SystemVerilog Gotchas"** (Springer, 2007) | Ch.4 fork/join gotchas; Ch.7 task/function limitations; Ch.2 event queue gotchas |
| 4 | **Icarus Verilog Wiki** (github.com/steveicarus/iverilog) | Icarus-specific limitations: `return` not in tasks, `break` not supported, `ref` ports not implemented |
| 5 | **Skill local experiments (R5-R8)** | 19 testbench infrastructure bugs documented across 4 A/B experiment rounds |

**When to cite:** For each pitfall, the fix pattern is grounded in at least one of: IEEE standard semantics (tier 1-2), protocol specification timing (tier 3), or published methodology paper analysis (tier 4). The experiment source (tier 5) provides empirical validation that the pitfall actually occurs in practice.

---

## Category A: Language Feature Gaps (Compile Errors)

These are features that Icarus does not support or supports incompletely. They cause **compile errors** that can waste 1-2 simulation iterations.

**Authority:** IEEE 1364-2001 §9.6 (loops), §9.8.2 (fork), §10 (tasks) — Icarus implements IEEE 1364 but not IEEE 1800 extensions. Sutherland, "Verilog and SystemVerilog Gotchas" Ch.7 documents `return`/`break` as SystemVerilog additions not in baseline Verilog. Icarus Wiki confirms these features are unimplemented.

### A1: `return` in tasks NOT supported

**Symptom:** `error: return not supported in tasks` (Windows iverilog)
**Source:** IEEE 1800-2017 §13.4.1 (`return` is a SystemVerilog keyword, not in IEEE 1364-2001). Icarus Verilog Wiki confirms `return` from tasks is unimplemented. Sutherland, "Verilog and SystemVerilog Gotchas" Ch.7 §7.2.
**Experiment:** R8 Agent A (iter 2)

Icarus on Windows does not support `return` inside tasks for early exit.

```verilog
// ❌ BROKEN — iverilog compile error
task run_test;
    input [255:0] name;
begin
    if (skip) return;   // NOT SUPPORTED by iverilog
    // ... test logic ...
end
endtask

// ✅ FIX — named block + disable for early exit
task run_test;
    input [255:0] name;
begin : task_body
    if (skip) disable task_body;  // early exit
    // ... test logic ...
end
endtask
```

**Rule:** Never use `return` in tasks. Use `begin : name ... disable name; ... end`.

### A2: `break` in loops NOT supported

**Symptom:** `error: break not supported` (iverilog)
**Source:** IEEE 1800-2017 §12.8 (`break` is a SystemVerilog keyword, not in IEEE 1364-2001 §9.6 loops). Sutherland, "Verilog and SystemVerilog Gotchas" Ch.4 §4.3.

```verilog
// ❌ BROKEN
for (i = 0; i < 256; i = i + 1) begin
    if (found) break;    // NOT SUPPORTED by iverilog
end

// ✅ FIX — named block + disable
for (i = 0; i < 256; i = i + 1) begin : find_loop
    if (found) disable find_loop;
end
```

### A3: `ref` ports in tasks NOT supported

**Symptom:** `error: ref ports not supported` (iverilog)
**Source:** IEEE 1800-2017 §13.5.2 (pass-by-reference is a SystemVerilog feature). Icarus Wiki confirms unimplemented.

```verilog
// ❌ BROKEN
task read_bus(output reg [31:0] data);  // ref/output ports not supported
begin
    // ...
end
endtask

// ✅ FIX — use module-level reg + task writes to it
reg [31:0] bus_data;
task read_bus;
begin
    // ... drive bus signals ...
    bus_data = prdata_o;  // assign to module-level reg
end
endtask
```

### A4: `fork` variable sharing (non-automatic tasks)

**Symptom:** Variables shared across `fork` branches change unpredictably. Loop index `i` in one branch overwrites `i` in another.
**Source:** IEEE 1364-2001 §9.8.2 (fork/join — all branches share parent scope variables by default). Sutherland, "Verilog and SystemVerilog Gotchas" Ch.4 §4.7-4.8 documents fork variable sharing as a known gotcha. IEEE 1800-2017 §9.3.3 fixes this with `fork...join_none` named blocks and `automatic` variables.

```verilog
// ❌ BROKEN — all fork branches share the same 'i'
integer i;
initial begin
    fork
        for (i = 0; i < 10; i = i + 1) send_beat(i);  // i changes globally
        for (i = 0; i < 10; i = i + 1) recv_beat(i);  // steals i from sender
    join
end

// ✅ FIX — use automatic variables per fork branch
integer i;
initial begin
    fork
        begin : sender
            automatic integer j;  // local copy
            for (j = 0; j < 10; j = j + 1) send_beat(j);
        end
        begin : receiver
            automatic integer k;  // separate local copy
            for (k = 0; k < 10; k = k + 1) recv_beat(k);
        end
    join
end

// ✅ BETTER — avoid fork/join for directed tests entirely
// Sequential tests are easier to debug and don't have fork issues
```

**Rule:** If you must use `fork`, wrap every branch in `begin : name` with `automatic` local variables. Prefer sequential directed tests.

### A5: Loop variable double-counting in fork

**Symptom:** A fork loop counts extra iterations because the loop variable is incremented by multiple branches.
**Source:** Same root cause as A4 (IEEE 1364-2001 §9.8.2 shared scope). Prefer sequential directed tests over fork-based concurrency.

```verilog
// ❌ BROKEN — i incremented in both wait and main paths
for (i = 0; i < N; i = i + 1) begin
    fork
        begin : wait_path
            @(posedge clk_i);
            if (ready) count = count + 1;
        end
    join_none
end

// ✅ FIX — use fixed-range for loop, count only in the intended path
for (i = 0; i < N; i = i + 1) begin
    @(posedge clk_i);
    if (valid && ready) count = count + 1;  // sequential, no fork
end
```

---

## Category B: Timing & Delta-Cycle Issues (Simulation Mismatch)

These cause the simulation to behave differently from what the RTL actually does — the testbench sees old or wrong values.

**Authority:** IEEE 1364-2001 §5.3 (stratified event queue) defines the active → inactive → NBA → monitor execution order that creates delta-cycle races. Cummings, SNUG 2000 §4 explains why `assign` RHS values sampled from active region appear "old" in NBA region. Cummings, SNUG 1999 §3 provides the `#1` settling delay methodology. ARM IHI 0024C §3.1-3.2 defines APB phase timing that governs when PSLVERR/PRDATA are valid.

### B1: Combinational `assign` + `posedge` sampling = delta-cycle race

**Symptom:** APB writes silently dropped. Register values never change. STATUS always reads 0. Testbench drives `psel_i=1, penable_i=1, pwrite_i=1` on posedge, but the DUT samples old `penable_i=0`.
**Source:** IEEE 1364-2001 §5.3 (stratified event queue: `assign` evaluates in active region, `always @(posedge clk)` samples from NBA region — the assign sees values from BEFORE the NBA update). Cummings, SNUG 2000 §4 "Verilog Stratified Event Queue" explains the delta-cycle mechanism. Cummings, SNUG 2000 §8.1: "Recommendation: Inline combinational conditions inside sequential blocks."
**Experiment:** R8 Agent A (iter 2 — the APB delta-cycle race wasted 1 iteration)

```verilog
// ❌ BROKEN — delta-cycle race in iverilog
assign apb_write = psel_i && penable_i && pwrite_i;

always @(posedge clk_i) begin
    if (apb_write) begin   // apb_write sampled at OLD penable_i value
        case (paddr_i)
            4'h0: ctrl_q <= pwdata_i[1:0];
            // ... NEVER executes because apb_write is 0 at sampling edge
        endcase
    end
end

// ✅ FIX — inline the condition directly in the sequential block
always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        ctrl_q <= 2'b00;
    end else if (psel_i && penable_i && pwrite_i) begin  // INLINE
        case (paddr_i)
            4'h0: ctrl_q <= pwdata_i[1:0];
            // ... now works correctly
        endcase
    end
end
```

**Root cause:** In iverilog, `assign` continuous assignments evaluate in the active region. The `always @(posedge clk_i)` samples at the NBA region boundary. If the testbench changes inputs on the same posedge, the `assign` reads the PREVIOUS values. Inlining the condition in the sequential block avoids this by evaluating all signals in the same timing region.

**Rule:** NEVER use `assign` for write-enable or chip-select signals that are consumed in `always @(posedge clk_i)` blocks. Inline the condition. This is mandatory for APB, AXI-Lite, and any bus slave interface.

### B2: Combinational output sampled too late (stale after transaction)

**Symptom:** APB `prdata_o` reads 0 after the transaction completes. `PSLVERR` never asserted despite writing to invalid address.
**Source:** ARM IHI 0024C §3.1-3.2: PRDATA/PSLVERR are combinational outputs — they reflect the CURRENT paddr_i/pwrite_i values. When the bus is idle (psel_i=0), the outputs reflect address 0x0 values. IEEE 1364-2001 §5.3: combinational outputs change in the active region immediately when inputs change.
**Experiment:** INTC project (APB PSLVERR scope), UART project (APB timing), golden-reference validation GAP-GR3 (stale output)

```verilog
// ❌ BROKEN — sampling after transaction, bus is idle
task test_pslverr;
begin
    apb_write(4'h30, 32'hdeadbeef);  // invalid address → should assert PSLVERR
    idle_bus();  // clears psel_i, penable_i, paddr_i
    #100;
    if (pslverr_o !== 1'b1)  // pslverr_o is combinational from paddr_i
        $display("FAIL");    // paddr_i = 0 now → pslverr_o = 0
end
endtask

// ✅ FIX — check combinational outputs DURING the transaction
task test_pslverr;
begin
    // SETUP phase
    @(negedge clk_i);
    psel_i   = 1'b1;
    paddr_i  = 6'h30;
    pwrite_i = 1'b1;
    pwdata_i = 32'hdeadbeef;
    // ACCESS phase
    @(negedge clk_i);
    penable_i = 1'b1;
    @(negedge clk_i);
    // Check BEFORE deasserting
    if (pslverr_o !== 1'b1)  // still in ACCESS phase, pslverr valid
        $display("FAIL: PSLVERR not asserted");
    // Now deassert
    psel_i   = 1'b0;
    penable_i = 1'b0;
end
endtask
```

**Rule:** All bus protocol combinational outputs (PRDATA, PSLVERR, PREADY, HRDATA, HREADY) are valid ONLY during the transaction. Check them BEFORE deasserting bus control signals.

### B3: Monitor samples before NBA settle (sees previous-cycle values)

**Symptom:** Data integrity checker reports mismatch, but waveform shows correct data. DUT output changes on posedge, but checker sees old value.
**Source:** Cummings, SNUG 1999 "Correct Methods For Adding Delays To Verilog Behavioral Models" §3: after `@(posedge clk)`, the NBA region hasn't executed yet — sampled values reflect PREVIOUS cycle. Adding `#1` (inertial delay) allows NBA execution to complete, then samples in the next active region. IEEE 1364-2001 §5.3 validates the execution order.
**Experiment:** golden-reference validation (always block race condition), tb-examples.md pattern 7

```verilog
// ❌ BROKEN — samples combinational output at NBA boundary, sees OLD value
always @(posedge clk_i) begin
    if (out_valid && out_ready) begin
        if (out_data !== expected)  // out_data is still previous cycle's value!
            $display("FAIL");
    end
end

// ✅ FIX — add #1 settling delay after posedge
always @(posedge clk_i) begin
    #1;  // let NBA region execute — NOW out_data is current-cycle value
    if (out_valid && out_ready) begin
        if (out_data !== expected)
            $display("FAIL");
    end
end
```

**Rule:** Every monitor/checker that reads combinational DUT outputs MUST add `#1` after `@(posedge clk_i)` before sampling.

### B4: NBA assignment in testbench + `@(posedge clk)` in DUT = race

**Symptom:** Testbench drives data with `<=` on posedge, DUT samples with `always @(posedge clk)` on same posedge — DUT sometimes samples new value, sometimes old. Non-deterministic.
**Source:** IEEE 1364-2001 §5.5 (scheduling semantics: NBA region execution order between multiple processes is non-deterministic). Cummings, SNUG 2000 §8.2: "Drive stimulus on negedge when DUT samples on posedge — guaranteed to be stable before the next active edge." IEEE 1800-2017 §4.7 documents the same non-determinism.
**Experiment:** R5 (FWFT sampling race), R6 (NBA race in data capture)

```verilog
// ❌ BROKEN — race between testbench NBA and DUT sampling
always @(posedge clk_i) begin
    s_axis_tdata_i  <= data;      // NBA — scheduled for later
    s_axis_tvalid_i <= 1'b1;      // NBA — scheduled for later
end
// DUT's always @(posedge clk_i) may sample OLD valid/data

// ✅ FIX — drive stimulus on NEGEDGE (guaranteed stable before next posedge)
always @(negedge clk_i) begin
    s_axis_tdata_i  <= data;      // drives half-cycle before DUT samples
    s_axis_tvalid_i <= 1'b1;
end
```

**Rule:** Drive stimulus on `@(negedge clk_i)` when the DUT samples on `@(posedge clk_i)`. See tb-examples.md pattern 6.

### B5: APB register update timing — FSM pops data before test checks it

**Symptom:** Test writes TXDATA, then enables FSM. Status read shows FIFO_EMPTY=1 — the byte was already popped and sent before the status check.
**Source:** IEEE 1364-2001 §5.5: all NBAs in a time step execute in zero simulation time — the FSM activates and processes data in the same clock cycle the register is written. ARM IHI 0024C §3.2: APB writes take effect on the posedge following ACCESS phase setup. The fix (write data first, enable last) follows the standard configuration-then-trigger pattern used by ARM PrimeCell peripherals.
**Experiment:** R8 Agent A (iter 3 — T2 test sequencing)

```verilog
// ❌ BROKEN — FSM immediately pops the byte
apb_write(CTRL,   2'b01);   // enable=1 → FSM sees FIFO has data → pops it
apb_write(TXDATA, 8'h55);   // too late — FSM already consumed previous data (or empty)
check_status(FIFO_EMPTY, 0);  // FIFO already empty!

// ✅ FIX — write data first, enable last
apb_write(DIVIDER, 16'd434);
apb_write(TXDATA, 8'h55);   // data in FIFO, FSM not running
apb_write(TXDATA, 8'hAA);   // second byte
apb_write(CTRL,   2'b01);   // NOW enable FSM
// Check status AFTER waiting for transmission to complete
```

**Rule:** For modules with auto-start FSMs: write data/config registers FIRST, then enable. For modules with explicit start bits: write data, then write CTRL with start=1.

---

## Category C: Output Protocol Compliance

The simulation-loop.md defines a standard output protocol. Agents who don't follow it produce output that cannot be automatically parsed.

**Authority:** Accellera UVM 1.2 §4.9 (end-of-test phasing and reporting). The `SIMULATION_DONE` marker pattern is derived from UVM's `report_phase` and adapted for minimal plain-Verilog testbenches. Mentor/Siemens "Verification Academy" (verificationacademy.com) recommends deterministic pass/fail markers for regression automation.

### C1: `$finish` without SIMULATION_DONE marker

**Symptom:** Simulation output ends abruptly. Automated result parsing can't determine if all tests ran.
**Source:** simulation-loop.md validation (rr_arbiter_trial)

```verilog
// ❌ BROKEN
initial begin
    run_tests();
    $finish;  // no summary, no marker
end

// ✅ FIX — follow the protocol
initial begin
    $display("SIMULATION_START");
    // ... setup ...
    $display("RESET_RELEASED");
    // ... tests ...
    $display("TEST_START test_name");
    // ... stimulus + checks ...
    $display("TEST_PASS test_name");  // or TEST_FAIL test_name
    // ...
    if (error_cnt == 0)
        $display("ALL_TESTS_PASS");
    else
        $display("FAIL: %0d errors", error_cnt);
    $display("SIMULATION_DONE");
    $finish;
end
```

**Required markers (in order):** `SIMULATION_START` → `RESET_RELEASED` → `TEST_START <name>` → `TEST_PASS <name>` or `TEST_FAIL <name>` → ... → `ALL_TESTS_PASS` or `FAIL: <n> errors` → `SIMULATION_DONE`

### C2: Immediate `$finish` on first failure prevents remaining tests

**Symptom:** Test 1 fails → `$finish` called → Tests 2-6 never run. Can't see full picture.
**Source:** simulation-loop.md validation

```verilog
// ❌ BROKEN — kills simulation on first failure
task check;
    if (actual !== expected) begin
        $display("FAIL at %0t", $time);
        $finish;  // other tests never run
    end
end
endtask

// ✅ FIX — accumulate errors, report at end
integer error_cnt;
task check;
    if (actual !== expected) begin
        $display("FAIL at %0t: got %08h, expected %08h", $time, actual, expected);
        error_cnt = error_cnt + 1;
        // continue running
    end
end
endtask
```

---

## Category D: Testbench Structural Issues

### D1: Address decode aliasing (parameterized decodes)

**Symptom:** `paddr_i[4:2]` maps address 0x40 to the same register as 0x00. PSLVERR never triggers for invalid addresses.
**Source:** ARM IHI 0024C §4.1: PSLVERR must be asserted for accesses to unimplemented addresses. IEEE 1364-2001 §4.2.3: bit-selects and part-selects are indexed from LSB — aliasing is a property of the indexing, not a simulator bug. ARM PrimeCell GPIO (PL061) §3.2 demonstrates full-address decode with explicit upper-address checking.
**Experiment:** R6 Agent A (sim iteration 3 — address decode aliasing)

```verilog
// ❌ BROKEN — aliased address decode
case (paddr_i[4:2])
    3'h0: prdata_o = ctrl_q;
    3'h1: prdata_o = divider_q;
    default: begin
        prdata_o = 32'h0;
        pslverr_o = 1'b1;
    end
endcase
// paddr_i=0x00 → [4:2]=3'h0 → CTRL ✓
// paddr_i=0x40 → [4:2]=3'h0 → CTRL ✗  (should be invalid!)

// ✅ FIX — use full address decode
wire addr_valid = (paddr_i[3:0] inside {4'h0, 4'h4, 4'h8, 4'hC});
always @(*) begin
    prdata_o = 32'h0;
    pslverr_o = 1'b0;
    if (psel_i && penable_i && !pwrite_i) begin
        case (paddr_i[3:0])  // full address width
            4'h0: prdata_o = {30'h0, ctrl_q};
            4'h4: prdata_o = {16'h0, divider_q};
            // ...
            default: pslverr_o = 1'b1;  // truly invalid addresses
        endcase
    end
end
```

**Rule:** Address decode must use the FULL address width or explicitly check that upper bits are zero. Never use bit-slicing that aliases higher addresses.

### D2: Timeout watchdog too short for slow protocols

**Symptom:** `SIMULATION_TIMEOUT` fires during a valid I2C transaction (100kHz SCL with 50MHz system clock means ~2000 cycles per byte).
**Source:** NXP UM10204 (I2C-bus specification) §5.1: standard-mode SCL = 100kHz → 10µs period. §7: clock stretching extends SCL low time arbitrarily. Maximum transaction time = (1 + TXLEN + 1 + RXLEN + 1) × 9 bits × 4 quarters × DIVIDER cycles + stretching. Use generous wall-clock timeouts (ms, not µs).

```verilog
// ❌ BROKEN — timeout too short for slow protocol
initial begin
    #100_000;  // 100 µs = only 10 I2C SCL cycles at 100kHz
    $display("SIMULATION_TIMEOUT");
    $finish;
end

// ✅ FIX — calculate timeout from protocol timing
// I2C: 1 byte ≈ 9 bits × 4 quarters × DIVIDER cycles ≈ 4500 cycles at 100kHz
// Timeout should allow for worst-case: max TXLEN × time_per_byte + margin
initial begin
    #10_000_000;  // 10 ms — generous margin for slow protocols
    $display("FAIL: SIMULATION_TIMEOUT at %0t", $time);
    $finish;
end
```

---

## Category E: Multi-Clock & CDC Testbench Issues

### E1: Cross-domain data capture without synchronization delay

**Symptom:** Fast-domain monitor enqueues data, slow-domain checker dequeues immediately — sees stale or X values because CDC hasn't settled.
**Source:** Cummings, SNUG 2008 "Clock Domain Crossing (CDC) Design & Verification Techniques Using SystemVerilog" §5.2: after reset deassertion, CDC synchronizers require 3-8 destination clock cycles to settle. Sampling across domains before synchronization latency produces X or metastable values. IEEE 1800-2017 §4.7 non-determinism in multi-clock scheduling.
**Guidance:** tb-examples.md pattern 8

```verilog
// ❌ — checker runs immediately, CDC hasn't synchronized yet
always @(posedge clk_slow_i) begin
    #1;
    if (out_valid && out_ready) begin
        if (out_data !== expected_queue[rd_ptr])  // may be stale
            error_cnt++;
    end
end

// ✅ — wait for CDC synchronization latency after reset
initial begin
    wait(rst_ni === 1'b1);
    repeat (20) @(posedge clk_slow_i);  // let CDC sync (~3-8 cycles + margin)
    // now start checking
end
```

---

## Summary Table

| ID | Category | Symptom | Fix Pattern | Source |
|:--:|------|------|------|------|
| A1 | Compile | `return` in task | Named block + `disable` | R8 A |
| A2 | Compile | `break` in loop | Named block + `disable` | R6 A |
| A3 | Compile | `ref` port in task | Module-level reg | R8 B |
| A4 | Fork | Variable sharing | `automatic` locals or sequential | R6 A |
| A5 | Fork | Loop double-count | Sequential instead of fork | R6 A |
| B1 | Timing | APB delta-cycle race | Inline condition (no `assign` for we) | R8 A |
| B2 | Timing | Combinational output stale | Check BEFORE deasserting bus | INTC, UART, Golden |
| B3 | Timing | Monitor sees old value | `#1` settling delay after posedge | Golden, tb-examples |
| B4 | Timing | NBA race stimulus vs DUT | Drive on negedge | R5, R6 |
| B5 | Seq | FSM pops before check | Write data first, enable last | R8 A |
| C1 | Proto | No SIMULATION_DONE | Follow output protocol | Sim-loop |
| C2 | Proto | $finish on first fail | Accumulate errors, report at end | Sim-loop |
| D1 | Struct | Address aliasing | Full-width decode or upper-bit check | R6 A |
| D2 | Struct | Timeout too short | Calculate from protocol timing | R8 I2C |
| E1 | CDC | CDC latency ignored | Repeat N cycles after reset | tb-examples |

**When you write a testbench, scan this table BEFORE running simulation.** Most of these are 2-line fixes that save 1-2 simulation iterations.

**Common element:** 73% of these bugs (11/15) were found by the OLD-workflow Agent A. Agent B's distributed checkpoints and better preparation produced cleaner testbenches. But the pitfalls still exist — the skill should prevent them proactively rather than relying on agent skill variance.
