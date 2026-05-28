# Synthesis Feedback Guide — Yosys-Driven RTL Improvement

## Purpose

After simulation confirms functional correctness, run synthesis to find structural issues that simulation cannot detect: latch inference, unused logic, combinational depth, resource usage. This closes the loop: **simulate (correct) → synthesize (clean) → fix → re-simulate (still correct)**.

---

## When to Run Synthesis

**After simulation passes (Step 8b), before finalizing (Step 10).** Do NOT run synthesis before simulation — synthesis checks are about hardware quality, not functional correctness.

```
Step 7: Generate RTL
Step 8: Structural self-review
Step 8b: Functional simulation → PASS
Step 9: Synthesis feedback (THIS GUIDE) → fix issues
Step 10: Re-simulate to confirm fixes don't break functionality
```

---

## Prerequisites

Yosys requires DLLs in PATH:

```powershell
# PowerShell
$env:PATH = "path\to\oss-cad-suite\bin;path\to\oss-cad-suite\lib;" + $env:PATH

# Or call environment.bat first
call "path\to\oss-cad-suite\environment.bat"
```

---

## Yosys Commands

### Basic synthesis + check + stat

```bash
yosys -p "read_verilog -sv <sources>; synth -top <module>; check -assert; stat" 2>&1
```

### With longest path analysis

```bash
yosys -p "read_verilog -sv <sources>; synth -top <module>; check -assert; stat; ltp" 2>&1
```

### RTL-only check (no synthesis, faster)

```bash
yosys -p "read_verilog -sv <sources>; hierarchy -check; proc; check -assert" 2>&1
```

---

## What Yosys Reports

### 1. `check -assert` — Structural Problems

| Check | Meaning | RTL Issue |
|-------|---------|-----------|
| Latch inference | Combinational block missing default | E2 violation |
| Undriven wire | Wire declared but never assigned | E8 violation |
| Multi-driven net | Wire driven by multiple sources | E1 violation |
| Unused port | Module port not connected | Integration issue |
| Comb loop | Combinational feedback loop | E7 violation |

### 2. `stat` — Resource Usage

```
=== module_name ===
   Number of wires:                 92
   Number of wire bits:            152
   Number of ports:                  9
   Number of port bits:             54
   Number of memories:               0
   Number of processes:              0
   Number of cells:                104
     $_ANDNOT_                      31
     $_MUX_                         10
     $_NAND_                         3
     $_NOR_                         22
     $_NOT_                          2
     $_ORNOT_                       15
     $_OR_                           8
     $_SDFFE_PP0N_                   1
     $_SDFFE_PP0P_                  12
```

**Key metrics:**

| Metric | What to look for |
|--------|-----------------|
| `$_SDFFE_*` count | Number of flip-flops (should match expected register count) |
| `$_DLATCH_*` presence | **Latch inference — always a bug in synchronous design** |
| Total cells | Rough area estimate; compare across implementations |
| `Number of memories` | Should be 0 for register-based designs; >0 means inferred RAM |
| `Number of processes` | Should be 0 after synthesis; >0 means un-synthesizable constructs |

### 3. `ltp` — Longest Topological Path (Critical Path)

```
Longest topological path in module_name (length=22):
    0: \valid_i [3]
    1: $abc$new_n74 (via ...)
    ...
   22: \data_o [7]
```

**What this tells you:**
- **Length** = number of combinational gates in the critical path
- Longer path = lower Fmax
- Typical target: < 20 gates for 100MHz, < 10 gates for 500MHz+
- **Loop warnings** = combinational feedback (E7 violation)

### 4. Warnings During Synthesis

| Warning | Meaning | Action |
|---------|---------|--------|
| `Detected loop at signal` | Combinational feedback | Check E7, add register break |
| `found latch` | Incomplete case/if in combinational block | Add default assignment |
| `wire is used but has no driver` | Signal read but never assigned | Assign or remove |
| `replacing memory with list of registers` | Memory too small for SRAM inference | Expected for small FIFOs |

---

## Synthesis → RTL Problem Mapping

| Yosys Finding | RTL Problem | Fix | Bug Pattern |
|---------------|-------------|-----|-------------|
| `$_DLATCH_*` in cell list | Latch inference | Add `default` to combinational block | E2 |
| `Detected loop` in ltp | Combinational feedback | Add register in feedback path | E7 |
| Large gate count vs expected | Unnecessary logic | Simplify conditionals, remove dead code | — |
| `$_SDFFE_PP0N_` count ≠ expected | Missing or extra registers | Check register declarations | E6 |
| More MUX than expected | Over-complex mux tree | Use casez or priority encoder | — |
| High ltp length (>25) | Combinational depth too large | Pipeline the critical path | — |
| Memory count > 0 for FIFO | Inferred RAM (may be intentional) | Verify dual-port requirements | — |

---

## Synthesis Feedback Workflow

### Step 1: Run synthesis

```bash
yosys -p "read_verilog -sv module.v; synth -top module; check -assert; stat; ltp" 2>&1 > synth_report.txt
```

### Step 2: Check for critical issues

1. Search for `DLATCH` in cell list → latch inference (must fix)
2. Search for `loop` in ltp output → combinational feedback (must fix)
3. Search for `found` or `warning` → synthesis warnings
4. Compare cell count against expectations

### Step 3: Map issues to RTL

For each yosys finding:
1. Identify the RTL source (yosys reports source line numbers in warnings)
2. Match against bug pattern library
3. Apply the fix from the pattern
4. Re-run synthesis to confirm the issue is resolved

### Step 4: Re-simulate

After fixing synthesis issues, re-run simulation to confirm functionality is preserved:
```bash
iverilog -g2012 -o sim.vvp module.v tb.v
vvp sim.vvp
```

---

## Example: Detecting Latch in Arbiter

**Yosys output:**
```
Warning: found latch in module rr_ready_valid_arbiter at line 99
```

**RTL source (line 99):**
```verilog
always @(*) begin
    ready_o = 4'b0000;
    if (accept_input) begin  // BUG: no default for ready_o when !accept_input
        case (grant_sel)
            ...
        endcase
    end
end
```

**Wait — this is actually correct.** The `ready_o = 4'b0000` at line 100 IS the default. Yosys may still report a latch if the case statement inside doesn't cover all values. Check the actual yosys warning carefully before fixing.

**Lesson:** Not every yosys warning is a real bug. Verify against RTL source before changing code.

---

## Limitations

- Yosys synthesis is technology-independent (no target library). Cell counts are structural, not area/timing.
- `ltp` reports topological path length, not actual timing. Real critical path depends on target library and P&R.
- Yosys cannot detect CDC issues, protocol violations, or functional bugs.
- Yosys `check -assert` is weaker than verilator `--lint-only -Wall` for RTL linting.
- For FPGA targets, use `synth_xilinx` or `synth_intel_alm` instead of generic `synth` for more accurate resource estimates.

---

## Integration with SKILL.md

This guide is referenced in SKILL.md Step 9 (Synthesis verification). The workflow is:

1. Simulation passes (Step 8b)
2. Run yosys synthesis (this guide)
3. Fix any synthesis issues found
4. Re-simulate to confirm (Step 8b again)
5. Report: simulation PASS + synthesis clean
