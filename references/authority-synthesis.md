# Authority synthesis for digital front-end RTL

## Purpose

This file explains how to turn authoritative design material into useful skill behavior.
The agent should not perform a literature review during normal RTL work. It should use distilled rules that preserve the timing and verification consequences of the source material.

## Source hierarchy

Use sources in this order:

1. User-provided project specification, interface definition, coding standard, waveform, log, or lint output.
2. Verilog/SystemVerilog language semantics for event scheduling, blocking/nonblocking assignment behavior, and synthesizable constructs.
3. Tool and vendor methodology guidance for synthesis, reset, CDC, lint, timing closure, and simulation.
4. Established synchronous design practice for state machines, FIFOs, pipelines, arbiters, counters, and handshakes.
5. This skill's curated local examples.

If sources conflict, preserve the user's project requirements first and state the conflict.

## Consulted source map

This reference set is distilled from the following authority classes. Do not require the agent to revisit them for every task; use the rules below as the working standard.

| Source class | Examples consulted | What the skill extracts |
| --- | --- | --- |
| Language standard | IEEE 1800 SystemVerilog standard pages and public standard access notes | event semantics, RTL/testbench/assertion language scope, blocking/nonblocking meaning |
| Assignment methodology | Cliff Cummings, "Nonblocking Assignments in Verilog Synthesis, Coding Styles That Kill" | sequential uses nonblocking, combinational uses blocking, avoid mixed assignment races |
| FSM methodology | Cliff Cummings, "Coding And Scripting Techniques For FSM Designs With Synthesis-Optimized, Glitch-Free Outputs" | separate state register and decode, prefer registered outputs when glitch freedom matters |
| Public RTL style guide | lowRISC SystemVerilog/Verilog coding style guide | readable RTL structure, `always_ff`/`always_comb` preference, width discipline, FSM two-process style |
| FPGA synthesis guidance | Intel/Altera Quartus design recommendations and AMD Vivado synthesis guide | avoid unintended latches, combinational loops, delay chains, ripple counters, ambiguous RAM inference |
| Timing/CDC methodology | Intel/Altera metastability and AMD UltraFast methodology guidance | explicit synchronizers, validation stages, CDC constraints, reset/clock discipline |
| Ready/valid protocol guidance | Arm AMBA/AXI family references and AMD AXI ready/valid/protocol-check documentation | transfer occurs on ready+valid edge; valid and payload stay stable until handshake |

## Distilled internal design standard

Use these rules directly when writing or reviewing RTL.

### 1. Clocked state

- Put registers in one clearly clocked process per synchronous region.
- Use nonblocking assignments for clocked state.
- The right-hand side of a clocked assignment is the pre-edge value; the assigned value is visible after the edge.
- Do not place complex decode in a sequential block when a simple next-state/next-data combinational block would make timing clearer.
- Do not assign the same register in multiple unrelated branches unless priority is explicit.

### 2. Combinational logic

- Use continuous assignments or a single combinational block with blocking assignments.
- Assign defaults before conditional branches.
- Cover every branch that drives an output or next-state signal.
- Avoid inferred latches, combinational loops, delay chains, and on-chip tri-state constructs.
- Avoid using multi-bit vectors as implicit booleans; compare explicitly to zero or to a named value.

### 3. Reset and enable

- State reset polarity and whether reset is synchronous or asynchronous.
- Define visible reset values for state and protocol outputs, especially valid-like signals.
- Prefer clock enables over generated/gated clocks unless the project has a clock-gating cell and methodology.
- If an asynchronous reset is used, define and verify deassertion synchronization per clock domain.
- Define the first active cycle after reset release.

### 4. Protocol movement

- Name every movement condition once: `accept_input`, `accept_output`, `wr_do`, `rd_do`, `advance`, or `load`.
- A ready/valid transfer occurs only on a clock edge where both ready and valid are asserted.
- Once valid is asserted, hold valid and associated payload/sideband stable until the transfer completes.
- Do not let stalls advance data without the matching valid/control fields.
- Avoid combinational ready loops unless the architecture explicitly requires and verifies them.

### 5. FIFO and memory inference

- Define whether the FIFO accepts writes on full+read and reads on empty+write cycles.
- Define whether read data is registered, combinational, first-word fall-through, old-data, or new-data behavior.
- Derive full/empty from one occupancy or pointer contract.
- Keep memory access conditions identical to the FIFO write/read contract.
- If RAM read-during-write behavior matters, state the expected behavior and choose a coding style that infers it.

### 6. FSM structure

- List legal states, reset state, transition conditions, and output behavior before coding.
- Prefer a two-process FSM: one combinational decode block and one clocked state block.
- Use registered outputs when glitches or timing closure matter.
- Give combinational outputs defaults before the state `case`.
- Add illegal-state recovery only when it matches the safety and debug policy.

### 7. Verification minimum

- Every nontrivial RTL answer should include syntax/lint expectations, directed tests, and one contract-protecting check.
- For ready/valid, check payload stability while stalled and no lost/duplicated transfers.
- For FIFO, check full, empty, simultaneous write/read, overflow attempt, and underflow attempt.
- For FSM, check reset state, each transition, and stuck-state escape or intentional wait behavior.
- For CDC, require a named synchronizer or handshake pattern and a CDC review step.

## Conversion method

For each useful source idea, convert it into four artifacts:

- Rule: a compact instruction the agent can follow.
- Timing consequence: what changes in the current cycle, at the clock edge, or on the next cycle.
- RTL consequence: the code structure that makes the rule visible.
- Verification consequence: the directed test, assertion, or waveform checkpoint that catches violations.

Example:

- Source idea: registered state updates are observed after the active clock edge.
- Rule: describe register updates as next-cycle visible, not as immediate intra-cycle changes.
- RTL consequence: use edge-triggered sequential blocks for state and nonblocking assignments for register updates.
- Verification consequence: check outputs at the cycle where the registered value should be visible.

## Rule quality checklist

A good internal rule:

- changes an RTL or verification decision,
- is short enough to apply while coding,
- names the affected signals or protocol condition when possible,
- explains the cycle-level consequence,
- avoids vague phrases such as "clean", "safe", or "robust" without a measurable condition,
- is backed by an example or a test idea.

A weak internal rule:

- quotes a standard without saying what code should do,
- gives style preferences without timing or verification impact,
- hides an assumption about reset, latency, or backpressure,
- is too broad to check in simulation.

## Standard rule families

### Assignment and event semantics

- Use nonblocking assignments for registered state.
- Use blocking assignments for local combinational calculations.
- Do not mix assignment styles in a way that obscures update order.
- Explain whether a value is pre-edge, post-edge, or next-cycle visible.

### Reset and initialization

- State reset polarity, synchrony, and visible output values.
- Clear valid-like protocol signals unless the contract says otherwise.
- Define the first active cycle after reset release.
- Verify reset values and first post-reset behavior.

### Handshake and flow control

- Name every transfer condition once, usually `accept_input`, `accept_output`, `wr_do`, `rd_do`, or `advance`.
- Hold payload and sideband fields stable while valid is asserted and the receiver is not ready.
- Define simultaneous boundary events, such as write+read at full or empty.
- Avoid combinational ready loops unless the contract explicitly allows and verifies them.

### State machines

- List legal states, reset state, and transition conditions before coding.
- Give outputs defaults in combinational logic.
- Define illegal-state recovery only if it matches the project safety policy.
- Verify each meaningful transition, not only the happy path.

### FIFOs and pipelines

- Use one source of truth for occupancy or stage validity.
- Keep data, valid, and sideband fields aligned through stall and flush.
- Define whether read data is registered or combinational.
- Test full, empty, simultaneous write/read, stall, flush, and reset boundaries as applicable.

### CDC and multi-clock logic

- Do not infer CDC safety from local synchronous behavior.
- Treat single-bit, multi-bit, pulse, and data-bus crossings as different problems.
- Require an explicit CDC pattern, clock relationship, reset strategy, and review expectation.
- Prefer asking for constraints over generating a guessed crossing.

## When to cite sources

Most RTL answers should cite the contract and the local pattern, not a long list of documents.
If the user asks why a rule exists, explain the rule in terms of language semantics, synthesis behavior, or verification observability.
If exact source names or versions matter, verify them before naming them.
