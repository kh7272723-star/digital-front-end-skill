# Synthesis guidance

## Purpose

Use this file to flag RTL constructs that can synthesize into unexpected area, timing, memory, or DSP structures.
Project vendor guidance overrides these generic rules.

## Core inference rules

- `always @(posedge clk_i)` infers flip-flops.
- Complete `always @(*)` logic infers combinational gates; incomplete assignment infers latches.
- Large memories infer RAM only when the read/write style matches the target technology.
- Large arithmetic infers adders, multipliers, or DSPs; pipeline requirements depend on width and clock target.
- Loops in combinational logic unroll into hardware; they do not become sequential unless coded with state.

## Common surprises

- Combinational loop with many iterations creates a long combinational chain.
- Resetting a large memory array can prevent RAM inference.
- Combinational read from a large array can prevent block RAM inference on many FPGA flows.
- Deep priority chains create long mux paths.
- `integer` in synthesizable state becomes a 32-bit signed register unless constrained.
- Wide ready logic across module boundaries can dominate timing.

## Synthesis notes to include

For nontrivial generated RTL, add concise notes covering:

- expected flops, RAMs, DSPs, or wide combinational structures,
- latch, RAM-inference, or loop-unroll risks,
- likely long paths such as ready chains, comparators, or priority encoders,
- attributes or pragmas that may be needed by the project flow.

Do not claim timing closure without synthesis and STA results.
