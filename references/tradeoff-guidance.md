# Tradeoff guidance

## Purpose

Experienced RTL engineers explain why they choose an architecture.
Use this file when there are multiple plausible implementations.

## Common tradeoffs

### Register slice vs skid buffer

- Register slice: simpler, predictable one-cycle storage, but can reduce throughput if not designed for replacement.
- Skid buffer: better backpressure tolerance, more state and verification burden.
- Choose skid buffer when upstream cannot stop immediately or throughput under one-cycle stall matters.

### Occupancy FIFO vs pointer-only FIFO

- Occupancy FIFO: full/empty and count are easy to reason about; count update must be correct at boundaries.
- Pointer-only FIFO: can be compact but boundary interpretation is easier to get wrong.
- Choose occupancy for first-pass readable RTL unless project area or timing constraints require another style.

### Combinational ready vs registered ready

- Combinational ready can improve throughput and reduce bubbles.
- It can also create long paths or loops across module boundaries.
- Use registered ready or buffering when integration timing is uncertain.

### Registered outputs vs combinational outputs

- Registered outputs improve timing isolation and glitch behavior.
- Combinational outputs can reduce latency but expose downstream timing to current-state decode.
- Choose registered outputs for cross-module control unless the latency contract requires combinational behavior.

### Full-featured block vs staged feature set

- A full implementation may hide missing contracts and verification holes.
- A staged implementation reveals interface and invariant problems earlier.
- For large systems, implement minimum useful feature first, then add stalls, errors, outstanding work, and recovery.

## Output format

When a tradeoff matters, state:

- options considered,
- chosen option,
- reason,
- cost,
- verification implication.
