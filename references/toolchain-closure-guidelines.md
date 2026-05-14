# Toolchain closure guidelines

## Purpose

Use this file to avoid overstating confidence.
Directed simulation is only the first tool gate.

## Tool gates

- Syntax/elaboration: code can compile with the selected simulator.
- Lint: style and structural issues are checked by project lint rules.
- Directed simulation: key scenarios produce pass/fail results.
- Assertion or monitor checks: protocol and timing invariants are protected.
- Coverage: important states, boundaries, and transitions are exercised.
- CDC review: all clock-domain crossings use approved patterns.
- Synthesis check: intended memories, registers, and enables infer as expected.
- Timing review: long combinational paths, ready chains, and wide comparisons are identified.
- Formal: local invariants are proven when the block is small enough and properties are available.

## Reporting rule

State exactly which gates were run and which remain.
Never call a block signoff-ready if lint, CDC, synthesis, timing, or coverage have not been addressed by the project flow.

## Available local tool policy

Use installed tools when available.
If only Icarus Verilog is available, report syntax and directed simulation evidence only.
If Verilator, Yosys, or SymbiYosys are unavailable, do not pretend those checks were run.

## Common closure risks

- Long combinational ready path across several modules.
- RAM style blocked by reset or mixed read/write coding.
- Async reset deassertion not synchronized.
- Outstanding counters missing overflow or underflow protection.
- Assertions check safety but not liveness.
