# DMA descriptor and burst planning guidelines

## Purpose

Use this file when moving from DMA architecture to executable command-generation slices.
This guidance is distilled from Arm AMBA AXI burst rules and mature DMA designs such as alexforencich `verilog-axi` DMA modules and PULP `axi` infrastructure.

## Conservative first slice

For the first descriptor-to-command slice:

- one descriptor active at a time,
- aligned source and destination addresses,
- byte count must be nonzero and a multiple of the data bus byte width,
- INCR-style full-width beats only,
- maximum burst length is fixed locally,
- read and write command counts match,
- expected B response count equals issued write burst count.

Do not implement unaligned transfers, narrow beats, 4KB boundary splitting, scatter-gather rings, or abort until this slice is verified.

## Descriptor contract

Define:

- source address,
- destination address,
- byte count,
- supported alignment,
- maximum burst beats,
- command issue policy under read/write command backpressure,
- completion metadata: total beats, read bursts, write bursts, expected B responses.

## Required cycle rows

Include rows for:

- descriptor accept,
- first full burst command pair,
- read command stall,
- write command stall,
- final short burst,
- zero-length descriptor reject,
- unaligned descriptor reject.

## Verification minimum

Include checks for:

- bytes-to-beats conversion,
- burst length field equals beats minus one,
- source and destination address increments together,
- read and write command counts match,
- expected B response count equals write command count,
- no command emitted for rejected descriptor,
- backpressure holds command payload stable.

## Golden fixture

Use `evals/trials/dma_burst_planner_trial` as the executable local example.
Run:

```text
python scripts/rtl_check.py --case evals/trials/dma_burst_planner_trial
```
