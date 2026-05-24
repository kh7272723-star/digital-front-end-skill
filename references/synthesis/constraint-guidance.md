# Constraint guidance

## Purpose

Use this file when the user asks for SDC/XDC constraints, clocking, CDC constraints, generated clocks, IO timing, false paths, or multicycle paths.
Constraints are project-specific; templates need explicit assumptions.

## Minimum constraint contract

- primary clocks and periods,
- generated clocks and source relationship,
- reset synchrony and clock-domain ownership,
- external IO timing budget,
- asynchronous clock groups,
- intended false paths or multicycle paths and their functional reason.

## Common templates

- Primary clock: `create_clock -period <ns> [get_ports clk_i]`.
- External inputs: `set_input_delay` relative to the capturing clock.
- External outputs: `set_output_delay` relative to the launching clock.
- Unrelated clocks: `set_clock_groups -asynchronous`.
- CDC synchronizer datapath control: use project-approved max-delay or false-path style.

## Caution rules

- Do not add false paths to hide real synchronous timing paths.
- Do not add multicycle paths unless the RTL has a matching enable/hold contract.
- Generated clocks must be constrained when logic creates a real clock; prefer clock enables over generated logic clocks.
- IO delay values are placeholders unless board-level timing is known.

## Output rule

State the assumptions and mark every placeholder value that must be replaced by board, IP, or STA owner data.
