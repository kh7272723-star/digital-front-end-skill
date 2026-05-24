# Advanced RTL patterns

## Purpose

Use these patterns after the basic examples when a task needs more than a FIFO, FSM, or simple pipeline.
Each pattern still requires a contract and local cycle trace before RTL.

## Priority arbiter

Use when multiple requesters compete for one resource and fixed priority is acceptable.

Contract points:

- request lifetime,
- grant encoding,
- whether grant is combinational or registered,
- whether grant holds until transaction completion,
- starvation expectations.

Checks:

- at most one grant,
- highest-priority active request wins,
- held grant is not revoked before the contract allows.

## Round-robin arbiter

Use when fairness matters.

Contract points:

- pointer update condition,
- whether inactive requesters are skipped,
- whether grant is held under backpressure,
- reset priority.

Checks:

- no requester with a persistent request is starved under stated assumptions,
- pointer advances only after accepted grant.

## Req/ack adapter

Use when a level request must remain asserted until acknowledgment.

Contract points:

- `req_o` lifetime,
- `ack_i` meaning,
- whether a new request can start while one is outstanding,
- pulse versus level behavior.

Checks:

- request holds until ack,
- no double issue while busy,
- ack without request is ignored or flagged according to contract.

## Counter/event detector

Use for timeout, length tracking, beat counting, and pulse generation.

Contract points:

- enable condition,
- clear/load priority,
- wrap versus saturate,
- terminal count pulse width,
- relation to data beat acceptance.

Checks:

- terminal pulse exactly one cycle unless contract says otherwise,
- count changes only on accepted events,
- clear/load priority matches the trace.

## CDC policy patterns

Do not improvise CDC RTL.

Allowed planning patterns:

- two-flop synchronizer for single-bit level controls,
- pulse-to-toggle synchronizer for isolated pulses,
- handshake synchronizer for event transfer,
- gray-coded pointer async FIFO for multi-bit ordered data,
- CDC review requirement for multi-bit status snapshots.

For generated CDC code, require the user to supply clock relationship, reset strategy, data coherency requirement, and project CDC methodology.
