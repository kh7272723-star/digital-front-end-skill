# Staged bring-up guidelines

## Purpose

Use staged bring-up for large systems or modules with multiple interacting features.
This prevents the agent from trying to solve every protocol corner in one pass.

## Bring-up ladder

1. Smoke test: reset, idle, no transaction.
2. One transaction, no stalls.
3. Back-to-back transactions, no stalls.
4. Single downstream stall.
5. Independent upstream and downstream stalls.
6. Boundary conditions: full, empty, last beat, count zero, max count.
7. Error path: explicit error event and recovery policy.
8. Flush or abort path.
9. Randomized stress within stated constraints.
10. Integration scenario with neighboring modules.

## Staged implementation rule

For each stage:

- state what feature is added,
- state which previous behavior must remain unchanged,
- add or update one check,
- stop if a contract must change.

## AXI DMA bring-up example

- Stage 1: accept one descriptor and mark it busy.
- Stage 2: issue one read command without stalls.
- Stage 3: buffer read data and issue one write command.
- Stage 4: wait for write response before completion.
- Stage 5: add read and write backpressure.
- Stage 6: add multiple bursts and outstanding counters.
- Stage 7: add AXI error response handling.
- Stage 8: add writeback and interrupt ordering.
- Stage 9: add reset or abort with outstanding work.

## Stop conditions

Stop and revise architecture when:

- a stage requires two owners for the same state,
- a new stall path can deadlock with an existing wait,
- a completion event can occur before visible side effects,
- error recovery cannot drain or cancel outstanding work,
- the testbench cannot observe the required invariant.
