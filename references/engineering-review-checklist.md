# Engineering review checklist

## Purpose

Use this file to move from "works in a simple test" toward experienced RTL engineering review.
The agent should use this checklist before finalizing nontrivial RTL or subsystem architecture.

## Design maturity levels

- Sketch: behavior is plausible, but contracts and checks are incomplete.
- Reviewable RTL: contract, cycle trace, RTL, and directed checks exist.
- Integration-ready RTL: interfaces, reset, error, backpressure, and invariants are checked.
- Signoff candidate: lint, CDC, simulation, formal or coverage, synthesis, and timing risks are addressed by project tools.

Do not imply signoff-level correctness when only a sketch or directed simulation exists.

## Review dimensions

### Functional contract

- Are accepted inputs, visible outputs, and completion events defined?
- Are illegal requests ignored, flagged, blocked, or unsupported?
- Is every output driven by one owner?
- Are reset, flush, and error paths consistent with normal operation?

### Timing and microarchitecture

- Are registered state and combinational decisions separated clearly?
- Is the critical path likely to include wide compares, long ready chains, RAM output decode, or arbitration priority logic?
- Are data, valid, sideband, address, byte enable, ID, and error fields aligned?
- Does the design state which RAM behavior is required?

### Backpressure and liveness

- Can every stall be relieved by a state transition?
- Can ready/valid combinational paths form a loop?
- Is there enough buffering for independently stalled channels?
- Can an outstanding counter or queue saturate and block its own drain?

### Tool and implementation risks

- Could the code infer latches, distributed RAM instead of block RAM, or unintended registers?
- Does reset style prevent desired memory inference?
- Are generated clocks, ripple counters, or gated clocks avoided unless project methodology allows them?
- Are widths explicit enough to avoid truncation or accidental signed behavior?

### Verification readiness

- Is there a directed test for reset, normal operation, boundary, stall, and error?
- Is there a pass/fail signal, not just waveform stimulus?
- Are scoreboards or monitors used when ordering matters?
- Is the first failing cycle identifiable from logs or checks?

## Final review output

For nontrivial work, include:

- maturity level,
- top three residual risks,
- checks already covered,
- checks still needed before integration,
- smallest next step.
