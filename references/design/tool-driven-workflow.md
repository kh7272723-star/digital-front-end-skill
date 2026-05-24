# Tool-driven verification workflow

## Purpose

This file makes tool-based verification a required step, not an afterthought.
When Icarus Verilog is available, the agent must run the generated RTL through `scripts/rtl_check.py`, interpret the output, and iterate fixes before presenting the final result.

## When to invoke tools

- After generating RTL and testbench for any nontrivial module.
- After fixing a bug reported by the user.
- After modifying existing RTL that has a fixture or trial.
- When the user asks for verification, simulation, or debug evidence.

Do not claim simulation correctness without running a tool. Do not present unrun testbenches as proof.

## Tool availability check

Before invoking tools, check what is installed:

```
which iverilog    # required for rtl_check.py
which vvp         # required for rtl_check.py
which verilator   # optional: lint-only check
which yosys       # optional: synthesis sanity check
```

If `iverilog` or `vvp` is unavailable, state that tool verification was skipped and why. Do not pretend checks were run.

## rtl_check.py usage

### Writing a fixture directory

To verify newly generated RTL, write a temporary fixture directory:

```
evals/trials/<module_name>/
  manifest.json
  <module>.v
  tb.v
```

The manifest format:

```json
{
  "name": "<module_name>",
  "top": "<testbench_top_module>",
  "sources": ["<module>.v"],
  "testbench": "tb.v",
  "expected": {
    "result": "pass",
    "contains": ["PASS <module_name>"]
  },
  "timeout_seconds": 10
}
```

For bug fixtures where the expected result is a known failure:

```json
{
  "expected": {
    "result": "fail",
    "contains": ["EXPECTED_<SIGNATURE>"]
  }
}
```

### Running the checker

```
python scripts/rtl_check.py --case evals/trials/<module_name>
```

With optional Verilator and Yosys checks:

```
python scripts/rtl_check.py --case evals/trials/<module_name> --optional-tools
```

### Output format

```
CASE: <name>
EXPECTED_RESULT: pass/fail
ACTUAL_RESULT: pass/fail
EXPECTED_TOKENS_FOUND: true/false
RTL_CHECK_RESULT: PASS/FAIL
LOG_EXCERPT:
## compile
<iverilog output>
## run
<vvp output>
## verilator
<verilator output or SKIP>
## yosys
<yosys output or SKIP>
```

## Output interpretation rules

### Compilation errors

| Error pattern | Meaning | Fix direction |
|---|---|---|
| `syntax error` | Missing begin/end, semicolon, parenthesis, or keyword | Check block structure and punctuation |
| `undeclared signal` | Signal used without wire/reg declaration | Add declaration or check port spelling |
| `cannot be driven by` | Signal driven from wrong block type | Check always vs assign ownership |
| `incomplete case` or `incomplete if` | Missing branch in combinational logic | Add default or missing branches |
| `width mismatch` | Assignment width does not match target | Check parameter propagation and explicit widths |
| `ambiguous` or `multi-driven` | Multiple drivers for one signal | Ensure one driver per signal |
| `timescale` or `delay` | Timing or delay syntax issue | Remove delays from synthesizable code |

### Simulation failures

| Output pattern | Meaning | Fix direction |
|---|---|---|
| `$fatal` triggered | Assertion or check failed in testbench | Read the fatal message; fix the RTL condition it checks |
| `EXPECTED_*_FAIL` | Known bug pattern reproduced | Match against bug-pattern-library.md and apply known fix |
| No output / timeout | Simulation hangs | Check clock generation, reset release, handshake deadlock |
| `finish` without PASS | Test completed but did not print PASS | Check testbench logic and DUT response |
| Wrong value in check | RTL output does not match expected | Trace the signal path; check combinational vs registered timing |

### Verilator lint warnings

| Warning pattern | Meaning | Fix direction |
|---|---|---|
| `WIDTH` | Width mismatch or truncation | Add explicit width casts or fix source width |
| `UNUSED` | Unused signal | Remove or prefix with underscore |
| `UNDRIVEN` | Signal declared but never driven | Add assignment or remove declaration |
| `LATCH` | Inferred latch in combinational logic | Add default assignment or complete case coverage |
| `LOOP` | Combinational loop detected | Break the loop with registered logic |

### Yosys synthesis notes

| Output pattern | Meaning | Fix direction |
|---|---|---|
| `ERROR` | Synthesis cannot process the code | Fix unsupported constructs or syntax |
| `Warning: latch` | Inferred latch | Add defaults to combinational blocks |
| `cells` count | Number of inferred cells | Use as area reference, not a fix target |

## Iterative fix flow

```
Iteration 1: Generate RTL + testbench, run rtl_check.py
  ├─ Compile PASS, Sim PASS → DONE
  ├─ Compile FAIL → fix syntax/declarations → Iteration 2
  └─ Compile PASS, Sim FAIL → analyze failure → Iteration 2

Iteration 2: Apply fix, re-run rtl_check.py
  ├─ PASS → DONE
  ├─ Compile FAIL → undo and try different fix → Iteration 3
  └─ Sim FAIL → match bug pattern or reason from evidence → Iteration 3

Iteration 3: Apply second fix, re-run rtl_check.py
  ├─ PASS → DONE
  └─ FAIL → report residual issues, state what was tried and why it failed
```

After 3 iterations, stop and report:
- What was tried
- What the tool output shows
- What the likely root cause is
- What the user should investigate next

## Testbench requirements for tool verification

A testbench that works with rtl_check.py must:

1. Generate a clock signal.
2. Apply reset.
3. Run directed test scenarios.
4. Print `PASS <name>` on success.
5. Use `$fatal` or `$finish` with an error message on failure.

Minimal testbench skeleton:

```verilog
module tb_<name>;
  reg clk_i;
  reg rst_i;
  // ... DUT signals ...

  <module_name> dut (
    // ... port connections ...
  );

  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    rst_i = 1;
    // ... initialize inputs ...
    repeat (2) @(posedge clk_i);
    rst_i = 0;

    // Test 1: normal operation
    // ... stimulus ...
    @(posedge clk_i);
    #1;
    if (/* check */)
      $fatal(1, "Test 1 failed: <description>");

    // Test 2: boundary case
    // ... stimulus ...

    $display("PASS <name>");
    $finish;
  end
endmodule
```

## Integration with bug pattern library

When rtl_check.py reports a failure:

1. Check if the failure signature matches a known pattern from `references/debug/bug-pattern-library.md`.
2. If it matches, apply the pattern's known fix.
3. If it does not match, use the first-divergent-cycle method from the log output.
4. After fixing, re-run rtl_check.py to confirm.

## Tool output as evidence

When presenting results to the user:

- Quote the `RTL_CHECK_RESULT: PASS` or `FAIL` line.
- If FAIL, quote the specific error or `$fatal` message.
- If fixes were iterated, show what changed at each iteration.
- State which tools were run and which were skipped (and why).
