# Timing semantics for digital front-end work

## Source policy

Use this file only as a curated synthesis of authoritative sources.
Prefer vendor manuals, IEEE standards, and established methodology guides over ad hoc blog-style habits.
When exact standard versions matter, verify the version before naming it in user-facing output.

## Authoritative source classes to anchor on

- IEEE SystemVerilog language standard and Verilog semantics references
- Vendor synthesis and simulation user guides from major EDA vendors
- CDC and reset methodology guides from established FPGA/ASIC vendors
- Well-known RTL coding guideline documents used in industry flows
- Standard digital design textbooks for synchronous design, FSMs, pipelines, and handshakes

## Core timing rules

### 1. Separate combinational intent from registered state

- Combinational logic describes what is true in the current cycle.
- Sequential logic captures state that becomes visible on the next active clock edge.
- Never rely on implied storage in combinational blocks.
- In explanations, name whether a signal is an input condition, combinational result, registered state, or next-cycle output.

### 2. State updates happen on clock edges

- A value assigned in an edge-triggered block is not observable as the new value until after the triggering edge.
- When explaining behavior, always say whether the signal is pre-edge, post-edge, or next-cycle visible.

### 3. Nonblocking assignments model registered behavior

- Use nonblocking assignments for sequential state.
- Use blocking assignments only where the intended semantics are purely combinational and local.
- Avoid mixing update styles in a way that obscures cycle behavior.
- If two registers update on the same edge with nonblocking assignments, explain that each right-hand side observes the pre-edge value.

### 4. Handshake validity must be explicit

- For ready/valid style protocols, valid indicates data is available and stable until accepted.
- Ready indicates acceptance capacity for the current cycle.
- A transfer occurs only when both are asserted in the same cycle.
- If backpressure can occur, describe exactly how data is held and when it is released.

### 5. Reset behavior must be defined at the cycle level

- State whether reset is synchronous or asynchronous.
- State what outputs are forced during reset.
- State what the first active cycle after reset deassertion should do.
- Avoid vague phrases like "comes up clean" without cycle-by-cycle meaning.

### 6. Pipelines need data/control alignment

- Every registered stage must preserve alignment between data, valid, sideband fields, and control.
- If stalls or flushes exist, state how each field moves or holds.
- Check for off-by-one bugs whenever latency changes.

### 7. FSMs need explicit legal-state behavior

- List all legal states.
- Specify the reset state.
- Define what happens on illegal or unrecognized state encodings if relevant.
- Keep output behavior tied to a clear state/output table.

### 8. FIFO behavior must be defined on boundary cycles

- Define full, empty, almost-full, and almost-empty only if they are truly required.
- Specify simultaneous write/read behavior.
- Define whether reads from empty or writes to full are ignored, flagged, or prevented by protocol.
- Use a clear occupancy model so pointer arithmetic stays unambiguous.

### 9. CDC logic must not be improvised

- Use established synchronization patterns for single-bit crossings.
- Treat multi-bit crossings with stronger structure than a simple two-flop chain.
- Never infer that a local handshake is safe across clock domains without explicit CDC review.

## Timing explanation obligations

For stateful RTL, the agent should make these distinctions explicit:

- `pre-edge`: values sampled by sequential logic on the active edge.
- `edge update`: register assignments scheduled by the sequential block.
- `post-edge/next-cycle visible`: values downstream logic can observe after the edge.
- `same-cycle combinational`: values derived without waiting for another clock edge.

Avoid phrases like "immediately updates" unless the signal is purely combinational.
For registers, say "captured on this edge and visible after the edge" or "visible next cycle".

## Cycle-by-cycle explanation template

When explaining a circuit, answer in this order:

1. What is already registered at the start of the cycle?
2. What combinational conditions are evaluated during the cycle?
3. Which events happen on the active edge?
4. What becomes visible on the next cycle?
5. What corner case changes the above behavior?

## Common failure patterns to watch for

- valid rises before data is stable
- ready is deasserted too late to prevent overflow
- reset release leaves state and outputs inconsistent for one cycle
- pipeline stage drops a bubble or duplicates data
- FSM leaves an implicit transition unspecified
- combinational defaults are incomplete and imply latch behavior
- CDC signal is sampled without synchronization discipline

## Preferred reasoning posture

- Prefer conservative, standard semantics over clever shortcuts.
- If a behavior is not specified by the request, ask instead of guessing.
- When in doubt, validate with simulation and assertions rather than textual confidence.
