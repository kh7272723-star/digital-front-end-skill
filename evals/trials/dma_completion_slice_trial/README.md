# DMA completion slice trial

## Slice goal

Implement the smallest executable DMA slice that protects one key AXI ordering invariant:

> Descriptor completion must wait for all expected write responses. The last accepted write data beat is not enough.

This is not a complete DMA. Neighbor modules are modeled by simple inputs:

- descriptor frontend supplies one descriptor and expected write response count,
- write data engine reports accepted last W beat,
- AXI B channel supplies write responses,
- completion consumer accepts `done_valid_o`.

## Assumptions

- Single clock `clk_i`.
- Synchronous active-high reset `rst_i`.
- One active descriptor at a time.
- Descriptor field `desc_resp_count_i` is the number of B responses expected for the descriptor.
- `write_data_accept_i && write_data_last_i` marks the final W beat accepted for the descriptor.
- `bvalid_i && bready_o` accepts one write response.
- Any non-OKAY B response marks descriptor error, but completion still waits for all expected responses.

## Interface contract

- `desc_valid_i && desc_ready_o` starts a descriptor.
- `desc_ready_o` is high only when no descriptor is active and no completion is waiting.
- `bready_o` is high while a descriptor is active and at least one response is still outstanding.
- `done_valid_o` asserts only after final W beat accepted and outstanding response count is zero.
- `done_valid_o` and `error_o` hold until `done_ready_i=1`.

## State elements

- `active_q`: descriptor active.
- `data_done_q`: final write data beat accepted.
- `outstanding_resp_q`: remaining expected B responses.
- `error_q`: captured non-OKAY response.
- `done_valid_o`, `error_o`: completion result visible to downstream logic.

## Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset | state unknown, `rst_i=1` | reset branch selected | clear active, counters, completion | idle, ready for descriptor | reset creates no false completion |
| descriptor accept | idle, `desc_valid_i=1` | `accept_desc=1` | load expected response count, set active | busy, outstanding count visible | descriptor owns subsequent B responses |
| last W before B | active, outstanding nonzero | `accept_last_data=1`, no B | set `data_done_q` only | no completion yet | last W beat is not completion |
| delayed B | data done, outstanding > 1 | `accept_b=1` | decrement outstanding | no completion yet | wait for every B response |
| final B | data done, outstanding = 1 | `accept_b=1` | decrement to zero, set done | completion visible | completion follows all B responses |
| error B | active, error response | `accept_b=1`, `bresp_i!=OKAY` | set error and continue draining | done waits until count zero | error does not skip response drain |
| done stall | `done_valid_o=1`, `done_ready_i=0` | `accept_done=0` | hold completion result | result unchanged | completion visible until accepted |

## Verification matrix

| Scenario | Stimulus | Expected result | Checker | Coverage target | Priority |
| --- | --- | --- | --- | --- | --- |
| reset | assert and release reset | idle, ready, no done | direct checks | first active cycle | high |
| last W early | final W accepted before B responses | no completion | direct checks | delayed B path | high |
| delayed responses | B responses arrive over later cycles | completion only after final B | ordered checks | response count 2 | high |
| completion stall | hold `done_ready_i=0` | done result stable | stability check | two stalled cycles | high |
| error drain | first B is error, later B is OKAY | error completion after all B | direct checks | error plus drain | high |
| same-cycle final | final W and final B same cycle | completion after edge | direct checks | simultaneous data/response | medium |

## Run

```text
python scripts/rtl_check.py --case evals/trials/dma_completion_slice_trial
```
