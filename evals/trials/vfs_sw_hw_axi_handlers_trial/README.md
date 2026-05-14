# VFS software-hardware AXI handlers

## Purpose

This trial adds the AXI full leaf handlers needed under the thesis section 4.1 software-hardware communication mechanism. It is still a bounded slice: single ID, one outstanding transaction, INCR burst assumption, and no external DDR model.

## Design contract

The two AXI handlers use explicit two-process FSMs. State and payload registers update in the clocked block; next-state and next-register values are selected in the combinational block.

### SQE AXI read handler

- Accepts an SQE read command with address and entry count.
- Uses states `S_IDLE -> S_AR -> S_R -> S_DONE`.
- Converts entry count to AXI beat count using `ENTRY_BEATS`.
- Issues one AR command and holds AR payload stable until `m_arvalid_o && m_arready_i`.
- Accepts R beats only after AR acceptance.
- Applies local SQE-stream backpressure through `m_rready_o`.
- Marks every `ENTRY_BEATS` accepted R beats with `sqe_entry_last_o`.
- Captures non-OKAY `RRESP` and `RLAST` misalignment as errors.
- Raises `done_valid_o` only after the final expected accepted R beat.

### CQE AXI write handler

- Accepts one CQE write command with address, data, and phase.
- Uses states `S_IDLE -> S_AW -> S_W -> S_B -> S_DONE`.
- Issues AW first, then one W beat, then waits for B.
- Holds AW and W payloads stable under independent channel stalls.
- Inserts the phase bit into data bit 0 for this executable slice.
- Raises `done_valid_o` only after an accepted B response.
- Captures non-OKAY `BRESP` as an error completion.

## Cycle trace

| Boundary | Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- | --- |
| Read AR | command accepted | active, AR not done | AR valid asserted | AR payload holds | AXI sees stable AR | address/len cannot change while stalled |
| Read R before AR | AR not accepted | R valid may arrive | `m_rready_o=0` | no counter update | beat count unchanged | no speculative R acceptance |
| Read stream stall | AR done, R valid, local not ready | `sqe_ready_i=0` | no beat accepted | data must be retried | local backpressure does not lose data |
| Read final beat | one beat remaining | accepted R with expected `RLAST=1` | done registers | completion visible | done waits for final accepted beat |
| Write AW | command accepted | AW valid, W disabled | AW payload holds | AW accepted when ready | W phase can start | W is not emitted before AW in this slice |
| Write W | AW done | W valid, WLAST=1 | W done on ready | BREADY may assert | single CQE write has one W beat |
| Write B | W done | B valid and ready | done registers with error flag | completion visible | CQE write is not complete before B |

## Directed checks

- Read AR payload hold under AR stall.
- No R acceptance before AR acceptance.
- R channel local backpressure preserves beat count.
- SQE entry-boundary flag every two beats in the fixture.
- Read completion waits for final expected R beat.
- Read `RRESP` error drains through final beat.
- Write AW payload hold under AW stall.
- W channel waits for AW acceptance in the conservative slice.
- W payload hold under W stall.
- Write completion waits for B response.
- Write `BRESP` error is reported.
