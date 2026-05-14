# Micro-architecture decisions

## Purpose

Use this file when there are multiple valid RTL architectures.
State the tradeoff instead of silently choosing a shape that changes latency, throughput, area, or verification burden.

## Default decisions

| Decision | Default | Ask when |
| --- | --- | --- |
| FIFO read timing | registered read | zero-latency read may be required |
| Pipeline control | global advance for short simple pipelines | stages have independent stalls or throughput is critical |
| FSM encoding | binary for small FSMs | many states or timing-critical decode |
| FIFO depth | derive from burst plus stall margin | burst/stall rates are unknown and matter |
| Register slice vs skid buffer | register slice | upstream cannot stop immediately |
| Arbitration | fixed priority if priority is named, otherwise round-robin for fairness | starvation policy matters |
| Multiplier | pipelined for continuous data | operation is rare or area-constrained |
| Reset | synchronous active-high for examples | project style says otherwise |

## Decision flow

1. Does the choice affect the external interface? Put it in the contract and ask if unclear.
2. Is there a standard safe default? Choose it, state it, and continue.
3. Could the wrong choice force redesign? Present the tradeoff before RTL.

## Output rule

When a tradeoff matters, state options considered, chosen option, reason, cost, and verification implication.
