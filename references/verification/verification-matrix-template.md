# Verification matrix template

## Purpose

Use this matrix to plan tests beyond a single directed example.
The agent should generate a matrix when the design has protocol state, queues, backpressure, or subsystem integration.

## Matrix fields

| Scenario | Stimulus | Expected result | Checker | Coverage target | Priority |
| --- | --- | --- | --- | --- | --- |

## Required scenario classes

- Reset and first active cycle.
- One normal transaction.
- Consecutive transactions.
- Boundary condition.
- Stall or backpressure.
- Simultaneous movement, such as read/write or accept/consume.
- Error or illegal request.
- Flush, abort, or recovery if supported.
- Randomized or permuted ordering if the design tracks multiple items.

## Checker guidance

- Use direct comparisons for single outputs.
- Use a scoreboard when ordering or queues matter.
- Use counters for accepted versus completed work.
- Use stability checks for hold behavior.
- Use timeout checks for liveness.

## Example row

| Scenario | Stimulus | Expected result | Checker | Coverage target | Priority |
| --- | --- | --- | --- | --- | --- |
| downstream stall | hold `ready_i=0` while `valid_o=1` | `data_o` and sideband stable | stability monitor | stall length 1, 2, many cycles | high |

## Review rule

If the matrix has no checker for the highest-risk invariant, the verification plan is not integration-ready.
