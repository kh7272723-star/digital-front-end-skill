# Protocol edge-case checklist

## Purpose

Use this file before claiming a protocol block is complete.
It highlights edge cases that often pass simple tests but fail in integration.

## Ready/valid

- Source holds payload stable while valid is high and downstream is not ready.
- Destination may assert ready before valid, after valid, or in the same cycle.
- Replacement cycle is defined when output is accepted and input is accepted together.
- Sideband fields move with payload.
- Ready path has no unintended combinational loop.

## FIFO and buffering

- Full write/read same-cycle policy is explicit.
- Empty read/write same-cycle policy is explicit.
- Memory read timing is explicit.
- Overflow and underflow attempts are ignored, blocked, or flagged by contract.
- Count, pointers, memory access, and status flags use the same accepted-operation contract.

## Arbiter

- Grant is one-hot or explicitly encoded.
- Grant hold policy under downstream stall is defined.
- Fairness or starvation expectation is stated.
- Priority update occurs only on accepted transfer.

## Req/ack

- Request lifetime is level or pulse based.
- Ack without outstanding request is ignored or flagged.
- New request while busy is blocked, queued, or unsupported.
- Request clears only after the contract says the operation is complete.

## AXI-like systems

- Independent channels are not collapsed into one handshake.
- Outstanding read, write, and response counts are bounded.
- Write response is observed before completion.
- Error response has drain or abort behavior.
- Interrupt follows visible completion.

## AXI full

- AW, W, B, AR, and R are independently backpressured.
- Burst beat count and last-beat markers match the accepted command.
- ID and ordering policy is explicit before RTL.
- Outstanding counters cannot underflow or overflow.
- Completion waits for required B or R responses, not only last data beat.

## AXI-Lite

- Write address and write data may arrive in either order.
- Write response follows both accepted write address and accepted write data.
- Read data and response hold under read backpressure.
- Byte strobes update only selected byte lanes.
- Decode errors do not update state unless the contract explicitly says otherwise.

## AXI DMA

- Last write data beat is not the same as descriptor completion.
- Write response tracking is required before completion.
- Read and write channels can stall independently.
- Outstanding work has bounded counters or tags.
- Abort/reset policy covers commands already accepted by the external bus.

## APB

- Setup phase and access phase are distinct.
- Register updates occur only on completed access.
- Wait states do not update state.
- Byte strobes update only selected lanes.
- Error response is tied to a completed access.

## AHB-Lite

- Address/control phase and data phase are distinct.
- Write data belongs to the previous accepted address phase.
- `HREADY` wait behavior holds data-phase state.
- Back-to-back transfers preserve phase alignment.

## AXI-Stream

- Payload and sideband move together.
- Payload and sideband hold stable under downstream backpressure.
- `TLAST` packet boundary stays aligned with data.
- `TKEEP` or byte-lane information is preserved through conversion.

## CDC

- Single-bit, pulse, multi-bit, and FIFO crossings are treated differently.
- Multi-bit coherency is not assumed from per-bit synchronizers.
- Reset crossing behavior is defined.
