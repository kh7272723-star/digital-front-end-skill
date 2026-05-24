# Timing and protocol discipline

## Core rules

- Always explain stateful behavior in cycle terms before implementation.
- For every nontrivial block, write the cycle contract first: what changes now, what changes next, and what must stay stable.
- For FSM, FIFO, pipeline, or handshake logic, include a cycle trace before RTL.
- For complete subsystems, decompose first and trace only risky local boundaries.
- Use two-process FSMs for multi-stage control: one clocked block for `state_q <= state_d`, one combinational block for defaults, transitions, and outputs. See `references/rtl/fsm-examples.md`.
- For ready/valid logic, define exactly when data is accepted, held, and released.
- For FSMs, list legal states and the reset state before coding.
- For FIFOs and pipelines, define boundary behavior and alignment rules.
- For CDC or multi-clock logic, do not improvise; require an explicit safe crossing pattern.

## Cycle trace format

See `references/timing/cycle-trace-guidelines.md` for the full template. The trace must include:

- pre-edge state
- combinational condition
- active-edge update
- next visible state
- invariant

If the trace exposes an unspecified reset, stall, flush, or boundary case, ask or state a conservative assumption before RTL.

## Timing contract

Before writing code, produce a short timing contract using the template in `references/timing/timing-contract-template.md`. Include:

- module purpose
- clock domain(s)
- reset style
- input handshake
- output handshake
- data latency
- stall behavior
- flush behavior
- boundary behavior
- illegal or unsupported cases

If any field is irrelevant, mark as `not applicable` instead of inventing behavior.
