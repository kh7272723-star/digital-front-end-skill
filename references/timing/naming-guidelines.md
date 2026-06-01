# Naming Guidelines

## Purpose

This is the sole naming authority for the skill, incorporating project coding standards. All RTL must follow these rules.

## Rule Grades

| Grade | Meaning |
| --- | --- |
| **M** | Mandatory |
| **S** | Strongly recommended |
| **R** | Recommended |

## Basic Rules

| # | Grade | Rule |
|---|:---:|------|
| N1 | M | Signal and module names **all lowercase**; parameter names **ALL UPPERCASE**. |
| N2 | M | Port suffixes: `_i` for inputs, `_o` for outputs. Active-low signals insert `_n` before direction: `rst_ni`, `irq_no`. |
| N3 | M | Instance names prefixed with `inst_`. E.g., `inst_fifo`, `inst_fsm`. |
| N4 | M | Testbench filenames prefixed with `tb_`. |

## Port Naming

- `clk_i` — main clock (single-clock modules)
- `rst_i` — synchronous active-high reset (default)
- `rst_ni` — asynchronous active-low reset (only when the contract explicitly requires it)
- Port direction suffixes `_i`/`_o` must not be omitted

## Ready/Valid Handshakes

Single channel:

- `valid_i`, `data_i`, `ready_o` — upstream channel (received by this module)
- `valid_o`, `data_o`, `ready_i` — downstream channel (driven by this module)

Multi-channel — prefix with role:

- `req_valid_i`, `req_ready_o`, `req_data_i`
- `rsp_valid_o`, `rsp_ready_i`, `rsp_data_o`

## Pipeline Delays and Registers

| Context | Naming | Notes |
|---------|--------|-------|
| Single-cycle delay | `xxx_r` | Pure delay register |
| Multi-cycle delay chain | `xxx_r0`, `xxx_r1`, `xxx_r2` | Max three stages (M) |
| Current/next distinction needed | `xxx_q` (current), `xxx_d` (next-cycle value) | Non-mandatory; use only when timing clarity requires it |
| FSM state | `cstate` (current state), `nstate` (next state) | R |
| FSM state names | `S_` prefix + UPPERCASE, e.g., `S_IDLE`, `S_PAGE_TX` | M |

`_r` for pure delay chains; `_q`/`_d` for registers where the distinction between current-cycle value and next-cycle assignment matters (e.g., FSM auxiliary registers). Both conventions can coexist.

## FIFO Naming

External interface:

- Controls: `wr_en_i`, `rd_en_i`
- Data: `wdata_i`, `rdata_o`
- Status: `full_o`, `empty_o`, `count_o` (optional)

Internal signals:

- Accepted operations: `wr_do = wr_en_i && !full_o`, `rd_do = rd_en_i && !empty_o`
- Pointers: `wr_ptr_q`, `rd_ptr_q`
- Occupancy: `count_q`

FIFO module naming format (R): `[dist_][dc_]fifo_<width>bx<depth>[_fwft]`

- `fifo_32bx512` — standard synchronous FIFO
- `fifo_32bx1k_fwft` — FWFT mode
- `dist_fifo_8bx16` — LUT-based (distributed RAM)
- `dc_fifo_8bx256` — async clock domains (different clock)

## CDC Synchronizer Naming

Cross-domain synchronizer chain naming (skill CDC expertise):

- `*_q` — first synchronizer stage (destination clock domain)
- `*_2q` — second stage (output of double-flop synchronizer)
- `*_3q` — third stage (if edge detection is needed)

Prefix with the source domain for clarity:

- `rd_ptr_gray_wrclk_q` — read-pointer gray code sampled into write clock domain (stage 1)
- `rd_ptr_gray_wrclk_2q` — stage 2 sync output
- `wr_ptr_gray_rdclk_q` — write-pointer gray code sampled into read clock domain (stage 1)
- `wr_ptr_gray_rdclk_2q` — stage 2 sync output

Synthesis attributes (see `references/synthesis/cdc-guidelines.md`):

- `(* ASYNC_REG = "TRUE" *)` — Vivado/Quartus
- `// synopsys async_set_reset "wr_rst_ni"` — Synopsys

## Movement Conditions

Name protocol conditions once, reuse everywhere:

- `accept_input = valid_i && ready_o`
- `accept_output = valid_o && ready_i`
- `wr_do = wr_en_i && !full_o`
- `rd_do = rd_en_i && !empty_o`
- `advance = !stall_i`
- `load`, `clear`, `flush`, `hold` — only when the semantics match exactly

## Parameter Validation

Use `initial` block with `$error`, guarded by synthesis translate directives:

```verilog
// synthesis translate_off
initial begin
    if (DEPTH < 2 || (DEPTH & (DEPTH - 1)))
        $error("DEPTH must be power of 2, got %0d", DEPTH);
end
// synthesis translate_on
```

## Forbidden

- Mixing `_i`/`_o` with `in_*`/`out_*` in the same module
- Uppercase letters in signal or module names (except parameters)
- FIFO terms that obscure read/write semantics
- One movement condition reused for two different timing meanings
- Wire forward references — declare before first use
