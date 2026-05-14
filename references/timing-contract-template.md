# Timing contract template

## Purpose

Use this template before writing RTL or debugging RTL.
It forces the agent to describe cycle behavior explicitly.

## Required fields

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

## Cycle contract questions

1. What is visible in the current cycle?
2. What is registered for the next cycle?
3. What must remain stable while waiting?
4. What happens when both sides are ready or not ready?
5. What happens on the first cycle after reset release?
6. What happens at the full/empty or valid/invalid boundary?

## Output format

When the skill uses this template, it should produce:

- a short timing summary
- a table or bullet list of cycle behavior
- any assumptions that still need confirmation
- a note about which signals are held or advanced each cycle