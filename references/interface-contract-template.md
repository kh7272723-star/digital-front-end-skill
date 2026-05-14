# Interface contract template

## Purpose

Use this template for submodule boundaries in subsystem and full-system designs.
It makes integration timing explicit without tracing every register.

## Required fields

- interface name,
- producer,
- consumer,
- payload fields,
- sideband fields,
- transfer condition,
- hold rule,
- release rule,
- backpressure direction,
- latency,
- ordering guarantee,
- reset behavior,
- flush or abort behavior,
- error behavior,
- checks.

## Output template

| Field | Contract |
| --- | --- |
| Interface | |
| Producer | |
| Consumer | |
| Payload | |
| Sideband | |
| Transfer condition | |
| Hold rule | |
| Release rule | |
| Backpressure direction | |
| Latency | |
| Ordering | |
| Reset | |
| Flush or abort | |
| Error behavior | |
| Checks | |

## Integration rule

Every top-level connection must connect two compatible interface contracts.
If the producer can advance while the consumer must hold, add buffering or change the contract before RTL.
