# AXI DMA planning example

## Purpose

This is an architecture planning example, not production AXI DMA RTL.
Use it when the user asks for a complete AXI DMA engine or similar large memory mover.

## System contract sketch

- Purpose: move data from source address to destination address using descriptors.
- External protocols: descriptor/config interface, AXI read address/data, AXI write address/data/response, optional status writeback and interrupt.
- Clock/reset: one clock in the first architecture pass unless the user specifies CDC.
- Ordering: descriptor completion occurs after all required read data is written and write responses are observed.
- Backpressure: AXI data channels, internal FIFOs, descriptor queue, and completion path can stall independently.
- Outstanding work: descriptors, read bursts, write bursts, and write responses need explicit counters or tags.
- Errors: AXI errors mark the descriptor failed and trigger drain or abort policy.
- Interrupt: interrupt follows visible completion state, not merely last data beat.

## Suggested decomposition

| Submodule | Responsibility | Key state |
| --- | --- | --- |
| descriptor_frontend | accepts descriptors and checks basic fields | descriptor queue, active descriptor valid |
| read_cmd_engine | converts descriptor ranges into AXI read bursts | read address, remaining bytes, read outstanding count |
| read_data_buffer | stores read data before write side accepts it | data FIFO occupancy, sideband alignment |
| write_cmd_engine | converts buffered data ranges into AXI write bursts | write address, burst length, write outstanding count |
| write_data_engine | emits AXI write data beats from buffer | beat count, last beat, byte enables |
| response_tracker | tracks AXI write responses and errors | response count, error status |
| completion_engine | emits writeback and interrupt | completion state, interrupt pending |
| top_integration | connects contracts and enforces invariants | global busy, flush, error, reset convergence |

## Interface contracts to define

- descriptor_frontend to read_cmd_engine: descriptor accepted, held, completed, or rejected.
- read_cmd_engine to read_data_buffer: read beat payload, byte lane validity, descriptor ID.
- read_data_buffer to write_data_engine: data availability and backpressure.
- write_cmd_engine to response_tracker: issued burst identity and expected response count.
- response_tracker to completion_engine: all writes acknowledged or error captured.
- completion_engine to software/status path: writeback visible before interrupt.

## Integration invariants

- Descriptor is not completed until all write responses for that descriptor are observed.
- Read data accepted into the buffer must eventually be written, reported as error, or discarded by an explicit abort.
- Internal data FIFO full must backpressure read data acceptance or stop issuing further reads before overflow.
- Write data must not be emitted without a matching write command policy.
- Interrupt must not assert before completion writeback is visible.
- Reset clears active descriptor, outstanding counters, valid flags, FIFO state, and interrupt pending.

## Risky local traces

Trace these boundaries before integration RTL:

- descriptor accepted while data FIFO later becomes full,
- read data returns while write side is stalled,
- last write data beat issued but write response delayed,
- AXI error response occurs after partial data movement,
- reset or abort with outstanding read and write work.

## Implementation sequence

1. Freeze system contract and unsupported AXI features.
2. Define descriptor format and outstanding limits.
3. Implement and verify descriptor_frontend and burst planner.
4. Implement read_cmd_engine and read_data_buffer with local tests.
5. Implement write_cmd_engine and write_data_engine with local tests.
6. Implement response_tracker and completion_engine.
7. Integrate one descriptor, no stalls.
8. Add backpressure tests.
9. Add error, abort, reset, and interrupt ordering tests.

## What not to do

- Do not write a monolithic AXI DMA top from a vague prompt.
- Do not assume unlimited outstanding transactions.
- Do not assert completion based only on the last data beat.
- Do not ignore AXI response errors.
- Do not treat AXI channels as one combined handshake.

## Executable slices

- `evals/trials/dma_burst_planner_trial`: descriptor to paired read/write burst commands and expected B response count.
- `evals/trials/dma_completion_slice_trial`: final write-data observation, B response drain, and descriptor completion ordering.
