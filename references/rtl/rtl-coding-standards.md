# RTL Coding Standards

This document integrates project coding conventions with digital-front-end-skill best practices. All rules are graded M (Mandatory), S (Strongly Recommended), or R (Recommended).

## Rule Grades

| Grade | Meaning |
| --- | --- |
| **M** | Mandatory — violation is a reject |
| **S** | Strongly recommended — violation requires justification |
| **R** | Recommended — open to review discussion |

---

## 1. Naming Conventions

### 1.1 Basic Rules

| # | Grade | Rule |
|---|:---:|------|
| N1 | M | Signal names and module names **all lowercase**; parameter names **ALL UPPERCASE**. |
| N2 | M | Port suffixes: `_i` for inputs, `_o` for outputs. Active-low signals add `_n` before direction: `rst_ni` (active-low reset input), `irq_no` (active-low interrupt output). |
| N3 | M | Instance names prefixed with `inst_`. E.g., `inst_fifo`, `inst_fsm`. |
| N4 | M | Testbench filenames prefixed with `tb_`. E.g., `tb_nvme_io.v`. |

### 1.2 Pipeline Delay and State

| # | Grade | Rule |
|---|:---:|------|
| N5 | M | One-cycle delay: `xxx_r`. Multi-cycle delay chain: `xxx_r0`, `xxx_r1`, `xxx_r2`. Max three stages in principle. |
| N6 | R | FSM current state and next state named `cstate`, `nstate`. |
| N7 | M | FSM state names **UPPERCASE** with `S_` prefix. E.g., `S_IDLE`, `S_PAGE_TX`. |
| N8 | R | FSM state encoding: one-hot recommended. |
| N9 | S | FSM state count: ≤ 10 states. For slow clock domains (≤100 MHz), relax to ≤ 16. |
| N10 | R | FSM signal widths: ≤ 8 bits in principle. |

### 1.3 FIFO Naming

| # | Grade | Rule |
|---|:---:|------|
| N11 | R | FIFO module name format: `[dist_][dc_]fifo_<width>bx<depth>[_fwft]`. E.g., `fifo_32bx512` (standard sync FIFO), `fifo_32bx1k_fwft` (FWFT mode), `dist_fifo_8bx16` (LUT-based), `dc_fifo_8bx256` (async clock domains). |

### 1.4 Clock and Reset

| # | Grade | Rule |
|---|:---:|------|
| N12 | S | Single-clock module: clock named `clk_i`. |
| N13 | S | Single-reset module: reset named `rst_i` (sync active-high) or `rst_ni` (async active-low), clarified in the contract. |

### 1.5 Skill-Specific Naming (supplementary, no conflict)

- FIFO internal operations: `wr_do = wr_en_i && !full_o`, `rd_do = rd_en_i && !empty_o`
- Handshake conditions named once: `accept_input = valid_i && ready_o`, `accept_output = valid_o && ready_i`
- Registered state current/next distinction: `*_q` (current register value), `*_d` (next-cycle assignment). Use when the agent must reason about current vs. next visible state. For pure delay chains, prefer `_r`/`_r0`/`_r1` (N5).
- CDC synchronizer chain: `*_q` (first stage), `*_2q` (second stage output). Prefix with source clock domain for clarity.

---

## 2. Coding Rules

### 2.1 File Structure

| # | Grade | Rule |
|---|:---:|------|
| C1 | S | Embed a version number in the source file. |
| C2 | S | Declare all signals at the top of the file. |
| C3 | M | Every `.v` file starts with `` `default_nettype none `` and ends with `` `default_nettype wire ``. |
| C4 | S | Explicitly declare port directions as `input wire` / `output reg` / `output wire` — never omit. |

### 2.2 FSM Rules

| # | Grade | Rule |
|---|:---:|------|
| C5 | M | Be explicitly clear whether a module is **datapath** or **state machine** — no ambiguous third category. |
| C6 | M | **No datapath inside a state machine** (multi-bit arithmetic, complex assignments). FSM outputs single-bit enable signals only. |
| C7 | M | **No FSM-like code inside a datapath** module. Datapath modules contain no `case(cstate)` structures. |
| C8 | R | State machine in a separate file `xxx_fsm.v`, instantiated in the datapath file `xxx.v`. |
| C9 | M | State machine uses **two-process** style: combinational (`always @(*)`) + sequential (`always @(posedge clk_i)`). |
| C10 | M | Combinational process: **default assignments first**, before the `case(cstate)` — prevents latch inference. |

### 2.3 Reset and Initialization

| # | Grade | Rule |
|---|:---:|------|
| C11 | S | Use **synchronous active-high reset** unless the contract specifically requires otherwise. Do not mix reset and set. |
| C12 | S | Shift registers **should not use a reset signal**. |
| C13 | S | **Datapath registers do not require reset** — reduces timing pressure. |
| C14 | M | **Control conditions must be symmetric.** If a reset controls some registers in an `always` block, all registers on the same timing chain must be equally controlled. See §2.3.1. |

#### §2.3.1 Control Asymmetry Examples

The following is **forbidden** — `rst_i` controls only `flag_o`, but intermediate pipeline registers `flag_r0`, `flag_r1` lack equivalent reset control:

```verilog
// ❌ Forbidden: asymmetric control
always @(posedge clk_i) begin
    if (rst_i) begin
        flag_o <= 4'h0;
    end else begin
        flag_r0 <= flag_i;
        flag_r1 <= flag_r0;
        flag_o  <= flag_r1;
    end
end
```

**Fix A** (pipeline registers don't need reset — recommended):

```verilog
// ✅ Pipeline registers in a separate block, no reset
always @(posedge clk_i) begin
    flag_r0 <= flag_i;
    flag_r1 <= flag_r0;
end

always @(posedge clk_i) begin
    if (rst_i)
        flag_o <= 4'h0;
    else
        flag_o <= flag_r1;
end
```

**Fix B** (all registers need reset — symmetric control):

```verilog
// ✅ All registers under symmetric reset
always @(posedge clk_i) begin
    if (rst_i) begin
        flag_r0 <= 4'h0;
        flag_r1 <= 4'h0;
        flag_o  <= 4'h0;
    end else begin
        flag_r0 <= flag_i;
        flag_r1 <= flag_r0;
        flag_o  <= flag_r1;
    end
end
```

### 2.4 Synthesis and Quality

| # | Grade | Rule |
|---|:---:|------|
| C15 | M | After code generation, **must check for latch inference**. If latches exist, review and fix. |
| C16 | M | **Bit widths must be explicit.** Write `2'b01`, never `1`. |
| C17 | S | Review all warnings. Fix those related to your own code. |
| C18 | S | Cross-clock-domain signals: do not use `set_false` timing constraints without specific justification. |
| C19 | M | **Every register in a sequential `always` block must be assigned in every code path.** After `if`/`else-if` chains, include a final `else` that explicitly assigns the register its current value. See §2.4.1. |
| C20 | S | **Group registers by function into separate `always` blocks.** Do not place all sequential logic in one monolithic block. Registers that serve the same function, or share the same trigger/gate conditions, belong together. Benefits: readability, easier debug, better synthesis optimization (no false dependencies between unrelated registers). See §2.4.2. |
| **C21** | **M** | **One statement per line. Every register declaration on its own line. Every `<=` or `=` assignment on its own line.** Multiple statements on the same line (e.g., `a<=0; b<=0; c<=0;`) harm readability and make code review harder. Commas in port lists and case items are exempt. See §2.4.3. |

#### §2.4.1 Explicit Hold in Sequential Blocks

The pattern:

```verilog
// ✅ Correct: explicit hold in every branch
always @(posedge clk_i) begin
    if (trigger_a)
        reg_r <= next_val_a;
    else if (trigger_b)
        reg_r <= next_val_b;
    else
        reg_r <= reg_r;          // explicit hold — intent is clear
end
```

This is functionally equivalent to omitting the final `else`, but provides four concrete benefits:

1. **Makes hold intent explicit.** A reviewer immediately sees the register is deliberately held, not forgotten.
2. **Prevents refactoring bugs.** If someone inserts a new condition but misses the corresponding else, the compiler/linter catches the incomplete path sooner.
3. **Builds anti-latch muscle memory.** Combinational `always @(*)` blocks that lack an `else` infer latches. Forming the habit of explicit else in ALL blocks eliminates this class of bugs.
4. **Lint-friendly.** Tools like SpyGlass and Verilator flag incomplete if-else chains as warnings. Explicit else silences these.

```verilog
// ❌ Forbidden: register not assigned in all paths
always @(posedge clk_i) begin
    if (trigger_a)
        reg_r <= next_val_a;
    else if (trigger_b)
        reg_r <= next_val_b;
    // implicit hold — intent ambiguous, refactoring hazard
end
```

#### §2.4.2 Group Registers by Function

Monolithic `always` blocks mixing unrelated registers harm readability and synthesis. Registers driven by the same conditions naturally belong together.

```verilog
// ❌ Anti-pattern: all registers in one monolithic block
always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        fifo_wr_ptr    <= 0;
        fifo_rd_ptr    <= 0;
        aw_active      <= 1'b0;
        w_active       <= 1'b0;
        b_outstanding  <= 0;
        page_active    <= 1'b0;
    end else begin
        // FIFO write pointer
        if (fifo_wr_en) fifo_wr_ptr <= fifo_wr_ptr + 1;
        // FIFO read pointer
        if (fifo_rd_en) fifo_rd_ptr <= fifo_rd_ptr + 1;
        // AW controller
        if (aw_trigger)      aw_active <= 1'b1;
        else if (aw_handshake) aw_active <= 1'b0;
        // W controller
        if (w_trigger)      w_active <= 1'b1;
        else if (w_handshake) w_active <= 1'b0;
        // B controller
        if (b_handshake)    b_outstanding <= b_outstanding - 1;
        // Page controller
        if (page_accept)    page_active <= 1'b1;
        else if (page_done_cond) page_active <= 1'b0;
    end
end
```

Grouped by function — each block has a single responsibility, zero false dependencies:

```verilog
// ✅ FIFO write pointer: only cares about fifo_wr_en
always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
        fifo_wr_ptr <= 0;
    else if (fifo_wr_en)
        fifo_wr_ptr <= fifo_wr_ptr + 1;
    else
        fifo_wr_ptr <= fifo_wr_ptr;
end

// ✅ FIFO read pointer: only cares about fifo_rd_en
always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
        fifo_rd_ptr <= 0;
    else if (fifo_rd_en)
        fifo_rd_ptr <= fifo_rd_ptr + 1;
    else
        fifo_rd_ptr <= fifo_rd_ptr;
end

// ✅ AW controller: AW-only state machine
always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
        aw_active <= 1'b0;
    else if (aw_trigger)
        aw_active <= 1'b1;
    else if (aw_handshake)
        aw_active <= 1'b0;
    else
        aw_active <= aw_active;
end

// ✅ W controller: W-only state machine
always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
        w_active <= 1'b0;
    else if (w_trigger)
        w_active <= 1'b1;
    else if (w_last_beat)
        w_active <= 1'b0;
    else
        w_active <= w_active;
end

// ✅ B controller: simple counter
always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
        b_outstanding <= 0;
    else if (aw_fire && b_fire)
        b_outstanding <= b_outstanding;
    else if (aw_fire)
        b_outstanding <= b_outstanding + 1;
    else if (b_fire)
        b_outstanding <= b_outstanding - 1;
    else
        b_outstanding <= b_outstanding;
end
```

Grouping rules of thumb:
- FIFO pointer management → one block per pointer (wr_ptr, rd_ptr)
- AXI channel controllers → one block per channel (AW, W, B)
- Page/command state → its own block
- Completion/done signals → aggregate block (reads from other blocks)

### 2.5 Skill-Specific Coding Rules (supplementary)

- Each `reg`/`wire` has exactly one driver (`always` or `assign`). No multiply-driven signals (E1).
- `<=` (nonblocking) in `always @(posedge clk_i)`, `=` (blocking) in `always @(*)`. Never mix (E4).
- No implicit width truncation — use explicit part-selects (E3).
- No combinational feedback loops (E7).
- Declare `wire` before first use — avoid forward references.
- FIFO data path uses **FWFT** (combinational read): `rdata = mem[rd_ptr]`. Never use registered read output for data path FIFOs.

---

## 3. Timing Optimization

| # | Grade | Rule |
|---|:---:|------|
| T1 | S | Always know which clock domains you have planned, and be explicit about how each CDC crossing is handled. |
| T2 | R | Datapath registers do not need reset (reduces timing pressure). |
| T3 | S | Register outputs at module boundaries. Do not register inputs. Register data read from FIFO. |
| T4 | S | ILA usage is acceptable during early debug. Remove ILA in production code. |
| T5 | R | Reset signals should not use `set_false` in principle. |
| T6 | R | For algorithmic modules, do not use backpressure signals. E.g., for AXI-Stream, do not use `tready`; for FIFO writes, do not use `full`; for FIFO reads, do not use `empty`. Verify correctness through simulation. |
| T7 | R | Multi-clock designs: slow signals (parameters, status/control registers) use slow clock; high-bandwidth paths use fast clock. Use `multicycle` to relax CDC timing constraints where the design guarantees correctness. |
| T8 | R | Power-on configuration data paths (configured once): relax constraints with `multicycle`. Do not use `set_false`. |
| T9 | R | Plan FPGA placement. Use `PBLOCK` to guide the placer. |
| T10 | R | In Vivado: open `implementation → report clock networks` to verify the clock tree matches your plan. A 0 MHz clock indicates unconstrained clock. |

---

## 4. FSM Template (Integrated)

```verilog
// xxx_fsm.v — two-process FSM, separate file
// Version: v1.0

`default_nettype none

module xxx_fsm (
    input  wire        clk_i,
    input  wire        rst_i,        // sync active-high reset
    input  wire        start_i,      // single-bit enable (from datapath)
    output wire        done_o,       // single-bit status
    // ... other single-bit control signals ...
    output wire [3:0]  sel_o         // exception: small multi-bit control allowed
);

    // ── State encoding (one-hot) ──
    localparam S_IDLE    = 4'b0001;
    localparam S_BUSY    = 4'b0010;
    localparam S_DONE    = 4'b0100;
    localparam S_ERROR   = 4'b1000;

    reg [3:0] cstate, nstate;

    // ── Sequential process ──
    always @(posedge clk_i) begin
        if (rst_i)
            cstate <= S_IDLE;
        else
            cstate <= nstate;
    end

    // ── Combinational process: defaults → case(cstate) ──
    always @(*) begin
        nstate  = cstate;       // default: hold current state
        done_o  = 1'b0;        // default: all outputs inactive
        sel_o   = 4'b0000;

        case (cstate)
            S_IDLE:  if (start_i) nstate = S_BUSY;
            S_BUSY:  begin
                sel_o = 4'b0001;
                if (/* condition */) nstate = S_DONE;
            end
            S_DONE: begin
                done_o = 1'b1;
                nstate = S_IDLE;
            end
            S_ERROR: nstate = S_IDLE;
            default: nstate = S_IDLE;
        endcase
    end

endmodule

`default_nettype wire
```

Corresponding datapath file `xxx.v`:

```verilog
// xxx.v — datapath (instantiates FSM)
`default_nettype none

module xxx (
    input  wire        clk_i,
    input  wire        rst_i,
    // ... data ports ...
);

    // ── FSM instantiation ──
    wire fsm_done, fsm_sel;
    xxx_fsm inst_fsm (
        .clk_i   (clk_i),
        .rst_i   (rst_i),
        .start_i (start_i),
        .done_o  (fsm_done),
        .sel_o   (fsm_sel)
    );

    // ── Datapath (pure data flow, no case(cstate)) ──
    always @(posedge clk_i) begin
        if (fsm_sel) begin
            data_r <= data_i;       // pipelined signal: _r suffix
        end
    end

endmodule

`default_nettype wire
```

---

#### §2.4.3 One Statement Per Line (C21)

**Rule:** Every register declaration on its own line. Every `<=` or `=` assignment on its own line. Commas in port lists and `case` items are exempt.

```verilog
// ❌ BROKEN — multiple declarations and assignments on one line
reg [FA-1:0] fwp_q,frp_q; reg [FA:0] fcnt_q;
if (!rst_ni) begin
    aw_vld_q<=0; aw_a_q<=0; aw_l_q<=0;
end

// ✅ CORRECT — one declaration per line, one assignment per line
reg [FA-1:0] fwp_q;
reg [FA-1:0] frp_q;
reg [FA:0]   fcnt_q;

if (!rst_ni) begin
    aw_vld_q <= 0;
    aw_a_q   <= 0;
    aw_l_q   <= 0;
end
```

**Rationale:** Packed lines make code review harder — a reviewer must parse semicolons to find statement boundaries. Splitting to one-per-line also makes version control diffs cleaner: a one-line change to `aw_l_q` shows exactly which signal changed, not a whole block.

---

## 5. Phase 3 Code Compliance Audit

Based on the above standards, the current Phase 3 code has the following violations:

| File | Violation | Grade | Fix |
|------|-----------|:---:|------|
| `nvme_prp_walker.v` | C6 Multi-bit `_d` signals assigned inside `case(state)` | M | Split into FSM + datapath |
| `nvme_read_engine.v` | C5/C6 FSM and datapath interleaved | M | Split AW/W/B controllers into separate FSMs |
| `nvme_cmd_tracker.v` | C5/C6 Same issue | M | Split tracker FSM |
| All modules | N3 Missing `inst_` prefix on instances | M | Add `inst_` prefix |
| All modules | C11 Async active-low `rst_ni` | S | Change to sync active-high `rst_i` |
| All modules | N5 Delay chain naming uses `_q` instead of `_r` | M | Rename pipeline delay signals to `_r` series |
| PRP walker FSM | N6 Uses `state_q` instead of `cstate` | R | Rename to `cstate`/`nstate` |
