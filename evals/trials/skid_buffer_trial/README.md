# Skid Buffer Trial

## Assumptions

- Single clock domain: `clk_i`.
- Reset is synchronous active-high: `rst_i`.
- Input channel: `valid_i`, `ready_o`, `data_i`.
- Output channel: `valid_o`, `ready_i`, `data_o`.
- Buffer capacity is two items.
- If the buffer is full and downstream accepts one item, the buffer may accept one new input item in the same cycle.

## Design contract

- `accept_input = valid_i && ready_o`.
- `accept_output = valid_o && ready_i`.
- `valid_o` is high whenever at least one item is stored.
- `data_o` is the oldest stored item.
- While `valid_o && !ready_i`, `valid_o` and `data_o` remain stable.
- Accepted items leave in the same order they entered.
- No accepted item is dropped or duplicated.

## State elements

- `count_q`: number of stored items, 0 to 2.
- `data0_q`: oldest item, visible on `data_o`.
- `data1_q`: second item when the buffer is full.
- `accept_input`, `accept_output`: movement conditions.

## Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset | unknown state | `rst_i=1` | clear `count_q` | `valid_o=0`, `ready_o=1` | no false output item |
| empty accept | `count_q=0`, `valid_i=1` | `ready_o=1`, `accept_input=1` | load `data0_q` | `valid_o=1`, `data_o=data_i` | accepted item becomes oldest |
| downstream stall | `count_q=1`, `ready_i=0` | `accept_output=0` | optional new item loads into `data1_q` | `data0_q` still visible | output payload stays stable |
| full stall | `count_q=2`, `ready_i=0` | `ready_o=0` | no new input accepted | both stored items hold | no overwrite |
| full replace | `count_q=2`, `ready_i=1`, `valid_i=1` | both accepts true | shift `data1_q` to `data0_q`, load `data_i` to `data1_q` | order preserved | one leaves and one enters |

## Verification notes

- Test reset, empty accept, downstream stall, full stall, full replace, drain.
- Scoreboard every accepted input against every accepted output.
- Check `data_o` stability while downstream stalls.

Run:

```bash
python scripts/rtl_check.py --case evals/trials/skid_buffer_trial
```
