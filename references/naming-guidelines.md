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

## Avoid

- Mixing `in_*`/`out_*` with `*_i/*_o` in the same example.
- Using `ready_i` or `ready_o` without saying which side owns the ready signal.
- Using FIFO terms that hide whether the operation is a write or read.
- Reusing one movement condition for two different timing meanings.
