# Simulation Loop — Tool-Driven Verification

## Purpose

Close the verification loop: generate RTL → lint → compile → simulate → analyze → fix → re-simulate. This file defines the complete workflow an AI agent should follow when simulation tools are available.

## Prerequisites

Before starting the simulation loop, check tool availability:

```bash
verilator --version    # lint (priority 1)
iverilog -V            # compile + simulate (priority 2)
vvp -V                 # simulation runtime
gtkwave --version      # optional: waveform viewer (agent cannot use GUI, but can parse VCD)
```

If no simulation tools are available, state this explicitly and fall back to static self-review only.

---

## Phase 1: Lint (Verilator)

Run Verilator lint **before** simulation. It catches structural errors without needing a testbench.

```bash
verilator --lint-only -Wall \
    --top-module <top> \
    -I<include_dir> \
    <source_files> 2>&1
```

### Verilator warning categories and fixes

| Warning | Code | Meaning | Fix |
|---------|------|---------|-----|
| `MULTIDRIVEN` | — | Signal driven from multiple blocks | Merge into single driver (E1) |
| `WIDTH` | — | Width mismatch or implicit truncation | Add explicit part-select (E3) |
| `BLKSEQ` | — | Blocking `=` in clocked block | Change to `<=` (E4) |
| `LATCH` | — | Inferred latch in combinational block | Add default assignment (E2) |
| `UNDRIVEN` | — | Signal declared but never driven | Add assignment or remove (E8) |
| `UNUSED` | — | Signal driven but never read | Remove or use (E8) |
| `COMBDLY` | — | Delay in combinational block | Remove `#delay` from synthesizable code |
| `INITIALDLY` | — | Initial delay in non-initial block | Use `@(posedge clk)` instead |
| `CASEINCOMPLETE` | — | Missing case branches | Add `default` (C2) |
| `CASEOVERLAP` | — | Overlapping case items | Fix case conditions |
| `IMPLICIT` | — | Implicit wire declaration | Add `` `default_nettype none `` (E8) |

### Lint-first rule

Always run lint before simulation. A module that fails lint will produce unpredictable simulation results. Fix all lint warnings before writing a testbench.

**Exception:** `UNUSED` warnings on output ports that are intentionally unconnected in a testbench can be suppressed with `-Wno-UNUSED`.

---

## Phase 2: Compile (Icarus Verilog)

For multi-module designs, compile all source files together:

```bash
iverilog -g2012 -o sim.vvp \
    -I<include_dir> \
    <all_source_files> \
    <testbench_file> 2>&1
```

Flags:
- `-g2012`: enable SystemVerilog features (for SVA assertions)
- `-o sim.vvp`: output compiled simulation binary
- `-I<dir>`: include directory for header files

### Compilation error patterns

| Error | Meaning | Fix |
|-------|---------|-----|
| `syntax error, unexpected ...` | Missing semicolon, begin/end, parenthesis | Check block structure near the error line |
| `... is not a valid l-value` | Assigning to a wire from an `always` block | Change wire to reg, or use assign |
| `... is already declared` | Duplicate signal declaration | Remove duplicate |
| `cannot be driven by ...` | Port direction mismatch | Check input/output/inout |
| `unknown module` | Missing source file or wrong module name | Add source file or check instantiation |
| `width mismatch` | Assignment width does not match | Add explicit cast or fix width |

---

## Phase 3: Simulate (vvp)

Run the compiled simulation with a timeout:

```bash
timeout <seconds> vvp sim.vvp +vcd=<waveform.vcd> 2>&1
```

### Simulation output protocol

The testbench must follow this output protocol for automated parsing:

```
RESET_RELEASED           — printed after reset deasserts
TEST_START <test_id>     — printed before each test
TEST_PASS <test_id>      — printed when test passes
TEST_FAIL <test_id> <reason> — printed when test fails
ALL_TESTS_PASS           — printed when all tests pass
SIMULATION_DONE          — printed at end of simulation
```

**Output volume management:** For multi-test runs or large transfers (>256 beats), limit per-beat debug output. Use `$display` only at test boundaries (pass/fail/id). Disable per-beat logging after first failure diagnosis — a multi-burst transfer can produce thousands of per-beat lines that overflow context windows:

```verilog
// In testbench: gate per-beat debug on a verbosity flag
`ifdef VERBOSE
    always @(posedge clk_i)
        if (handshake_fire)
            $display("BEAT: addr=%08h data=%08h", addr, data);
`endif
```

Enable verbose mode only in Phase 4 (failure analysis) and disable before re-simulation. The output protocol markers (TEST_START/PASS/FAIL) are sufficient for result parsing — per-beat traces are diagnostic only.

Example testbench output:
```
RESET_RELEASED
TEST_START test_normal_burst
TEST_PASS test_normal_burst
TEST_START test_boundary_4kb
TEST_PASS test_boundary_4kb
TEST_START test_backpressure
TEST_FAIL test_backpressure: WVALID deasserted mid-burst at cycle 142
ALL_TESTS_PASS
SIMULATION_DONE
```

### Simulation result classification

| Result | Output pattern | Action |
|--------|---------------|--------|
| **PASS** | `ALL_TESTS_PASS` present | Done — report success |
| **FAIL** | `TEST_FAIL` present | Extract test_id and reason → Phase 4 |
| **HANG** | timeout killed, no `SIMULATION_DONE` | → Phase 5 |
| **COMPILE_ONLY** | no `RESET_RELEASED` | Testbench never started — check clock/reset |
| **FATAL** | `$fatal` or `$finish` without `ALL_TESTS_PASS` | Extract fatal message → Phase 4 |

---

## Phase 4: Failure Analysis

When a test fails, follow this procedure:

### Step 1: Extract the failure signature

From the simulation output, extract:
- Which test failed (`test_id`)
- What the failure message says (`reason`)
- At what simulation time or cycle it failed

### Step 2: Match against bug patterns

Check the failure against `references/debug/bug-pattern-library.md`:

| Failure message pattern | Likely bug pattern |
|------------------------|-------------------|
| "WVALID deasserted mid-burst" | P12 |
| "VALID dropped before READY" | H1, H8 |
| "Data changed while valid high" | H1 |
| "FIFO overflow/underflow" | H1 (boundary) |
| "FSM entered illegal state" | C2 |
| "Latch inferred" | C3, E2 |
| "Multi-driven net" | E1 |
| "Timeout — no done_o" | P4 (completion) or handshake deadlock |
| "B response error not captured" | DP5 |
| "AW/W/B coupled" | P13 |

If a pattern matches, apply the known fix from the pattern library.

### Step 3: If no pattern matches — first divergent cycle

1. Enable VCD dump in testbench: `initial begin $dumpfile("sim.vcd"); $dumpvars(0, tb_top); end`
2. Re-run simulation
3. Use `$display` probes to identify the first cycle where actual behavior diverges from expected
4. Trace the signal path backward from the divergent output to find the root cause

### Step 4: Apply minimal fix

- Change the smallest number of lines that address the root cause
- Do not refactor surrounding code
- Re-run lint after the fix to check for new warnings

### Step 5: Re-simulate

Go back to Phase 1 (lint) → Phase 2 (compile) → Phase 3 (simulate). Maximum 3 iterations. After 3 failures, report:
- What was tried (each fix)
- What the tool output shows (each failure)
- What the likely root cause is
- What the user should investigate next

---

## Phase 5: Hang Detection and Recovery

Simulation hangs when:
- Clock never starts (missing `forever #5 clk = ~clk`)
- Reset never releases (rst_i stays high)
- Handshake deadlock (both sides wait for each other)
- Infinite loop in FSM (state never transitions)

### Hang recovery procedure

1. **Check timeout output:** `timeout` kills the process and exits with code 124
2. **Add cycle counter to testbench:**
```verilog
integer cycle_cnt;
always @(posedge clk_i) cycle_cnt <= cycle_cnt + 1;
initial begin
    cycle_cnt = 0;
end
// In test:
always @(posedge clk_i) begin
    if (cycle_cnt > MAX_CYCLES) begin
        $display("HANG: exceeded %0d cycles at time %0t", MAX_CYCLES, $time);
        $finish;
    end
end
```
3. **Add handshake monitors:**
```verilog
// Monitor for handshake deadlock
always @(posedge clk_i) begin
    if (m_axi_awvalid_o && !m_axi_awready_i) begin
        aw_stall_cnt <= aw_stall_cnt + 1;
        if (aw_stall_cnt > 1000)
            $display("WARNING: AW stalled for %0d cycles", aw_stall_cnt);
    end else begin
        aw_stall_cnt <= 0;
    end
end
```

---

## Integration with rtl_check.py

For projects that use the existing `scripts/rtl_check.py`:

```bash
# Single module check
python scripts/rtl_check.py --case evals/trials/<module_name>

# With optional tools
python scripts/rtl_check.py --case evals/trials/<module_name> --optional-tools

# Multi-file project (manual iverilog)
iverilog -g2012 -o sim.vvp rtl/*.v tb/tb_top.v
timeout 30 vvp sim.vvp
```

The `rtl_check.py` script handles manifest-based pass/fail checking. For multi-module projects that don't fit the manifest format, use the manual iverilog/vvp flow described in this file.

---

## Testbench generation template (simulation-loop compatible)

```verilog
`default_nettype none
`timescale 1ns / 1ps

module tb_<module_name>;
    // Clock and reset
    reg clk_i;
    reg rst_i;

    // DUT signals
    // ... (match DUT port list)

    // Test infrastructure
    integer cycle_cnt;
    integer test_cnt;
    integer pass_cnt;
    integer fail_cnt;

    // DUT instantiation
    <module_name> dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        // ... port connections
    );

    // Clock generation
    initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i;
    end

    // Cycle counter (for hang detection)
    always @(posedge clk_i) cycle_cnt <= cycle_cnt + 1;

    // Timeout watchdog
    initial begin
        #1_000_000;  // 1ms timeout
        $display("FAIL: simulation timeout at %0t", $time);
        $finish;
    end

    // VCD dump (for waveform analysis)
    initial begin
        $dumpfile("sim.vcd");
        $dumpvars(0, tb_<module_name>);
    end

    // Helper tasks
    task reset;
        begin
            rst_i = 1;
            // Initialize all inputs to safe defaults
            // ...
            repeat (4) @(posedge clk_i);
            rst_i = 0;
            repeat (2) @(posedge clk_i);
            $display("RESET_RELEASED");
        end
    endtask

    task check;
        input integer test_id;
        input condition;
        input [255:0] fail_msg;
        begin
            if (condition)
                $display("TEST_PASS test_%0d", test_id);
            else begin
                $display("TEST_FAIL test_%0d: %0s", test_id, fail_msg);
                fail_cnt = fail_cnt + 1;
            end
            test_cnt = test_cnt + 1;
        end
    endtask

    // Main test sequence
    initial begin
        cycle_cnt = 0;
        test_cnt  = 0;
        pass_cnt  = 0;
        fail_cnt  = 0;

        reset;

        // Test 1: Normal operation
        $display("TEST_START test_1_normal");
        // ... stimulus ...
        @(posedge clk_i);
        // ... check ...
        check(1, /* condition */, "normal operation failed");

        // Test 2: Boundary case
        $display("TEST_START test_2_boundary");
        // ... stimulus ...

        // Test 3: Backpressure
        $display("TEST_START test_3_backpressure");
        // ... stimulus ...

        // Summary
        if (fail_cnt == 0)
            $display("ALL_TESTS_PASS");
        else
            $display("FAIL: %0d of %0d tests failed", fail_cnt, test_cnt);

        $display("SIMULATION_DONE");
        $finish;
    end
endmodule
`default_nettype wire
```

---

## Simulation loop checklist (for SKILL.md step 9)

When simulation tools are available:

- [ ] Verilator lint passes with no errors (warnings acceptable with justification)
- [ ] iverilog compiles all source files without errors
- [ ] Testbench follows output protocol (RESET_RELEASED, TEST_START/PASS/FAIL, ALL_TESTS_PASS)
- [ ] Simulation completes within timeout (no hang)
- [ ] All directed tests pass
- [ ] If any test fails: bug pattern matched, fix applied, re-simulation passed (max 3 iterations)
- [ ] If 3 iterations exhausted: residual issues reported with evidence
