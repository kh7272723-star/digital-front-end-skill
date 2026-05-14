# AXI DMA channel guidelines

## Purpose

Use this file when a DMA, memory mover, bus bridge, or AXI subsystem request includes AXI read, AXI write, completion, errors, or interrupts.
This is not a full AXI specification; it is a checklist that prevents common wrong RTL assumptions before detailed implementation.
This guidance is distilled from the Arm AMBA AXI protocol family and must be checked against the project-selected AXI version before signoff.

## AXI channel separation

Treat each AXI channel as independently backpressured:

- read address issues commands,
- read data returns beats and response status,
- write address issues write commands,
- write data emits payload beats,
- write response confirms write completion status.

Do not merge channels into one transaction handshake in RTL or explanation.
Each channel needs an owner, acceptance condition, held payload rule, outstanding counter, and error path.

## DMA ordering rules

- A descriptor is not complete when the last write data beat is emitted.
- Completion requires all required write responses for that descriptor to be observed.
- Interrupt follows visible completion state or writeback, not the last data beat.
- Read data accepted internally must be written, drained by an explicit error policy, or discarded only by a defined abort/reset policy.
- Errors need a first-error capture rule and a drain or abort rule.

## Burst and beat accounting

Before RTL, define:

- maximum burst length,
- address alignment policy,
- byte count to beat conversion,
- last-beat generation,
- write strobe policy,
- boundary crossing policy,
- outstanding read limit,
- outstanding write command limit,
- outstanding write response limit,
- descriptor ID or ordering rule.

If any item is missing, write architecture or one leaf module only.

## Risky local traces

Trace these before implementation:

- read command accepted but data FIFO later becomes full,
- read data returns while write data channel is stalled,
- write address accepted but write data is delayed,
- last write data beat emitted while write response is delayed,
- error response arrives after partial movement,
- abort/reset occurs with outstanding read or write work,
- completion writeback is delayed while interrupt is requested.

## Verification minimum

For a DMA slice, include:

- command count versus response count checks,
- descriptor byte count versus emitted beat count,
- data ordering scoreboard,
- backpressure on every AXI channel independently,
- error response and drain/abort tests,
- completion-after-write-response check,
- interrupt-after-visible-completion check.

## Golden completion slice

Use `evals/trials/dma_burst_planner_trial` as the executable first slice for descriptor parsing and burst command generation.
Use `evals/trials/dma_completion_slice_trial` as the executable first slice for completion ordering.
It models one active descriptor, final write-data acceptance, expected B response count, error capture, and completion hold.

The burst planner fixture checks:

- descriptor byte count converts to full-width beat count,
- source and destination addresses increment together,
- read and write command lengths match,
- read and write command backpressure holds payload stable,
- expected B response count equals write command count,
- invalid descriptors emit error completion and no commands.

Key rule captured by the fixture:

- final W beat acceptance sets data-side done only,
- each accepted B response reduces outstanding response count,
- descriptor completion appears only after data-side done and response count zero,
- any non-OKAY B response marks the descriptor error after all expected responses drain.

Run:

```text
python scripts/rtl_check.py --case evals/trials/dma_completion_slice_trial
```
