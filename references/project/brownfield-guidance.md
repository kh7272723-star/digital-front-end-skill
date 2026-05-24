# Brownfield RTL guidance

## Purpose

Use this file when modifying existing RTL.
Brownfield work is not greenfield design: read first, match style, and touch only the requested behavior.

## Workflow

1. Inspect project conventions: naming, reset, FSM style, lint style, and testbench framework.
2. Read the complete target module or request the missing context if the snippet is incomplete.
3. Identify the exact modification point: signal, always block, state transition, or instantiation.
4. Match existing style: reset polarity, suffixes, indentation, always-block organization, and comments.
5. Make the minimal diff; avoid unrelated cleanup.
6. State what behavior is preserved.
7. Add or propose one regression for old behavior and one directed check for the new behavior.

## Pitfalls

- style mismatch that makes the patch hard to review,
- new condition shadowing an existing transition,
- new port not connected in all instantiations,
- new parameter default changing old behavior,
- reset polarity or synchrony drift,
- comments no longer matching behavior.

## Output rule

For brownfield tasks, lead with observed conventions and the intended modification point before showing code.
