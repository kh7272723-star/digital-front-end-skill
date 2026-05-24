# Formal Verification Guidelines

## Purpose

This file covers formal verification concepts for RTL engineers. Use when the task involves property checking, formal proofs, or assertions beyond basic SVA.

Sources: IEEE 1800-2017 SystemVerilog Standard (SVA sections), Synopsys VC Formal User Guide, Cadence JasperGold User Guide, "SystemVerilog Assertions Handbook" (Ben Cohen).

## Formal vs simulation

| Aspect | Simulation | Formal |
|--------|-----------|--------|
| Stimulus | User-defined or random | Exhaustive (all possible inputs) |
| Coverage | Depends on tests | Proves property holds for all cases |
| Scalability | Scales with compute | Scales with design complexity (state space) |
| Best for | Dataflow, integration | Control logic, protocols, corner cases |

## When to use formal

- **Deadlock freedom**: prove no state where all outputs are blocked
- **Safety properties**: something bad never happens
- **Liveness properties**: something good eventually happens
- **Protocol compliance**: all sequences follow the spec
- **Equivalence**: two implementations are functionally identical

## SVA for formal

### Basic properties

```systemverilog
// Safety: valid must not deassert while ready is low (hold until consumed)
property hold_until_consumed;
  @(posedge clk) (valid_o && !ready_i) |-> (valid_o until ready_i);
endproperty

// Liveness: if valid asserted, eventually ready will come
property eventually_ready;
  @(posedge clk) valid_o |-> (##[0:$] ready_i);
endproperty

// Deadlock: at least one output can always make progress
property no_deadlock;
  @(posedge clk) 1'b1 |-> (valid_o || ready_o);
endproperty
```

### Formal-specific patterns

```systemverilog
// Cover: prove a state is reachable
cover property (@(posedge clk) state == ERROR);

// Assume: constrain inputs for formal engine
assume property (@(posedge clk) valid_i |-> !$isunknown(data_i));

// Assert: prove property holds for all inputs
assert property (@(posedge clk) cnt != MAX || !incr);
```

## Formal verification flow

1. **Define properties** — what must be true (safety) or eventually true (liveness)
2. **Add constraints** — restrict input space to legal behavior
3. **Run proof** — tool tries to find counterexample or prove property
4. **Analyze results**:
   - **Proven**: property holds for all reachable states
   - **Counterexample (CEX)**: tool found a trace that violates property
   - **Bounded proof (BMC)**: property holds for N cycles but not proven unbounded
   - **Inconclusive**: state space too large, needs abstraction

## Abstraction techniques

- **Blackboxing**: replace complex submodules with their interface contracts
- **Cutpoints**: break combinational loops or deep logic
- **Over-approximation**: relax constraints to make proof feasible
- **Under-approximation**: tighten constraints for faster but bounded proofs

## Formal for protocol checking

AXI, AHB, APB protocols have well-defined formal properties:

```systemverilog
// AXI: valid must remain stable until ready
property axi_valid_stable;
  @(posedge clk) (awvalid && !awready) |-> (##1 awvalid);
endproperty

// AXI: handshake completion
property axi_handshake;
  @(posedge clk) awvalid && awready |-> (##1 !awvalid || !awready || new_transfer);
endproperty
```

## Limitations of formal

- State space explosion: large memories, wide counters, many FSMs
- Cannot handle analog or mixed-signal behavior
- Requires good constraints (over-constrained = false proof, under-constrained = false CEX)
- Does not replace timing or power analysis

## Formal vs assertions in simulation

- SVA assertions can run in both simulation and formal
- Simulation assertions check only exercised scenarios
- Formal assertions check all reachable scenarios
- Use both: simulation for quick feedback, formal for exhaustive proof

## Common mistakes

1. Writing assertions that are too weak (pass trivially)
2. Not constraining inputs (formal engine explores illegal states)
3. Expecting formal to handle large data paths (use simulation instead)
4. Ignoring BMC depth (short BMC does not prove unbounded safety)
5. Over-using formal (simple modules do not need it)
