# Timing Contract

## Module: simple_counter

- Clock: clk_i, single domain
- Reset: rst_ni, async active-low
- Input: inc_i (pulse), clr_i (pulse)
- Output: count_o [7:0] (registered)
- Behavior: increments on inc_i, clears on clr_i
