# Clock and reset guidelines

## Purpose
This file distills the clock and reset discipline the skill should enforce when writing or reviewing Verilog RTL.
The goal is to make timing visible, reset behavior explicit, and post-reset behavior predictable.

## 1. Treat clock edges as the boundary of visible state change
- Registered state becomes visible after the active clock edge.
- Do not describe a register as changing 'inside' a cycle.
- When reasoning about behavior, separate pre-edge state, edge-triggered updates, and next-cycle visibility.

## 2. Keep one primary clock per synchronous region
- Prefer a single explicit clock for a synchronous block of logic.
- If more than one clock is involved, make the boundaries explicit.
- Do not blur local clock enable logic with clock-domain behavior.
- Prefer clock-enable logic over generated clocks, ripple clocks, or ad hoc gated clocks.
- If clock gating is required, require the project clock-gating cell and methodology.

## 3. Use a clearly stated reset style
- State whether reset is synchronous or asynchronous.
- State whether it is active-high or active-low.
- Use the same reset style consistently for related registers.
- Do not mix reset meanings inside one control block unless the contract requires it.
- If reset is asynchronous, state how deassertion is synchronized in each affected clock domain.

## 4. Define what reset does to visible outputs
- Specify whether outputs are forced to zero, held idle, or otherwise initialized.
- Do not assume 'reset' means 'internally initialized only' unless that is written down.
- For stateful interfaces, define whether valid-like signals are cleared during reset.

## 5. Define the first cycle after reset release
- The first active cycle after reset deassertion must be explicit in the contract.
- State whether the block accepts data immediately, waits one cycle, or performs a housekeeping transition.
- This is where many off-by-one bugs are born, so the skill should always ask or specify it.
- Valid-like outputs should normally be low on reset and remain low until the first meaningful item is available.

## 6. Keep reset behavior local and readable
- Reset logic should be obvious in the sequential block.
- Avoid burying reset side effects in nested conditions that are hard to scan.
- If several registers must leave reset in a coordinated way, describe the relationship in the contract.

## 7. Use enables and stalls intentionally
- Clock enables should gate state updates, not redefine the meaning of the clock.
- Stall logic should preserve state and keep data/control aligned.
- A stalled pipeline or control block should have a clear 'hold' rule.
- Enable conditions should be named when they protect protocol movement, for example `advance`, `load`, `accept_input`, or `accept_output`.

## 8. Do not improvise CDC by accident
- A reset crossing into another clock domain is not automatically safe.
- Clock-domain boundaries should be explicit in the architecture and review process.
- If the user did not ask for CDC handling, do not silently invent it.
- A two-flop synchronizer is a single-bit control pattern, not a general solution for multi-bit data.
- For multi-bit CDC, require a handshake, async FIFO, gray-coded pointer scheme, or another explicit reviewed pattern.

## 9. Ask for the missing reset contract when needed
Ask questions if any of these are unclear:
- synchronous or asynchronous reset
- polarity
- outputs during reset
- behavior on the first cycle after reset release
- whether clocks are shared across all logic
- whether the block must recover cleanly from mid-operation reset

## 10. What the skill should output
When clock/reset is relevant, the skill should always provide:
- reset style
- visible reset values
- first post-reset cycle behavior
- enable/stall behavior if present
- any reset-related corner cases that need verification

## Derived review checks

Flag these issues during review:

- derived clocks or ripple counters used as clocks without a clocking methodology,
- async reset deasserted directly into stateful logic without a synchronizer,
- reset values for state and valid-like outputs disagree,
- memory arrays reset in a way that prevents intended RAM inference,
- enable logic updates data but not the matching valid or sideband fields.
