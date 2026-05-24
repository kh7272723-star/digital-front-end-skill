# RTL Correctness Rules — Common Low-Level Errors

## Purpose

Prevent common RTL coding errors that tools catch during compilation, lint, or synthesis. These errors are cheap to fix if caught at code generation time, expensive if caught after simulation. Each rule includes the tool warning message, a bug example, and a fix.

## Sources

| Source | Document |
|--------|----------|
| Verilator | Warning codes: MULTIDRIVEN, WIDTHTRUNC, BLKSEQ, COMBDLY, UNDRIVEN, UNUSED |
| UG901 | Vivado Synthesis User Guide — coding for synthesis |
| UG949 | UltraFast Design Methodology — reset, CDC, timing |
| IEEE 1800-2017 | SystemVerilog Standard, Section 10.4 (blocking/nonblocking) |
| IEEE 1364-2001 | Verilog Standard, Section 4.1.3 (implicit nets) |
| Cummings SNUG2000 | "Nonblocking Assignments in Verilog Synthesis, Coding Styles that Kill!" |

---

## E1. Multi-driven nets

**Tool warning:**
- Verilator: `%Warning-MULTIDRIVEN: signal has multiple drivers`
- Vivado: `[Synth 8-3332] multi-driven net`
- Synopsys DC: elaboration error on multi-driven signal

**Root cause:** Two `always` blocks or two `assign` statements drive the same signal. This is a structural error — the simulator picks one driver arbitrarily, but synthesis produces unpredictable hardware.

**Bug code:**
```verilog
// BUG: two always blocks drive the same register
always @(posedge clk_i) begin
    if (sel_a) data_q <= val_a;
end
always @(posedge clk_i) begin
    if (sel_b) data_q <= val_b;
end
```

**Correct code:**
```verilog
// Single driver: merge into one block with priority
always @(posedge clk_i) begin
    if (sel_b)      data_q <= val_b;
    else if (sel_a) data_q <= val_a;
end
```

**Prevention rule:** Every `reg` or `wire` must have exactly one driving source — one `always` block or one `assign` statement. After generating RTL, scan for any signal name that appears on the LHS of assignments in more than one block.

**Self-review check:** For each `reg` signal, verify it appears on the LHS of `<=` in exactly one `always @(posedge clk)` block. For each `wire`, verify it appears in exactly one `assign`.

---

## E2. Latch inference

**Tool warning:**
- Vivado: `[Synth 8-327] inferring latch for variable 'out'`
- Intel Quartus: `Warning (10270): incomplete case statement`
- Verilator: no direct warning (use `always_comb` in SV to catch at sim time)

**Root cause:** A signal is not assigned in all branches of a combinational `always` block. The synthesis tool infers a latch to hold the value when no branch is taken. Latches cause timing analysis difficulties and simulation/synthesis mismatches.

**Bug code:**
```verilog
// BUG: 'out' not assigned when sel==0 → latch
always @(*) begin
    if (sel) out = a;
end
```

**Correct code:**
```verilog
// Default value at top — no latch
always @(*) begin
    out = 1'b0;  // default
    if (sel) out = a;
end
```

**Prevention rule:** Every combinational `always` block must assign a default value to every output before any conditional branches. This is the "default-first" pattern. See `references/rtl/coding-guidelines.md` C3.

**Self-review check:** For every `always @(*)` block, verify that every `reg` assigned in the block has a default assignment before the `case`/`if-else` chain.

---

## E3. Width mismatches

**Tool warning:**
- Verilator: `%Warning-WIDTHTRUNC: expects N bits, but RHS generates M bits`
- Synopsys DC: `VERI-2010: LHS width narrower than RHS, truncation`
- Vivado: `[Synth 8-3332] width mismatch`

**Root cause:** Assigning a wider expression to a narrower target without explicit truncation. The tool silently discards upper bits. This is often a bug (wrong width) or an unintentional sign extension.

**Bug code:**
```verilog
wire [15:0] wide_val;
reg  [7:0]  narrow_val;
// BUG: silent truncation of bits [15:8]
assign narrow_val = wide_val;
```

**Correct code:**
```verilog
// Explicit part-select shows intent
assign narrow_val = wide_val[7:0];

// Or, if full width is needed, extend the target
reg [15:0] full_val;
assign full_val = wide_val;
```

**Prevention rule:** Never rely on implicit truncation. Always use explicit bit-selects (`[7:0]`) or part-selects when assigning across different widths. Use `$unsigned()` / `$signed()` casts when mixing signed and unsigned operands.

**Self-review check:** For every assignment, verify LHS and RHS widths match, or the difference is explicitly handled with a part-select.

---

## E4. Blocking vs non-blocking misuse

**Tool warning:**
- Verilator: `%Warning-BLKSEQ: Blocking assignment (=) in sequential block`
- IEEE 1800-2017 Section 10.4: defines blocking (`=`) and nonblocking (`<=`) semantics

**Root cause:** Using `=` (blocking) in a clocked `always @(posedge clk)` block, or `<=` (nonblocking) in a combinational `always @(*)` block. Blocking assignments in sequential blocks cause simulation race conditions — the updated value is visible to subsequent statements in the same timestep, which does not match flip-flop hardware behavior.

**Bug code:**
```verilog
// BUG: blocking in sequential — race condition
always @(posedge clk_i) begin
    a = b;     // a updates immediately
    c = a;     // sees NEW a, not old a — wrong hardware model
end
```

**Correct code:**
```verilog
// Nonblocking in sequential — matches flip-flop behavior
always @(posedge clk_i) begin
    a <= b;    // a updates at end of timestep
    c <= a;    // sees OLD a — correct hardware model
end
```

**Prevention rule:**
- `always @(posedge clk)` → use `<=` (nonblocking) for all assignments
- `always @(*)` → use `=` (blocking) for all assignments
- Never mix `=` and `<=` in the same `always` block

Reference: Cummings SNUG2000 "Nonblocking Assignments in Verilog Synthesis, Coding Styles that Kill!"

**Self-review check:** For every `always @(posedge clk)` block, verify all assignments use `<=`. For every `always @(*)` block, verify all assignments use `=`.

---

## E5. Incomplete sensitivity list

**Tool warning:**
- Simulation/synthesis mismatch: sim misses signal changes, synth infers full logic
- Verilator: `always @*` catches this automatically

**Root cause:** Manually writing `always @(a or b)` but missing signal `c` that is read in the block. Simulation does not re-evaluate when `c` changes, but synthesis builds combinational logic that includes `c`. This creates a sim/synth mismatch.

**Bug code:**
```verilog
// BUG: missing 'b' in sensitivity list
always @(a) begin
    out = a & b;  // sim doesn't re-evaluate when b changes
end
```

**Correct code:**
```verilog
// always @(*) infers correct sensitivity automatically
always @(*) begin
    out = a & b;
end
```

**Prevention rule:** Use `always @(*)` for all combinational logic. Never hand-write sensitivity lists. The `(*)` construct tells the compiler to infer the complete sensitivity from the RHS of all assignments in the block.

**Self-review check:** Every combinational `always` block uses `always @(*)`, not `always @(signal_list)`.

---

## E6. Incomplete reset

**Tool warning:**
- Vivado UG949: async reset must be directly tested (not gated by enable)
- Synopsys DC: `Warning: recovery/removal time violation on reset`
- Simulation: register powers up to 'x' instead of known state

**Root cause:** Not all registers in a sequential block are reset. Some registers retain their power-on value (undefined in ASIC, zero in FPGA) while others are explicitly reset. This causes unpredictable initial state.

**Bug code:**
```verilog
// BUG: data_q not reset — unknown initial state
always @(posedge clk_i) begin
    if (rst_i) begin
        cnt_q <= 8'd0;
        // data_q not reset!
    end else begin
        cnt_q  <= cnt_q + 1;
        data_q <= next_data;
    end
end
```

**Correct code:**
```verilog
// All registers explicitly reset
always @(posedge clk_i) begin
    if (rst_i) begin
        cnt_q  <= 8'd0;
        data_q <= {DATA_W{1'b0}};
    end else begin
        cnt_q  <= cnt_q + 1;
        data_q <= next_data;
    end
end
```

**Prevention rule:** Every register in every `always @(posedge clk)` block must have a reset assignment, or be explicitly documented as "intentionally not reset" with a justification (e.g., FPGA BRAM output register, shift register for CDC). This skill mandates synchronous active-high reset — see `references/timing/naming-guidelines.md`.

**Self-review check:** For every `always @(posedge clk)` block, verify the reset branch assigns all registers that are assigned in the non-reset branch.

---

## E7. Combinational loops

**Tool warning:**
- Synopsys DC: `Error: combinational loop detected through signal 'x'`
- Vivado: `Combinational loop detected`
- Verilator: `%Warning-COMBDLY` (delayed assignment in combinational context)

**Root cause:** A signal feeds back into its own combinational logic cone without an intervening register. The loop creates oscillation or metastability in hardware.

**Bug code:**
```verilog
// BUG: 'a' depends on itself combinationally
assign a = b & a;
```

**Correct code:**
```verilog
// Break the loop with a register
always @(posedge clk_i) begin
    if (rst_i) a_q <= 1'b0;
    else       a_q <= b & a_q;
end
```

**Prevention rule:** No combinational path may form a cycle. Every feedback path must pass through at least one flip-flop. After generating RTL, verify no `assign` or `always @(*)` block reads a signal that it also drives.

**Self-review check:** For every combinational block, verify the output signals do not appear in the input sensitivity list or RHS expressions of the same block.

---

## E8. Undeclared signals (implicit wires)

**Tool warning:**
- Verilator: `%Warning-UNDRIVEN: signal has no source` / `%Warning-UNUSED: signal is never used`
- IEEE 1364-2001 Section 4.1.3: undeclared identifiers create implicit 1-bit wire

**Root cause:** A misspelled signal name silently creates a new 1-bit wire. The intended signal is never driven, and the typo-driven wire has no meaningful value. This is extremely hard to debug because the code compiles without errors.

**Bug code:**
```verilog
// BUG: 'data_ou' is a typo — creates implicit 1-bit wire
// 'data_out' is never driven
wire [7:0] data_in;
wire [7:0] data_out;
assign data_ou = data_in + 1;  // typo: 'data_ou' not 'data_out'
```

**Correct code:**
```verilog
`default_nettype none  // at file top — disables implicit wires

module my_module (...);
    wire [7:0] data_in;
    wire [7:0] data_out;
    assign data_out = data_in + 1;  // typo now causes compile error
endmodule

`default_nettype wire  // at file bottom — restore for third-party IP
```

**Prevention rule:** Every module file must start with `` `default_nettype none `` and end with `` `default_nettype wire ``. This disables Verilog's implicit wire declaration, turning typos into compile errors.

**Self-review check:** Every `.v` file starts with `` `default_nettype none ``.

---

## Summary: minimum self-review checklist

Add these checks to the RTL self-review (SKILL.md step 8):

| ID | Check | Severity |
|----|-------|----------|
| E1 | Every reg/wire has exactly one driving source | Error |
| E2 | Every combinational block has default-first assignments | Error |
| E3 | No implicit truncation — explicit part-selects on all width mismatches | Warning |
| E4 | `<=` in sequential blocks, `=` in combinational blocks, never mixed | Error |
| E5 | All combinational blocks use `always @(*)` | Error |
| E6 | All registers have explicit reset (or documented justification) | Error |
| E7 | No combinational feedback loops | Error |
| E8 | File starts with `` `default_nettype none `` | Warning |
