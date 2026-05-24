# RTL writing guidelines

## Purpose
This file turns authoritative design practice into actionable writing rules for the skill.
It is not a general reading list.
It is the distilled behavior the agent should follow when writing or reviewing Verilog RTL.

## How source guidance becomes code

Use standards and methodology guidance to justify concrete decisions:

| Source idea | RTL rule | Verification check |
| --- | --- | --- |
| Registered state updates are edge-triggered | put state in `always @(posedge clk_i)` and use nonblocking assignments | check next-cycle visibility |
| Combinational logic should not imply storage | assign defaults and cover every branch | lint for latch inference |
| Valid data must remain stable under backpressure | gate data updates with the same condition as valid movement | assert stable payload while stalled |
| Reset must create known visible behavior | define reset values for state and protocol outputs | check reset and first post-reset cycle |
| Boundary behavior is part of the spec | define full/empty, overflow/underflow, write/read conflict policy | directed boundary tests |

## 1. Write the contract before code
Before generating RTL, state:
- the module purpose
- the clock and reset scheme
- the input/output handshake
- the latency or throughput target
- the boundary behavior
- the illegal or unsupported cases

## 2. Preserve cycle semantics in the code structure
Use code structure that makes timing obvious:
- edge-triggered blocks for state
- combinational blocks for next-state and outputs
- explicit default assignments in combinational logic
- one driver per signal
- no hidden storage in combinational blocks

## 3. Prefer standard sequential semantics
For stateful RTL:
- use nonblocking assignments for registered updates
- keep the update condition readable
- do not bury handshake or stall logic inside opaque expressions
- keep reset behavior explicit and consistent across related registers

## 4. Make protocol behavior visible
For ready/valid or similar protocols:
- define the transfer condition once
- define when data is sampled
- define when data must remain stable
- define how backpressure propagates
- define what happens when both sides assert their control signals in the same cycle

## 5. Make pipeline behavior visible
For pipelines or delayed paths:
- name the stage latency
- keep data and control aligned
- define stall and flush behavior separately
- explain whether a register stage is transparent or holding during each cycle

## 6. Make state machines inspectable
For FSMs:
- list legal states in the design contract
- give each state a meaning
- define reset state
- define outputs per state
- define transitions before implementation
- prefer two-process FSM style for multi-stage control: one clocked block for `*_q <= *_d`, one combinational block for defaults, transitions, and next values
- use implicit flag/counter control only for small single-path trackers, and document the equivalent states

## 7. Make FIFO behavior unambiguous
For FIFO-like storage:
- define empty/full boundary behavior
- define simultaneous write/read behavior
- define overflow and underflow handling
- define whether occupancy or pointer logic is the primary source of truth

## 8. Make debug evidence-driven
When a log or waveform is provided:
- identify the first cycle where behavior diverges
- locate the signal that changed too early, too late, or not at all
- keep the proposed fix minimal
- re-check the contract after the fix

## 9. Make verification part of the deliverable
For every nontrivial RTL deliverable, include:
- a minimal directed test list
- one boundary case
- one handshake or stall case when relevant
- the key waveform observation points
- the assertion or check that protects the contract

## 10. Use conservative engineering defaults
Prefer the simplest implementation that:
- is synthesizable
- is readable
- matches the stated timing contract
- is easy to verify
- avoids ambiguous corner behavior

## 11. Respect local project style

If the user provides existing RTL, match its local style when it does not conflict with correctness:

- module naming and port naming
- active-high or active-low reset convention
- one-process, two-process, or three-process FSM style
- plain Verilog versus SystemVerilog constructs
- assertion style and testbench framework

Do not rewrite unrelated style in code review. Only change style when it affects correctness, timing clarity, or integration.

## When to ask questions
Ask before coding if any of these are unclear:
- reset polarity or synchrony
- handshake semantics
- latency or throughput target
- overflow/underflow policy
- CDC or multi-clock involvement
- whether the output should change in the same cycle or the next cycle

If the missing detail blocks a correct design, ask before coding. If a conservative default is safe and obvious, state it as an assumption and proceed.
