# VFS software-hardware communication slice

## Scope

This trial is a Verilog-first executable slice for the thesis section 4.1 software-hardware communication mechanism. It models the timing-sensitive part of the mechanism, not the whole AXI master subsystem.

Covered behavior:

- Submission queue tail doorbell tracking.
- Submission read-command generation with ring-boundary split and maximum burst split.
- Completion queue single-entry write command generation.
- Completion tail update only after the downstream write-completion indication.
- Completion phase value toggling on CQ ring wrap.
- Completion backpressure with a one-empty-slot full policy.
- Aggregated interrupt pulse by CQE-count, byte-count, or timeout threshold.

## Contract

- `rst_i` is synchronous active high.
- SQ software owns `sq_tail_db_i`; hardware owns `sq_head_o`.
- SQ command length is an entry count, not AXI `ARLEN`.
- SQ commands never cross the ring boundary and never exceed `MAX_BURST_ENTRIES`.
- CQ software owns `cq_head_db_i`; hardware owns `cq_tail_o`.
- CQ accepts one completion only when no CQ write is already in progress and the ring is not full.
- CQ tail and visible pending count update after `cq_write_done_i`, representing the downstream AXI write response point.
- `cq_cmd_phase_o` is the phase value written into the CQE slot. It toggles after the tail wraps.
- `irq_pulse_o` is one cycle wide. Priority is CQE count, then byte count, then timeout.
- Zero interrupt thresholds disable the corresponding trigger.

## State elements

- SQ: `sq_head_q`, `sq_tail_q`, registered command valid/address/length.
- CQ: `cq_head_q`, `cq_tail_q`, `cq_phase_q`, command state, captured completion byte count.
- IRQ: accumulated CQE count, accumulated byte count, and timeout counter.

## Cycle trace

| Cycle | Pre-edge state | Combinational condition | Active-edge update | Next visible state | Invariant |
| --- | --- | --- | --- | --- | --- |
| reset release | all pointers reset, no command valid | normal path selected | no transaction accepted | SQ/CQ empty, interrupt low | reset creates no false command |
| SQ doorbell | `sq_tail_q` old, `sq_head_q` stable | doorbell write active | `sq_tail_q` captures new tail | pending becomes visible next cycle | software tail is sampled on clock edge |
| SQ issue | pending entries visible | command length is min(pending, until-wrap, max-burst) | command valid/address/length registered | downstream sees legal command | command never crosses ring boundary |
| SQ accept | command valid and ready | `accept_sq_cmd=1` | head advances by command length | remaining pending visible | no skipped SQE |
| CQ accept | CQ idle and not full | `accept_cpl=1` | command fields capture tail address and phase | CQ write command visible | one CQE write per completion |
| CQ write done | command accepted, waiting for done | `cqe_commit=1` | tail advances; phase toggles on wrap; IRQ counters update | completion becomes visible to software | CQE is committed only after write response |
| CQ full | next tail equals software head | `cpl_ready_o=0` | no new completion accepted | pending count preserved | no overwrite of unread CQE |
| timeout | accumulated count nonzero | timer reaches threshold | one interrupt pulse, counters clear | new aggregation window begins | pending completion cannot wait forever |

## Directed checks

- Reset release leaves SQ/CQ empty.
- SQ tail `0 -> 3` splits into lengths `2` and `1`.
- SQ tail wrap `3 -> 1` splits at ring boundary.
- CQ tail does not advance before `cq_write_done_i`.
- CQ count threshold triggers an interrupt pulse.
- CQ one-empty-slot full policy blocks further completion input.
- CQ head doorbell releases completion backpressure.
- CQ phase toggles after tail wrap.
- Byte threshold triggers after accumulated bytes cross the threshold.
- Timeout threshold triggers for a partial aggregation window.
