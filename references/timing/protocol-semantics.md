# Protocol semantics guidelines

## Purpose
This file turns protocol behavior into explicit writing rules for the skill.
The agent should use it to reason about ready/valid, request/ack, pipeline handoff, FIFO boundaries, and similar interface contracts.
Use `naming-guidelines.md` for signal names and `cycle-trace-guidelines.md` before writing stateful protocol RTL.

## 1. Every protocol needs an explicit contract
For each interface, state:
- who produces data or requests
- who consumes data or acknowledgments
- what means 'accepted'
- what means 'held'
- what means 'released'
- what happens under backpressure

## 2. Ready/valid is a cycle-level contract
- valid means data is available and stable.
- ready means the receiver can accept in that cycle.
- transfer happens only when both are true in the same cycle.
- if valid remains high while ready is low, data must remain stable until acceptance.
- once valid is asserted for an item, valid must remain asserted until the ready/valid transfer completes.
- payload and sideband fields protected by valid must remain stable while `valid && !ready`.
- ready may be asserted before valid, after valid, or in the same cycle, unless a protocol subset says otherwise.

Use consistent direction names when writing examples:

- `valid_i`, `data_i`: upstream producer into this block.
- `ready_o`: this block can accept upstream input.
- `valid_o`, `data_o`: this block drives downstream.
- `ready_i`: downstream can accept this block's output.
- `accept_input = valid_i && ready_o`: this block accepts an input item.
- `accept_output = valid_o && ready_i`: downstream accepts an output item.

For multiple interfaces, add a short interface prefix before the suffix, for example `req_valid_i`, `req_ready_o`, `rsp_valid_o`, and `rsp_ready_i`.

## 3. Request/ack needs lifetime rules
- define whether request is level-based or pulse-based.
- define whether acknowledgment is immediate or deferred.
- define whether the request must remain asserted until ack.
- avoid ambiguous handshakes that appear to work in one test but fail under stall.

## 4. Pipeline handoff must preserve alignment
- data, valid, and sideband fields must move together.
- if a stage stalls, every field protected by the protocol must stall consistently.
- if a stage flushes, define exactly which fields clear and which fields are discarded.

## 5. FIFO boundaries are part of the protocol
- define full and empty behavior in the same spec as the interface.
- define whether a simultaneous write and read is allowed at full or empty.
- define how the design prevents overflow and underflow.
- do not leave boundary behavior to synthesis interpretation.
- define RAM read-during-write behavior if a simultaneous read and write can touch the same address.

## 6. Backpressure must be visible and local
- a receiver should deassert ready for a reason the source can understand.
- avoid hidden combinational loops through ready paths unless the architecture explicitly allows them and they are verified.
- explain where backpressure originates and how far it propagates.

For a one-entry ready/valid register slice, the common rule is:

- accept new input when the storage is empty or when the stored output is being consumed,
- hold stored data while `valid_o && !ready_i`,
- deassert `ready_o` only when the storage is full and downstream is not consuming,
- never overwrite stored data while it is waiting.

## 7. Sideband signals must follow the same contract as data
- tags, keep masks, IDs, parity bits, and error flags must not drift by a cycle.
- if a sideband field is registered, its timing must be described explicitly.
- a correct payload with a misaligned sideband is still a bug.

## 8. The skill should ask before assuming protocol meaning
Ask questions if unclear:
- is the interface level-based or edge-based
- is ready/valid source-driven or sink-driven in the implementation
- can the producer change data while valid is high and ready is low
- what is the policy on overflow or underflow
- do sideband fields share the same latency as data

## 9. The skill should produce protocol artifacts
When protocol behavior matters, output:
- a short contract summary
- a cycle-by-cycle explanation of acceptance and release
- a cycle trace table for stateful protocol logic
- a boundary case list
- a verification checklist
- a note about any unsupported or unsafe behavior

## 10. Protocol anti-patterns

Flag these during review:

- valid changes data while ready is low.
- ready depends combinationally on an upstream ready path and forms a loop.
- FIFO pointer updates and count updates use different write/read enable conditions.
- full, empty, valid, and ready are treated as style details instead of part of the contract.
- sideband fields are registered on a different enable than payload data.
