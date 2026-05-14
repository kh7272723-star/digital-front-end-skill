# AXI-Stream buffer trial

## Source basis

- Protocol rules: Arm AMBA AXI4-Stream protocol specification, Arm IHI 0051.
- Open-source implementation style reviewed for inspiration, not copied:
  - alexforencich `verilog-axis`, especially the library pattern of small AXI-Stream components with testbenches.
  - PULP `axi_stream` and `common_cells`, especially the composable ready/valid stream-register style.

## Contract

- One clock `clk_i`, synchronous active-high reset `rst_i`.
- Two-entry AXI-Stream buffer.
- Input item fields are `tdata_i`, `tkeep_i`, `tlast_i`, and `tuser_i`.
- Output item fields are `tdata_o`, `tkeep_o`, `tlast_o`, and `tuser_o`.
- `tready_o` is high when the buffer has free space.
- `tvalid_o` is high when the buffer has at least one item.
- Output payload and sideband hold stable while `tvalid_o && !tready_i`.
- `tlast` and byte-lane information in `tkeep` move with the matching data beat.

## State elements

- `count_q`: number of stored stream items.
- `rd_ptr_q`, `wr_ptr_q`: two-entry ring pointers.
- Per-entry payload and sideband registers.

## Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset | state unknown, `rst_i=1` | reset branch selected | clear count and pointers | no valid output | no false stream item |
| input accept | buffer not full, source valid | `accept_input=1` | store payload and sideband | count increases | data and sideband stored together |
| output accept | buffer not empty, sink ready | `accept_output=1` | advance read pointer | next item visible or empty | one output item consumed |
| simultaneous | one item present, source valid, sink ready | both accepts true | read old item, store new item | count unchanged | no loss or duplication |
| stall | output valid, sink not ready | `accept_output=0` | no read pointer change | output stable | payload and sideband hold |
| packet last | accepted item has `tlast=1` | normal accept | last flag stored with data | same last flag later visible | packet boundary preserved |

## Verification matrix

| Scenario | Stimulus | Expected result | Checker | Coverage target | Priority |
| --- | --- | --- | --- | --- | --- |
| reset | assert and release reset | output invalid, input ready | direct checks | reset release | high |
| normal packet | three beats with final partial `tkeep` and `tlast` | same sequence exits | scoreboard | packet boundary | high |
| downstream stall | hold `tready_i=0` while valid output | all output fields stable | stability check | two-cycle stall | high |
| simultaneous movement | ready while source valid | count remains consistent | scoreboard | replacement cycle | high |
| randomized ready | pseudo-random sink ready pattern | no loss or duplication | scoreboard | 12 items | high |

## Run

```text
python scripts/rtl_check.py --case evals/trials/axis_buffer_trial
```
