# VFS software-hardware communication hierarchy

## Purpose

This trial continues the thesis section 4.1 implementation by splitting the first monolithic slice into engineering-sized leaf modules. It keeps AXI bus handlers outside the scope and treats them as ready/valid command consumers.

## Architecture contract

- `sqe_read_cmd_gen` owns the submission queue head pointer and emits legal SQE read commands.
- `cqe_write_cmd_gen` owns the completion queue tail pointer and emits one CQE write command per accepted completion.
- `irq_aggregator` observes registered committed-CQE pulses and generates one-cycle aggregated interrupt pulses.
- `vfs_sw_hw_comm_core` wires the CQ commit pulse into the interrupt aggregator.

## FSM style

- `sqe_read_cmd_gen` uses a two-process FSM: `S_IDLE -> S_ISSUE`.
- `cqe_write_cmd_gen` uses a two-process FSM: `S_IDLE -> S_ISSUE -> S_WAIT_DONE`.
- Pointer, command, phase, and commit registers use `*_q/*_d` current/next naming.
- `irq_aggregator` remains counter-based because it is an event accumulator rather than a multi-stage controller.

## Interface contracts

- SQ software updates the tail doorbell. Hardware samples it on `sq_tail_db_wr_en_i`.
- SQ read commands are accepted on `cmd_valid_o && cmd_ready_i`.
- CQ completion input is accepted only when `cpl_valid_i && cpl_ready_o`.
- CQ tail advances only on `write_done_i` after the CQ write command has been accepted.
- IRQ aggregation sees committed CQEs one cycle after the CQ write response, not speculative CQ write commands.

## Local cycle traces

| Boundary | Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- | --- |
| SQ | tail doorbell | old tail, stable head | doorbell write active | tail captures doorbell | pending entries visible | software intent is sampled on edge |
| SQ | command issue | pending nonzero, no valid command | length=min(pending, until-wrap, max-burst) | command registers load | legal read command visible | no command crosses ring wrap |
| SQ | command accept | command valid | `valid && ready` | head advances by length | pending decreases | no SQE skipped or duplicated |
| CQ | completion accept | CQ idle and not full | `valid && ready` | command captures tail address and phase | CQ write command visible | no overwrite of unread CQE |
| CQ | write complete | command accepted | write response done | tail advances, commit pulse registers | CQE visible to software | completion is not counted before writeback |
| IRQ | commit count | registered commit visible | commit pulse arrives | count/bytes update or pulse | aggregation window advances | interrupt reason has fixed priority |
| IRQ | timeout | partial window active | timer reaches threshold | timeout pulse emits, counters clear | new window starts | lone completion cannot wait forever |

## Directed checks

- SQ burst limit split.
- SQ ring-boundary split.
- CQ write-response gating.
- CQ one-empty-slot full policy.
- CQ head doorbell backpressure release.
- CQ phase toggling on wrap.
- IRQ by completion count.
- IRQ by byte count.
- IRQ by timeout.
