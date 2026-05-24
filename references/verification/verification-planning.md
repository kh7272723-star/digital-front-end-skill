# Verification Planning Guidelines

## Purpose

This file provides a structured approach to verification planning that goes beyond directed tests. Use when planning verification for any nontrivial RTL module or subsystem.

Sources: "Writing Testbenches: Functional Verification of HDL Models" (Janick Bergeron), "SystemVerilog for Verification" (Chris Spear), UVM User Guide (Accellera).

## Verification maturity levels

| Level | Method | Coverage | When sufficient |
|-------|--------|----------|-----------------|
| L0 | Smoke test (one happy path) | None | Bring-up only |
| L1 | Directed tests | None | Simple leaf modules |
| L2 | Directed + assertions | Assertion coverage | Register slices, counters |
| L3 | Constrained-random + coverage | Functional coverage | FIFOs, arbiters, adapters |
| L4 | L3 + formal properties | Proof coverage | Protocol blocks, control logic |
| L5 | L4 + UVM environment | Full coverage closure | Subsystems, IP blocks |

Most RTL work needs L2-L3. L4-L5 for protocol-critical or safety-critical paths.

## Verification plan template

For each module, define:

```
## Verification Plan: [module_name]

### Scope
- What is verified: [list features]
- What is NOT verified: [list exclusions with rationale]

### Stimulus strategy
- Directed: [list specific scenarios]
- Constrained-random: [what randomizes, constraints]
- Corner cases: [list boundary conditions]

### Checking strategy
- Self-checking: [pass/fail in testbench]
- Assertions: [SVA properties]
- Scoreboard: [reference model comparison]
- Formal: [properties to prove]

### Coverage model
- Functional coverage: [bins and crosses]
- Code coverage: [tool-generated, not specified here]
- Assertion coverage: [which properties must be hit]

### Entry criteria
- [ ] All directed tests pass
- [ ] Functional coverage > 90%
- [ ] All assertions pass
- [ ] No known bugs open

### Exit criteria
- [ ] All entry criteria met
- [ ] Formal properties proven (if L4+)
- [ ] Review complete
```

## Directed test design

Each directed test should:
1. Have a clear purpose (what scenario it tests)
2. Have a pass/fail criterion (not just "no error")
3. Be reproducible (fixed seed or deterministic stimulus)
4. Be minimal (test one thing, not everything)

### Directed test categories

| Category | Purpose | Example |
|----------|---------|---------|
| Reset | Verify initial state | Reset, check all outputs |
| Happy path | Normal operation | One complete transfer |
| Boundary | Edge conditions | Full FIFO, empty FIFO, max counter |
| Backpressure | Stall handling | Deassert ready mid-transfer |
| Error | Error injection | Invalid input, protocol violation |
| Timing | Timing-sensitive cases | Simultaneous events, minimum interval |

## Constrained-random strategy

### What to randomize

- Transaction content (address, data, length)
- Timing (delays between transactions, backpressure patterns)
- Ordering (sequence of operations)
- Configuration (parameters, modes)

### Constraints to define

```systemverilog
class my_transaction extends uvm_sequence_item;
  rand bit [31:0] addr;
  rand bit [31:0] data;
  rand bit [7:0]  length;
  rand bit        write;

  // Realistic constraints
  constraint c_aligned { addr[1:0] == 2'b00; }
  constraint c_length { length inside {[1:16]}; }
  constraint c_dist { write dist {1 := 70, 0 := 30}; }
endclass
```

### Coverage-driven closure

1. Define coverage model BEFORE writing tests
2. Run constrained-random, collect coverage
3. Analyze holes (bins not hit)
4. Write targeted sequences for hard-to-hit bins
5. Repeat until coverage closure

## Assertion categories

| Category | Purpose | Example |
|----------|---------|---------|
| Safety | Something bad never happens | No simultaneous grants |
| Liveness | Something good eventually happens | Eventually ready |
| Stability | Values hold under conditions | Data stable while valid && !ready |
| Protocol | Interface rules followed | Handshake completion |
| Deadlock | System can always progress | At least one output active |

## Verification matrix

For complex modules, use a matrix:

| Scenario | Stimulus | Expected | Checker | Coverage | Priority |
|----------|----------|----------|---------|----------|----------|
| Reset | Assert reset | All outputs default | Check outputs | Reset hit | P0 |
| Normal transfer | Valid + data | Data forwarded | Scoreboard | Transfer hit | P0 |
| Full + write | Fill FIFO, write | Write rejected | Full flag | Full hit | P1 |
| Empty + read | Empty FIFO, read | Read rejected | Empty flag | Empty hit | P1 |
| Simultaneous | Read + write same cycle | Correct count | Counter check | Simul hit | P2 |

## Common verification mistakes

1. Writing tests without a coverage model (random without purpose)
2. Checking only happy paths (ignoring boundary and error)
3. No scoreboard (stimulus without checking is useless)
4. Stopping at 50% coverage ("good enough" is not closure)
5. Not verifying reset behavior (most bugs are post-reset)
6. Ignoring assertion vacuity (assertions that pass trivially)
