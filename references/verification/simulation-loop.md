# Simulation Loop — Tool-Driven Verification

## Purpose

Close the verification loop: generate RTL → lint → compile → simulate → analyze → fix → re-simulate. This file defines the complete workflow an AI agent should follow when simulation tools are available.

**Authority:** Phase ordering (lint before compile, compile before simulate, fix-and-rerun with constraints) follows:
- IEEE 1364-2001 §5.3 (stratified event queue) and IEEE 1800-2017 §4.7 (scheduling semantics) for understanding simulation behavior
- Cummings, SNUG 2000 "Nonblocking Assignments" §8 for NBA-region timing in failure analysis
- Mentor/Siemens Verification Academy "Verification Planning and Management" for regression methodology (max iterations, pass/fail protocol)
- Verilator Manual §4 (linting), Icarus Verilog Wiki (simulator limitations) for tool-specific behavior
- The output protocol (`SIMULATION_START` → `RESET_RELEASED` → `TEST_START/PASS/FAIL` → `ALL_TESTS_PASS` → `SIMULATION_DONE`) is adapted from Accellera UVM 1.2 §4.9 end-of-test reporting

## Prerequisites

Before starting the simulation loop, check tool availability:

```bash
verilator --version    # lint (priority 1, preferred)
yosys -V               # lint (priority 1, fallback when verilator unavailable)
iverilog -V            # compile + simulate (priority 2)
vvp -V                 # simulation runtime
gtkwave --version      # optional: waveform viewer (agent cannot use GUI, but can parse VCD)
```

**Environment setup:** Yosys from oss-cad-suite requires DLLs in PATH. If `yosys -V` fails with STATUS_DLL_NOT_FOUND (0xC0000135), source the environment first:
```bash
call "path\to\oss-cad-suite\environment.bat"
```

**Path encoding:** Tools may fail when the working directory contains non-ASCII characters (CJK, accented). If tools report file-not-found or encoding errors, copy source files to an ASCII-only temp directory:
```bash
mkdir C:\temp_sim
copy *.v C:\temp_sim\
cd C:\temp_sim
```

If no simulation tools are available, state this explicitly and fall back to static self-review only.

---

## Phase 1: Lint

Run lint **before** simulation. It catches structural errors without needing a testbench.

### Option A: Verilator (preferred)

```bash
verilator --lint-only -Wall \
    --top-module <top> \
    -I<include_dir> \
    <source_files> 2>&1
```

### Option B: Yosys (fallback when verilator unavailable)

```bash
yosys -p "read_verilog -sv <source_files>; check -assert; stat" 2>&1
```

**Yosys lint coverage (weaker than verilator):**

| Check | Verilator | Yosys |
|-------|-----------|-------|
| Latch inference | Yes (`LATCH`) | Yes (`check -assert`) |
| Undriven signals | Yes (`UNDRIVEN`) | Yes |
| Unused signals | Yes (`UNUSED`) | Yes |
| Width mismatch | Yes (`WIDTH`) | **No** |
| Blocking in clocked | Yes (`BLKSEQ`) | **No** |
| Implicit wires | Yes (`IMPLICIT`) | **No** |
| Incomplete case | Yes (`CASEINCOMPLETE`) | **No** |
| Combinational delay | Yes (`COMBDLY`) | **No** |

When using yosys, supplement with iverilog warnings during compile: `iverilog -g2012 -Wall` catches some width and implicit wire issues.

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

**Exception:** `UNUSED` warnings on output ports that are intentionally unconnected in a testbench can be suppressed with `-Wno-UNUSED` (verilator only).

**Fallback:** When verilator is unavailable, use yosys `check -assert` for basic structural checks. Supplement with `iverilog -g2012 -Wall` during compile for width/implicit warnings. Document which checks were skipped.

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

Evaluate in this priority order (first match wins):

| Priority | Result | Output pattern | Action |
|----------|--------|---------------|--------|
| 1 | **HANG** | timeout killed, no `SIMULATION_DONE` | → Phase 5 |
| 2 | **PASS** | `ALL_TESTS_PASS` present | Done — report success |
| 3 | **FAIL** | `TEST_FAIL` present | Extract test_id and reason → Phase 4 |
| 4 | **FATAL** | `$fatal` or `$finish` without `ALL_TESTS_PASS` | → fallback check |
| 5 | **COMPILE_ONLY** | no output at all (empty stdout) | Testbench never started — check clock/reset |

### Fallback: non-compliant testbenches

Existing testbenches may not follow the output protocol (they were written before this standard). When the classification yields FATAL or COMPILE_ONLY but the output is non-empty, apply this fallback:

1. Check if output contains a PASS-like pattern: `"PASS"`, `"OK"`, `"ALL TESTS PASSED"`, `"$finish"` with no preceding `"FAIL"` or `"ERROR"`
2. Check if output contains a FAIL-like pattern: `"FAIL"`, `"ERROR"`, `"ASSERT"`, `"mismatch"`
3. If PASS-like found and no FAIL-like found → classify as **PASS (non-compliant output)**, report success with a note that the testbench should be updated to use the standard protocol
4. If FAIL-like found → classify as **FAIL**, extract the failure message and proceed to Phase 4
5. If neither → classify as **UNKNOWN**, re-run with verbose output or inspect VCD

**Example non-compliant output and classification:**
```
PASS round robin arbiter        → PASS (non-compliant): contains "PASS", no "FAIL"
tb.v:488: $finish called at ... → $finish without ALL_TESTS_PASS, but preceded by PASS
```

---

## Phase 4: Failure Analysis

When a test fails, follow this procedure:

### Step 0: Classify the failure type

Before pattern matching, classify the failure to choose the right debug approach:

| Failure type | How to recognize | Debug approach |
|-------------|-----------------|----------------|
| **Structural** | lint warning, compilation error | Fix with coding guidelines (E1-E8) |
| **Protocol** | handshake violation message, assertion failure | Match against bug patterns H/P |
| **Functional** | output value wrong, zero when non-zero expected | Golden reference comparison (golden-reference-guide.md) |
| **Hang** | timeout, no SIMULATION_DONE | Phase 5 |

For **functional failures** (wrong output values), the primary debug approach is:
1. Identify which golden reference strategy applies (see `references/verification/golden-reference-guide.md`)
2. Add or activate the golden reference checker in the testbench
3. Run simulation to find the first divergent value
4. Trace backward from the wrong output to the logic error

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
| "Output is zero when non-zero expected" | P18 (pipeline latency) or computation logic error |
| "Output matches INIT_VALUE, not computed value" | P18: combinational reads stale register |
| "Data corruption through module" | H1 (payload under stall) or DP1 (width converter) |
| "Transfer never completes" | P4 (completion logic), H4 (deadlock), or counter bug |
| "Readback mismatch" | register write path bug, address decode error |
| "Structural PASS but functional FAIL" | V1 (verification blind spot) — see golden-reference-guide.md |

### Step 3: If no pattern matches — first divergent cycle

1. Enable VCD dump in testbench: `initial begin $dumpfile("sim.vcd"); $dumpvars(0, tb_top); end`
2. Re-run simulation
3. Use the VCD helper script to extract target signals and find divergences:
   ```bash
   python scripts/vcd_extract.py sim.vcd --signals <suspect_signals> --range <start>:<end>
   python scripts/vcd_extract.py sim.vcd --find-violation valid-drop --signals valid,ready
   python scripts/vcd_extract.py sim.vcd --protocol axi-write
   ```
   See `references/verification/vcd-analysis-guide.md` for full VCD analysis methodology.
4. Trace the signal path backward from the divergent output to find the root cause

### Step 4: Apply minimal fix

- Change the smallest number of lines that address the root cause
- Do not refactor surrounding code
- Re-run lint after the fix to check for new warnings

### Step 5: Re-simulate

Go back to Phase 1 (lint) → Phase 2 (compile) → Phase 3 (simulate). Maximum 3 iterations. After 3 failures, report:
- What was tried (each fix)
- What the tool output shows (each failure)

### Step 6: Functional regression after fix

After a fix passes re-simulation, verify functional correctness:
1. Run the golden reference test that caught the original failure
2. If no golden reference existed, add one (see `references/verification/golden-reference-guide.md`)
3. Run at least one end-to-end data integrity test
4. Report: "Structural PASS + Functional PASS" or list remaining functional gaps
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

- [ ] Lint passes with no errors (verilator preferred; yosys `check -assert` as fallback)
- [ ] iverilog compiles all source files without errors (use `-Wall` for extra warnings)
- [ ] Testbench follows output protocol (RESET_RELEASED, TEST_START/PASS/FAIL, ALL_TESTS_PASS)
- [ ] If testbench is non-compliant: apply fallback classification (PASS-like/FAIL-like pattern matching)
- [ ] Simulation completes within timeout (no hang)
- [ ] All directed tests pass
- [ ] If any test fails: bug pattern matched, fix applied, re-simulation passed (max 3 iterations)
- [ ] If 3 iterations exhausted: residual issues reported with evidence
- [ ] At least one golden reference test exists (see golden-reference-guide.md for strategy selection)
- [ ] Golden reference test passes (functional correctness, not just structural)

When yosys is available (after simulation passes):

- [ ] Yosys synthesis completes without errors
- [ ] No latch inference (`$_DLATCH_*` absent from cell list)
- [ ] No combinational loops (real loops, not register feedback false positives)
- [ ] Critical path length reasonable (ltp < 25 gates for 100MHz target)
- [ ] Cell count within expectations
- [ ] Synthesis issues fixed → re-simulation confirms functionality preserved
