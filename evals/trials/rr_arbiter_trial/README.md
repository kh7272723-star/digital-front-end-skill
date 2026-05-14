# Registered ready/valid round-robin arbiter trial

## Assumptions

- Plain Verilog-first RTL, simulated with Icarus Verilog using `rtl_check.py`.
- Single synchronous clock `clk_i`.
- Synchronous active-high reset `rst_i`.
- Four upstream ready/valid inputs share one downstream ready/valid output.
- Input data is flattened as `{ch3, ch2, ch1, ch0}` with each channel `DATA_W` bits.
- The arbiter contains one registered output slot and no per-input buffering.

## Design contract

- If `valid_o=1` and `ready_i=0`, the arbiter holds `valid_o`, `data_o`, and `grant_o`.
- While holding a full output slot, all `ready_o` bits are low, so no new input item is accepted.
- If the output slot is empty or the downstream accepts the current item, the arbiter may accept one valid input item.
- Selection starts at `rr_ptr_q` and skips invalid requesters.
- `rr_ptr_q` advances to the requester after the accepted requester only when an input item is accepted.
- Reset clears `valid_o`, clears payload registers, and sets `rr_ptr_q=0`, so requester 0 has first priority after reset.
- If no input is valid and the current output is accepted or empty, `valid_o` becomes 0.

## State elements

- `rr_ptr_q`: next requester index to search first.
- `valid_o`: registered output-valid state.
- `data_o`: registered output payload.
- `grant_o`: registered index of the payload currently visible on `data_o`.

## Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset | state unknown, `rst_i=1` | reset branch selected | clear output slot, pointer to 0 | `valid_o=0`, `rr_ptr_q=0` | no false valid item after reset |
| first request | output empty, requests on multiple channels | `output_can_load=1`, selected index starts at `rr_ptr_q` | capture selected data, set `valid_o=1`, advance pointer | selected payload visible | one accepted item creates one output item |
| downstream stall | `valid_o=1`, `ready_i=0` | `output_can_load=0`, `accept_input=0` | no state update | payload and grant unchanged | data and sideband stay stable |
| consume and replace | `valid_o=1`, `ready_i=1`, at least one valid input | `accept_output=1`, `accept_input=1` | old output is consumed, new selected input is captured | replacement payload visible | no gap when replacement exists |
| consume and empty | `valid_o=1`, `ready_i=1`, no valid input | `accept_output=1`, `accept_input=0` | clear `valid_o` | output slot empty | consumed item is not duplicated |
| sparse requests | requester at pointer invalid | search skips invalid requesters | capture first valid requester in cyclic order | grant matches cyclic order | inactive channels do not block progress |

## Verification matrix

| Scenario | Stimulus | Expected result | Checker | Coverage target | Priority |
| --- | --- | --- | --- | --- | --- |
| reset release | assert and release reset | `valid_o=0`, `rr_ptr_q` implied by first grant 0 | direct checks | first active cycle | high |
| consecutive requests | all four inputs valid, downstream ready | grants 0,1,2,3,0,1,2,3 | ordered comparisons | wrap-around pointer | high |
| downstream stall | hold `ready_i=0` while output valid | `ready_o=0`, payload and grant stable | stability checks | 2 stalled cycles | high |
| consume and replace | reassert `ready_i=1` with requests valid | next grant appears without a bubble | direct checks | simultaneous output/input movement | high |
| sparse requests | only channels 1 and 3 valid | grants alternate 1,3,1,3 | ordered comparisons | skip invalid channels | medium |
| idle clear | no input valid and downstream ready | `valid_o=0` after current item drains | direct checks | empty output | medium |
| randomized handshakes | pseudo-random source valid and downstream ready | DUT matches a cycle-accurate reference model | scoreboard | 180 mixed cycles | high |
| persistent fairness | all four inputs valid with periodic backpressure | accept counts stay balanced across channels | grant counters | 80 accepted items | medium |

## Assertion and review ideas

- `ready_o` should be zero while `valid_o && !ready_i`.
- At most one `ready_o` bit may be high.
- If `valid_o && !ready_i`, `data_o` and `grant_o` must remain stable across the next edge.
- Pointer should advance only when an input item is accepted.
- The executable testbench now includes directed checks, a cycle-accurate scoreboard, pseudo-random valid/ready traffic, and a bounded fairness counter. It is still simulation evidence, not formal proof.
