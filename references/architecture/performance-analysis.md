# Performance Analysis for Hardware Design

## Purpose

RTL simulation tells you "does it work?" — performance analysis tells you "does it meet spec?" Every design has throughput, latency, and area targets. This document defines the core formulas and methods for analyzing whether your design meets them, before you write a single line of RTL.

**When to use:** Any L1/L2 design with throughput requirements, any pipeline, any multi-module system.

**Authority:** Hennessy & Patterson "Computer Architecture: A Quantitative Approach" §1.5-1.9 (performance metrics), ARM IHI 0022E §A5 (AXI throughput analysis), Little's Law (MIT, 1961 — applied to hardware queueing).

---

## 1. Throughput Calculation

### The Core Formula

```
Effective Throughput = Theoretical Max × Utilization × (1 - Overhead)
```

Where:
- `Theoretical Max` = bus_width × frequency / bits_per_item
- `Utilization` = fraction of cycles producing valid output
- `Overhead` = fraction of cycles lost to protocol overhead (headers, gaps, turnarounds)

### Example: NVMe SQ Fetch

```
Theoretical Max = 64 bits × 50 MHz / 512 bits_per_SQE = 6.25M SQE/sec
Utilization = 1/(8+3) = 1/11 ≈ 0.091  (8 R beats + ~3 cycles FSM overhead)
Overhead = 0 (raw AXI reads, no packet headers)
Effective = 6.25M × 0.091 × 1.0 ≈ 0.57M SQE/sec
```

Check: 1 SQE every 11 cycles at 50MHz = 50M/11 ≈ 4.5M. Hmm, the utilization should be 1/11 not 1/(8+3). Let me recalculate.

Actually, for an 8-beat AXI burst at 50MHz:
- 1 burst = 8 data beats + ~3 cycles address/response overhead
- Time for 1 SQE = 11 cycles at 50MHz = 11 × 20ns = 220ns
- Throughput = 1 SQE / 220ns = 4.55M SQE/sec

### Real Throughput with Backpressure

```
Throughput_actual = items_transferred / total_cycles
Throughput_actual ≤ 1 / max(producer_period, consumer_period)
```

If the consumer takes 512 cycles per item and the producer takes 11 cycles:
```
Throughput_actual = 1 / 512 items/cycle = 0.00195 items/cycle
```
The consumer is the bottleneck.

### Throughput Bottleneck Identification

1. **Compute** each module's standalone max throughput
2. **Find** the minimum (the bottleneck)
3. **Check** if any module's throughput drops further under backpressure (some modules slow down when downstream stalls)

```
Module A: 1 item/10 cycles = 0.100 items/cycle
Module B: 1 item/512 cycles = 0.002 items/cycle  ← BOTTLENECK
Module C: 1 item/4 cycles = 0.250 items/cycle
System throughput = min(0.100, 0.002, 0.250) = 0.002 items/cycle
```

---

## 2. Latency Budgeting

### Critical Path Decomposition

Break down the end-to-end latency into stages:

```
Total Latency = Input + Processing + Queueing + Output
```

| Stage | Components | Typical Range |
|-------|-----------|:---:|
| Input | Bus read, protocol decode, buffer write | 1-20 cycles |
| Processing | FSM traversal, computation, memory access | 1-10K cycles |
| Queueing | FIFO wait, arbitration, credit accumulation | 0-∞ (unbounded if deadlocked) |
| Output | Protocol encode, bus write, completion post | 1-20 cycles |

### Latency Budget Template

```
┌─────────────────────────────────────────────────────────┐
│ Component              │ Min │ Typ │ Max │ Blocking?   │
├────────────────────────┼─────┼─────┼─────┼─────────────┤
│ SQ fetch (8-beat AR)   │  8  │ 11  │ 11+N│ AR stall    │
│ Command parse          │  1  │  1  │  1  │ —           │
│ Admin exec (Identify)  │  3  │512  │512  │ DATA_XFER   │
│ CQ post (2-beat AW+W)  │  3  │  5  │  5  │ W stall     │
│ ─────────────────────  │     │     │     │             │
│ End-to-end (Identify)  │ 15  │529  │529+N│             │
└─────────────────────────────────────────────────────────┘
```

**N** = cycles waiting for AXI AR acceptance (bus contention)

### Where Latency Matters vs Doesn't

| Latency-critical | Latency-tolerant |
|-----------------|------------------|
| Read command → first data beat | Identify Controller (host waits 4KB) |
| Doorbell write → SQ fetch start | Queue creation (host expects ~ms) |
| CQE post → interrupt | Periodic status updates |
| Pipeline feedback path | Bulk data transfer |

---

## 3. Backpressure Propagation Analysis

### Propagation Delay

When a sink deasserts ready, how many cycles until the source stops sending?

```
Propagation_delay = number_of_pipeline_stages × (register_delay + wire_delay)
```

For a 3-stage feed-forward pipeline: delay = 3 × 1 = 3 cycles (if ready is registered at each stage).

Items in flight during backpressure propagation:
```
Items_in_flight = throughput × propagation_delay
```

### Deadlock Detection

**Construct the dependency graph:**
1. Each module is a node
2. Each FIFO/valid-ready link is a directed edge (data flow direction)
3. Each backpressure signal is a reverse edge

**A cycle in the graph = potential deadlock.**

```
Example: A → B → C → A (cycle!)
  A waits for B to accept → B waits for C → C waits for A
```

**To break the cycle:** Insert a buffer (FIFO) in any edge of the cycle:

```
A → [FIFO] → B → C → A
```
The FIFO absorbs items while waiting, preventing the circular stall.

### Backpressure Propagation Check (for any multi-module design)

1. List all valid→ready links between modules
2. For each downstream module, trace: "if this module deasserts ready, which modules upstream are affected?"
3. For each upstream module, verify: "can this module tolerate being stalled for the worst-case downstream stall duration?"

---

## 4. Utilization Analysis

### Module Utilization

```
Utilization = cycles_busy / total_cycles
```

| Utilization | Interpretation |
|:---:|------|
| >90% | Bottleneck — consider pipelining or parallel instances |
| 50-90% | Healthy — balanced design |
| <50% | Under-utilized — consider resource sharing or clock gating |
| <10% | Likely over-designed — candidate for area reduction |

### Bottleneck Visualization

```
Module   Utilization
──────   ───────────
SQ Fetch    ████░░░░░░░░  9%
Admin Exec  ████████████  100%  ← BOTTLENECK (512/512 cycles)
CQ Post     █░░░░░░░░░░░  1%
```

In NVMe Phase 1, Admin Exec is the bottleneck because Identify data transfer takes 512 cycles. The SQ Fetch (9%) and CQ Post (1%) are mostly idle. This is expected for a one-shot admin command — not a design flaw.

For sustained I/O (Phase 2), the bottleneck shifts to the data transfer engine.

---

## 5. Little's Law for Hardware

### Statement

```
L = λ × W
```

Where:
- `L` = average number of items in the system (buffer occupancy)
- `λ` = average arrival rate (items/cycle)
- `W` = average time an item spends in the system (cycles)

### Application: Buffer Sizing

```
FIFO_depth_needed = arrival_rate × max_processing_time
```

Example: NVMe I/O commands arrive at 1 cmd/100 cycles. Processing takes up to 500 cycles.
```
FIFO_depth = 1/100 × 500 = 5 commands (minimum)
Add margin: ×2 = 10 commands (safe)
```

### Application: Credit Sizing (NVMe SQ)

```
credits_max = queue_depth (host-side limit)
credits_needed = arrival_rate × round_trip_time
```

Round-trip time = time from host doorbell write to CQE post.
For NVMe: RTT ≈ SQ_fetch + processing + CQ_post ≈ 11 + 512 + 5 = 528 cycles.
With 1 command/528 cycles arrival rate: credits_needed = 1. Add margin for burst: 4.

---

## 6. Quick Performance Audit (before writing RTL)

For any module with throughput requirements, answer these 5 questions:

1. **Max throughput:** items/cycle = ? (compute from bus width, frequency, items/sec needed)
2. **Bottleneck:** Which stage takes the longest? (FSM traversal? Memory access? Data transfer?)
3. **Buffer depth:** For each rate mismatch, what FIFO depth prevents overflow?
4. **Deadlock risk:** Are there any cyclic dependencies in the backpressure graph?
5. **Utilization target:** Is any module expected to be >90% utilized in steady state?

### Example: NVMe Identify Controller (Phase 1)

| Question | Answer |
|----------|--------|
| Max throughput | 1 cmd / 529 cycles (bottleneck: Identify data xfer) |
| Bottleneck | Admin Exec DATA_XFER (512 cycles of 64-bit writes) |
| Buffer depth | SQ Fetch → Admin Exec: SKID (2) sufficient |
| Deadlock risk | cq_data_done pulse miss (fixed with level flag) |
| Utilization | Admin Exec: ~97% (512/529), others <10% |

### Example: Hypothetical NVMe Phase 2 (NVM Read, 4KB page)

| Question | Answer |
|----------|--------|
| Max throughput | 1 cmd / ~260 cycles (data xfer = 4096B / 64b/beat = 512 cycles, plus PRP walk) |
| Bottleneck | AXI read channel (memory bandwidth limited) |
| Buffer depth | Data buffer: bandwidth×latency = 1×512 = 512 entries minimum |
| Deadlock risk | Yes: data buffer full → cannot complete reads → cannot drain buffer. Fix: credit-based flow control on read commands. |
| Utilization | Data engine ~80%, others <20% |

---

## Design Checklist (add to Step 5a P2 review)

For any design with performance requirements:
1. **Throughput calculation:** Compute max theoretical and expected effective throughput. Show the bottleneck.
2. **Latency budget:** Fill the latency table. Mark blocking vs non-blocking stages.
3. **Backpressure graph:** Draw the valid/ready connection graph. Tag each link with direction and latency.
4. **Buffer sizing:** Apply Little's Law: `depth = arrival_rate × max_processing_time`. Show your math.
5. **Utilization projection:** Project steady-state utilization for each module. Flag any module expected to be >90%.
