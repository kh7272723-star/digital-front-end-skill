# Engineering Intuition Checklist

## Purpose

Convert experienced engineer intuition into actionable, checkable rules for RTL self-review (SKILL.md Step 8). Each rule has a quantitative threshold, authoritative source, and fix suggestion.

These are heuristics, not hard limits. Use judgment — a 55-line combinational block in a one-off testbench is fine; the same in a reusable IP block is not.

---

## A. Code Complexity

**Source:** Keating & Bricaud, "Reuse Methodology Manual for System-on-a-Chip Designs" (RMM), Chapter 7; IEEE 1800-2017 Section 12.4.

| ID | Check | Threshold | Source | Fix |
|----|-------|-----------|--------|-----|
| C1 | `always @(*)` block line count | > 50 lines | RMM §7.3 | Extract sub-expressions into named wires; split into multiple combinational blocks by function; move logic into submodules |
| C2 | if-else nesting depth | > 3 levels | RMM §7.4 | Use `case`/`casez`; use early-return pattern (`if (!en) begin out=0; end else begin ...`) |
| C3 | Single module line count | > 300 lines | RMM §7.2 | Decompose into submodules with clear interfaces; each submodule < 200 lines |
| C4 | Signal fanout (reference count) | > 50 references | Synopsys DC, Xilinx UG949 §Fanout | Insert register stages or `MAX_FANOUT` attribute; use buffer tree |
| C5 | Registers in single `always @(posedge clk)` block | > 8 registers | NVMe Phase 3 Retrospective (2026-06-01) | Split by function: each block owns one concern (FIFO wr_ptr, FIFO rd_ptr, AW controller, W controller, etc.). Each block < 50 lines. See C20 in `rtl-coding-standards.md`. |
| C6 | Single `always @(posedge clk)` block line count | > 50 lines | NVMe Phase 3 Retrospective (2026-06-01) | Split by function. Monolithic blocks hide NBA ordering hazards and resist synthesis optimization. |

**Why these matter:** Long combinational blocks are hard to review, hard to debug, and produce deep logic that fails timing. High fanout signals create routing congestion and slow down the design. Monolithic sequential blocks mix unrelated registers, creating false synthesis dependencies and making NBA hazards nearly invisible in review.

---

## B. Combinational Depth

**Source:** Synopsys Design Compiler User Guide (Combinational Depth Analysis); Xilinx UG901 (Vivado Synthesis); Wakerly "Digital Design" §5.4.

| ID | Check | Threshold | Source | Fix |
|----|-------|-----------|--------|-----|
| D1 | Input-to-output combinational levels | > 7 gate levels | Synopsys DC timing analysis | Insert pipeline register; restructure logic to reduce depth |
| D2 | Wide comparator on critical path | > 32-bit comparison | Xilinx UG901 §Combinational Logic | Use hierarchical comparison (compare MSBs first, then LSBs); pipeline the comparison |
| D3 | Long priority chain (if-else if) | > 8 levels | Wakerly §5.4, Synopsys DC | Use `case`/`casez` for parallel decode; use one-hot priority encoder |
| D4 | Wide multiplexer | > 16:1 MUX | Xilinx UG901 §MUX Inference | Use hierarchical MUX tree; register the output; use `case` instead of nested ternary |

**Why these matter:** Each gate level adds ~30ps at 28nm. 7 levels = ~210ps. At 200MHz (5ns period), that's 4% of the budget on one path alone. Deeper paths leave no margin for wire delay, setup time, or clock skew.

---

## C. Area Red Flags

**Source:** RMM §6.2; Synopsys DC Area Optimization; Xilinx UG901 §RAM/DSP Inference; Intel UG-20136 §Memory.

| ID | Check | Threshold | Source | Fix |
|----|-------|-----------|--------|-----|
| A1 | Register array depth | > 64 entries | Xilinx UG901 §RAM Inference, Intel UG-20136 §Memory | Use inferred RAM (`reg [W-1:0] mem [0:N-1]` with proper coding style); use `(* ram_style = "block" *)` for FPGA |
| A2 | Repeated module instantiation | > 4 instances of same module | RMM §6.2 | Consider time-multiplexed resource sharing (A6 in power-timing-area.md) |
| A3 | Hard-coded constants | Non-parameterized numeric literals | RMM §3.3 | Replace with `parameter` or `localparam`; derive widths from parameters using `$clog2` |
| A4 | Unpipelined wide multiplier | 32-bit+ `*` without register | Xilinx UG901 §DSP48, Synopsys DC | Pipeline: `always @(posedge clk) product <= a * b;` — lets tool infer DSP |
| A5 | Wide operations in combinational loop | > 64-bit operations in `always @(*)` | Synopsys DC | Break into registered stages; use carry-save or other decomposition |

**Why these matter:** A 256-entry x 32-bit register array costs ~8K flip-flops (~12,000 µm² at 28nm). The same as a 2KB SRAM block. Registers should be for state, not storage.

---

## D. Timing Red Flags

**Source:** Cummings SNUG papers (Sunburst Design); Xilinx UG949 (UltraFast Design Methodology); Intel AN573.

| ID | Check | Threshold | Source | Fix |
|----|-------|-----------|--------|-----|
| T1 | Cross-module combinational path | No register at module boundary | Xilinx UG949 §Pipeline at Boundaries | Insert register slice at module I/O; use `(* keep_hierarchy = "yes" *)` to preserve boundary |
| T2 | High-fanout signal without constraint | Fanout > 50, no MAX_FANOUT | Xilinx UG949 §Fanout | Add `(* max_fanout = 50 *)` attribute; insert buffer tree |
| T3 | Async reset release without synchronizer | Async deassert on different clock edge | Cummings SNUG 2003 "Reset Design" | Use async assert, sync deassert pattern; add reset synchronizer |
| T4 | Gated clock in RTL | `assign gclk = clk & en` | Cummings SNUG 2000, Xilinx UG949 | Use clock-enable pattern (P1 in power-timing-area.md); let synthesis infer ICG |
| T5 | Combinational path across clock domains | No synchronizer between domains | Cummings SNUG 2008 "CDC Design" | Insert synchronizer; use gray code or handshake for multi-bit |

**Why these matter:** Cross-module combinational paths are the #1 cause of timing closure failures. They create paths that synthesis tools cannot optimize because they span hierarchy boundaries.

---

## E. Reusability

**Source:** RMM Chapters 3-4; ARM AMBA Design Methodology.

| ID | Check | Threshold | Source | Fix |
|----|-------|-----------|--------|-----|
| R1 | Hard-coded bus width | Fixed 32-bit or 64-bit in port list | RMM §3.3 | Use `parameter DATA_W = 32` and reference in port declarations |
| R2 | Hard-coded address map | Fixed addresses in RTL | RMM §3.4 | Use parameters for base addresses; use `localparam` for derived offsets |
| R3 | Protocol-specific logic in datapath | APB/AXI handshaking mixed with core logic | RMM §4.2, ARM AMBA methodology | Separate protocol adapter from core logic; core uses simple valid/ready |
| R4 | Non-standard naming | Ports without `*_i`/`*_o` suffix | naming-guidelines.md | Follow naming convention; refactor port list |

**Why these matter:** A module with hard-coded 32-bit width cannot be reused in a 64-bit system without modification. A module that mixes protocol logic with datapath logic cannot be ported from AXI to APB without rewriting.

---

## How to Use

### During RTL generation (Step 7)

Scan the generated RTL against this checklist before presenting to the user. Fix violations proactively.

### During self-review (Step 8)

For each check item, cite the specific line numbers or signal names that satisfy or violate the check. State pass/fail for each item.

### With automated script

```bash
python scripts/rtl_complexity_check.py rtl/*.v
python scripts/rtl_complexity_check.py rtl/*.v --yosys --top module_name
```

The script checks C1-C4, D1-D4, A1-A5 automatically. T1-T5 and R1-R4 require human or agent judgment.

---

## Severity Levels

| Level | Meaning | Action |
|-------|---------|--------|
| **ERROR** | Likely to cause synthesis or timing failure | Must fix before proceeding |
| **WARNING** | May cause problems in production | Fix if time permits; document if deferred |
| **INFO** | Style or readability concern | Fix during cleanup |

| ID | Level |
|----|-------|
| C1, C2 | WARNING |
| C3 | WARNING |
| C4 | WARNING |
| D1, D2 | ERROR |
| D3, D4 | WARNING |
| A1 | ERROR (for FPGA), WARNING (for ASIC) |
| A2 | INFO |
| A3 | WARNING |
| A4 | WARNING |
| A5 | ERROR |
| T1 | ERROR |
| T2, T3, T4, T5 | ERROR |
| R1, R2, R3, R4 | INFO |
