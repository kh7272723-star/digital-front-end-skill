# System contract template

## Purpose

Use this template before designing a subsystem or full system.
It prevents a large RTL request from becoming a guessed top-level implementation.

## Required fields

- system purpose,
- external protocols and clock domains,
- reset policy,
- configuration interface,
- command or descriptor lifetime,
- data path width, alignment, and ordering,
- backpressure and buffering policy,
- outstanding transaction limits,
- error and abort policy,
- completion and writeback policy,
- interrupt policy,
- unsupported or out-of-scope behavior.

## Output template

```text
System purpose:
External protocols:
Clock/reset:
Configuration and command source:
Data movement:
Ordering:
Backpressure:
Outstanding work:
Error/abort:
Completion/writeback:
Interrupt:
Unsupported cases:
```

## Decision rule

If the system contract is incomplete, produce the architecture and open questions.
Do not fill missing protocol behavior with guessed RTL.
