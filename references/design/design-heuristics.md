# Design Heuristics and Engineering Intuition

## Purpose

This file captures rules of thumb, sizing guidelines, and design intuition that experienced engineers use. These are heuristics, not hard rules — use judgment.

Sources: accumulated engineering practice from ARM, Intel, NVIDIA RTL design teams; "Reuse Methodology Manual" (Keating & Bricaud); "RTL Modeling for System Design" (Rishe).

## FIFO depth sizing

### Rule of thumb

```
FIFO_depth = latency_cycles * throughput_ratio + safety_margin
```

Where:
- `latency_cycles`: how long the consumer can be busy before it accepts data
- `throughput_ratio`: producer rate / consumer rate
- `safety_margin`: 2-4 entries for pipeline latency and backpressure propagation

### Common scenarios

| Scenario | Depth | Rationale |
|----------|-------|-----------|
| Clock domain crossing | 8-16 | Covers async latency + gray code delay |
| Pipeline stage buffer | 2-4 | One entry per pipeline stage |
| DMA read data buffer | 16-32 | Covers AXI burst latency |
| Network packet buffer | 64-256 | Covers variable-length packets |
| CPU write buffer | 4-8 | Covers store queue depth |

### When FIFO is too shallow

- Downstream stalls propagate back to upstream (throughput collapse)
- Data loss on overflow (if no backpressure)
- Deadlock if producer and consumer wait on each other

### When FIFO is too deep

- Unnecessary area (each entry is a register or RAM word)
- Increased latency (deeper FIFO = more pointer comparison logic)
- Harder to meet timing on read/write paths

## Pipeline stage count

### Rule of thumb

```
stages = ceil(critical_path_delay / target_period)
```

Where:
- `critical_path_delay`: longest combinational path in the design
- `target_period`: 1 / target_frequency

### Common scenarios

| Scenario | Stages | Rationale |
|----------|--------|-----------|
| Simple register slice | 1 | One-cycle latency, full throughput |
| Skid buffer | 2 | Handles downstream deassert with one-cycle notice |
| Arithmetic pipeline | 2-4 | Depends on operation complexity |
| Memory access pipeline | 2-3 | Address decode + memory read + output register |
| Protocol bridge | 2-4 | Clock domain + protocol conversion |

### Pipeline hazards

- **Data hazard**: later stage depends on earlier stage result (need bypass or stall)
- **Control hazard**: branch/stall affects pipeline flow (need flush or bubble)
- **Structural hazard**: resource conflict between stages (need arbitration)

## Arbiter design choices

### Fixed priority vs round-robin

| Criterion | Fixed priority | Round-robin |
|-----------|---------------|-------------|
| Latency | Low for high-priority | Predictable |
| Fairness | Starvation possible | Fair |
| Complexity | Simple | Moderate |
| Use when | Clear priority (control vs data) | Equal priority (peer requesters) |

### Priority encoding

- Use `casez` for priority encoding (synthesizes to priority mux)
- Use `onehot` for fast arbitration (one-hot grant)
- Avoid nested `if-else` for more than 4 requesters (timing issues)

### Grant hold under backpressure

- Must hold grant until transfer completes (valid && ready)
- Re-arbitrating during backpressure causes data misrouting
- Exception: round-robin with grant-on-transfer (re-arbitrate on each accepted transfer)

## Counter sizing

### Rule of thumb

```
counter_bits = ceil(log2(max_count + 1))
```

### Common scenarios

| Counter purpose | Bits | Max value |
|-----------------|------|-----------|
| FIFO occupancy (depth 16) | 5 | 16 (with wrap bit) |
| Burst beat counter (AXI) | 4 | 256 (AXI max burst) |
| Timeout counter | 16-32 | Application-dependent |
| Cycle counter | 32-64 | Free-running |

### Off-by-one prevention

- Always check: does the counter count from 0 to N-1, or 1 to N?
- Use `count == MAX` for terminal condition, not `count > MAX`
- Test boundary: counter at MAX-1, MAX, and wrap-around

## State machine design

### Two-process vs one-process

| Style | Pros | Cons | When to use |
|-------|------|------|-------------|
| One-process (single always block) | Simple, no next-state logic | Hard to read for complex FSM | 3-5 states, simple transitions |
| Two-process (separate comb/seq) | Clear separation, easier debug | More code, must keep in sync | 5+ states, complex transitions |

### State encoding

| Encoding | Pros | Cons | When to use |
|----------|------|------|-------------|
| Binary | Fewer FFs | Slow decode | Area-constrained, few states |
| One-hot | Fast decode, easy debug | More FFs | Speed-critical, <32 states |
| Gray | Single-bit transitions | Complex logic | CDC state machines |

### Illegal state recovery

- Always include a `default` branch that returns to a known state
- For one-hot: check `$onehot(state)` and recover if violated
- Log illegal states in simulation for debug

## Handshake design

### Ready/valid rules

1. **Valid** is driven by the producer, independent of ready
2. **Ready** is driven by the consumer, independent of valid
3. Transfer happens only when both valid AND ready are high
4. Valid must hold until ready (producer cannot withdraw data)
5. Ready can change at any time (consumer can backpressure freely)

### Ready path design

- **Combinational ready**: `ready_o = !valid_o || ready_i` (zero-latency, but combinational path)
- **Registered ready**: `ready_o <= !valid_o || ready_i` (one-cycle latency, breaks combinational path)
- Choose based on timing requirements

### Accept conditions

Always define explicit accept conditions:
```verilog
wire accept_input  = valid_i && ready_o;
wire accept_output = valid_o && ready_i;
```

## Area estimation

### Rule of thumb (28nm)

| Component | Area estimate |
|-----------|--------------|
| Flip-flop | ~1.5 µm² |
| 32-bit adder | ~200 µm² |
| 32-bit multiplier | ~2000 µm² |
| 32x32 register file | ~3000 µm² |
| 1KB SRAM | ~5000 µm² |

### Area reduction techniques

1. Resource sharing (time-multiplex hardware)
2. Memory instead of registers (for large storage)
3. Smaller data widths where possible
4. Clock gating (reduces power, not area directly)

## Timing estimation

### Rule of thumb

| Logic | Delay (28nm, typical) |
|-------|----------------------|
| 2-input gate | ~30 ps |
| 32-bit adder | ~300 ps |
| 32-bit mux (4:1) | ~150 ps |
| Register (ck-to-q) | ~100 ps |
| Wire (1mm) | ~50-200 ps |

### Critical path identification

- Look for deep combinational chains (5+ logic levels)
- Wide muxes with registered outputs
- Arithmetic operations without pipelining
- Cross-hierarchy paths (long wires)

## Red flags in RTL review

### Immediate red flags

| Pattern | Risk | Action |
|---------|------|--------|
| `always @(*)` without default | Latch inference | Add defaults |
| Mixed blocking/nonblocking | Simulation/synthesis mismatch | Separate blocks |
| `assign` to reg | Simulation/synthesis mismatch | Use wire |
| Gated clock in RTL | CDC risk, test issues | Use enable |
| No reset on state register | Unknown initial state | Add reset |
| Combinational feedback | Unstable logic | Break the loop |

### Protocol red flags

| Pattern | Risk | Action |
|---------|------|--------|
| Valid deasserted mid-transfer | Data loss | Hold valid until ready |
| Ready depends on valid | Combinational loop | Register ready |
| Multi-bit CDC with flops | Transient values | Use gray/handshake |
| Completion on data beat, not response | Premature completion | Wait for response |
| No error handling | Silent corruption | Add error path |

### Performance red flags

| Pattern | Risk | Action |
|---------|------|--------|
| Single-entry FIFO | No throughput benefit | Use register slice |
| Deeply nested if-else | Timing violation | Use case or pipeline |
| Large combinational loop | Timing violation | Pipeline or multi-cycle |
| Cross-hierarchy combinational | Routing congestion | Register at boundary |

## Design review checklist (intuitive)

### Before writing code

- [ ] Do I know what the module does in one sentence?
- [ ] Do I know the input/output timing?
- [ ] Do I know the reset behavior?
- [ ] Do I know the boundary conditions?
- [ ] Have I identified the critical path?

### After writing code

- [ ] Can I trace the logic cycle by cycle?
- [ ] Are all state elements reset?
- [ ] Are all combinational blocks fully assigned?
- [ ] Are accept conditions explicit?
- [ ] Does the design handle backpressure correctly?

### Before claiming done

- [ ] Does it pass simulation?
- [ ] Does it pass lint?
- [ ] Are assertions checking the contract?
- [ ] Are boundary conditions tested?
- [ ] Is the code readable by someone else?
