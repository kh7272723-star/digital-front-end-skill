# Naming guidelines

## Purpose

Use these names so timing roles are visible before reading the logic.
Project-local naming wins when the user provides an existing style guide.

## Port suffixes

- Use `*_i` for module inputs.
- Use `*_o` for module outputs.
- Use `clk_i` for the main clock.
- Use `rst_i` for synchronous active-high reset examples.
- Use `rst_ni` only when the contract requires active-low reset.

## Ready/valid ports

Use these names for a single ready/valid channel:

- `valid_i`, `data_i`, `ready_o`: upstream channel into this block.
- `valid_o`, `data_o`, `ready_i`: downstream channel out of this block.

For multiple channels, prefix the channel role:

- `req_valid_i`, `req_ready_o`, `req_data_i`
- `rsp_valid_o`, `rsp_ready_i`, `rsp_data_o`

For AXI-adjacent command/status interfaces (e.g., DMA command input, completion output), prefer `valid_i`/`ready_o` over `req_i`/`ack_o` or `req_i`/`ready_o` to maintain semantic consistency with AXI's own valid/ready protocol. Use `req`/`ack` only for non-AXI request/acknowledge handshakes where the semantics differ from valid/ready (e.g., a single-cycle pulse ack).

## Movement conditions

Name protocol movement conditions once and reuse them:

- `accept_input = valid_i && ready_o`
- `accept_output = valid_o && ready_i`
- `wr_do = wr_en_i && !full_o`
- `rd_do = rd_en_i && !empty_o`
- `advance = !stall_i`
- `load`, `clear`, `flush`, or `hold` only when the condition means exactly that.

Do not use a clever abbreviation when the condition is part of the timing contract.

## FIFO names

- External controls: `wr_en_i`, `rd_en_i`.
- External data: `wdata_i`, `rdata_o`.
- Status: `full_o`, `empty_o`, optionally `count_o`.
- Internal accepted operations: `wr_do`, `rd_do`.
- Internal pointers: `wr_ptr_q`, `rd_ptr_q`.
- Internal occupancy: `count_q`.

State whether `wr_en_i` while full and `rd_en_i` while empty are ignored, flagged, or illegal.

## State and next-state names

Use `*_q` for registered state and `*_d` for the next value when that distinction clarifies timing:

- `state_q`, `state_d`
- `count_q`, `count_d`
- `valid_q`, `valid_d`

Do not add `*_q/*_d` mechanically to every signal. Use it where the agent must reason about current state versus next visible state.

## CDC synchronizer names

For signals crossing clock domains, use a naming chain that makes the synchronizer depth visible:

- `*_q` — first synchronizer stage (destination clock domain)
- `*_2q` — second synchronizer stage (output of double-flop synchronizer)
- `*_3q` — third stage if needed (e.g., for edge detection after synchronization)

Prefix with the source domain for clarity when multiple domains exist:

- `rd_ptr_gray_wrclk_q` — first sync of read-pointer gray code into write clock domain
- `rd_ptr_gray_wrclk_2q` — second sync stage (output)
- `wr_ptr_gray_rdclk_q` — first sync of write-pointer gray code into read clock domain
- `wr_ptr_gray_rdclk_2q` — second sync stage (output)

Mark synchronizer flip-flops with synthesis attributes (see `references/synthesis/cdc-guidelines.md`):
- `(* ASYNC_REG = "TRUE" *)` for Vivado/Quartus
- `// synopsys async_set_reset "wr_rst_ni"` for Synopsys tools

## Reset names

- `rst_i` — synchronous active-high reset (default)
- `rst_ni` — synchronous or asynchronous active-low reset
- `wr_rst_ni` / `rd_rst_ni` — domain-specific active-low reset for CDC designs
- Asynchronous reset with synchronized deassertion is the standard CDC reset pattern (see `references/synthesis/cdc-guidelines.md`)

## Parameter validation

Use `initial` block with `$error` for parameter validation. Guard with synthesis translate directives:

```verilog
// synthesis translate_off
initial begin
    if (DEPTH < 2 || (DEPTH & (DEPTH - 1)))
        $error("DEPTH must be power of 2, got %0d", DEPTH);
end
// synthesis translate_on
```

Use `// synthesis translate_off` for Synopsys/Cadence, or `// synopsys translate_off` for legacy tools. Prefer `synthesis translate_off` as it is more widely recognized.

## Avoid

- Mixing `in_*`/`out_*` with `*_i/*_o` in the same example.
- Using `ready_i` or `ready_o` without saying which side owns the ready signal.
- Using FIFO terms that hide whether the operation is a write or read.
- Reusing one movement condition for two different timing meanings.
