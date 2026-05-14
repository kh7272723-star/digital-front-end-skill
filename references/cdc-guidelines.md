# CDC guidelines

## Purpose

Use this file for clock-domain crossing, multi-clock reset, async FIFO, synchronizer, metastability, and CDC review requests.
CDC correctness is a methodology topic; do not claim it from RTL inspection alone.

## Safe pattern selection

- Single-bit slow level: two-flop synchronizer in the destination clock domain.
- Single-cycle pulse: convert to toggle or handshake before crossing.
- Multi-bit coherent value: use request/acknowledge with source-side data hold, a gray-coded counter, or an async FIFO.
- Stream or queue traffic: use an async FIFO with gray-coded pointers and full/empty checks.
- Reset: asynchronous assertion is allowed by project style, but deassertion must be synchronized per destination clock domain.

Do not synchronize each bit of a multi-bit bus independently and call it coherent.

## Required contract fields

- source clock and destination clock relationship,
- data coherence requirement,
- event loss tolerance,
- reset assertion and deassertion policy,
- maximum source and destination rates,
- chosen CDC primitive and constraints.

## Verification and constraints

- Simulate with unrelated clock periods and varied phase offsets.
- For handshake CDC, check that data is stable while the request is outstanding.
- For async FIFO, check no overflow, no underflow, and one-bit gray pointer changes.
- Mark synchronizer flops with project-approved attributes such as `ASYNC_REG`.
- Declare unrelated clocks with the project STA method, commonly `set_clock_groups -asynchronous`.
- Use CDC tools or formal apps for signoff; directed simulation is only a sanity check.

## Refusal rule

If the user asks for guessed CDC RTL without clock relationship, data coherency, or event-loss policy, provide the contract questions and a safe pattern recommendation instead of final RTL.
