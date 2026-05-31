# Memory Hierarchy & Buffer Strategy for Hardware

## Purpose

Every data path between modules needs buffers. Getting buffer sizing, placement, and arbitration strategy right is the difference between a pipeline that runs at line rate and one that deadlocks or drops data. This document covers the core formulas and patterns.

**When to use:** Any multi-module design, any rate-mismatched interface, any pipeline with feedback paths.

**Authority (Tier 1-4):** Dally & Towles "Principles and Practices of Interconnection Networks" (Morgan Kaufmann, 2004) §13.1-13.3 Buffered Flow Control with Eq.13.1 buffer sizing `F ≥ ceil(t_crt × b / L_f)`, §18.1-18.6 Arbiters (Fixed Priority §18.3, Round-Robin §18.4, Matrix §18.5, Queuing §18.6); ARM IHI 0022K §A6.3-A6.6 Transaction Ordering (outstanding transaction buffering); Hennessy & Patterson "Computer Architecture: A Quantitative Approach" 6th ed. §1.8-1.9 Performance, App.C Pipelining, §2 Memory Hierarchy; Little, J.D.C. "A Proof for the Queuing Formula: L=λW" Operations Research 9(3):383-387, 1961 (core buffer sizing theorem); Cummings "Simulation and Synthesis Techniques for Asynchronous FIFO Design" SNUG 2002 (Gray-code pointer sync, full/empty detection); Mohit Arora "The Art of Hardware Architecture" Springer 2012 (SKID/elastic buffer pattern); NVMe Base Specification 2.0e §4.1 Submission/Completion Queues, §4.5 Arbitration (WRR for NVMe I/O queues); Åkesson et al. "Real-Time Scheduling Using Credit-Controlled Static-Priority Arbitration" RTCSA 2008 (CCSP — credit-aware arbiter); Alan Jay Smith "Sequential Program Prefetching in Memory Hierarchies" IEEE Computer 11(12):7-21, 1978 (first systematic prefetch analysis, 10-25% effective speedup demonstrated); Falsafi & Wenisch "A Primer on Hardware Prefetching" Morgan & Claypool 2014 §3.1 (stride/stream prefetchers); PCIe Base Specification rev 3.0 §2.6 (credit-based flow control for TLPs). Additional: Patterson & Hennessy "Computer Organization and Design" §5.1-5.4 (CPU cache — not applicable to general buffer sizing); Xilinx UG901 §3 (FIFO inference in Vivado — covers BRAM/SRL inference only, not depth formulas).

**Note on engineering heuristics:** The SKID buffer term is industry convention (not from any single academic source); the FIFO depth formula `depth = burst_size × (1 - consumer_rate/producer_rate)` derives from rate-matching principles found in Dally & Towles Eq.13.1 and Cummings SNUG 2002; ping-pong/double buffering is standard practice documented in AMD PG021 AXI DMA §Cyclic DMA Mode. All heuristics have been validated against Dally & Towles' buffer sizing framework.

---

## 1. Buffer Sizing

### The Core Formula

```
buffer_depth = max_rate × max_latency_differential
```

Where:
- `max_rate` = maximum input rate (items/cycle)
- `max_latency_differential` = worst-case difference between producer and consumer response times

### Derivation: Producer-Consumer with Backpressure

```
Producer ──[FIFO]──> Consumer
   ↑                    │
   └─ ready ────────────┘
```

**Worst case:** Producer writes at rate P items/cycle. Consumer reads at rate C items/cycle. Backpressure takes L cycles to propagate from consumer's ready deassertion to producer seeing it.

```
FIFO depth ≥ P × L  (covers items produced during backpressure latency)
```

If consumer can stall for up to S cycles:
```
FIFO depth ≥ P × (L + S)
```

### Practical Example: NVMe SQ Fetch + Admin Exec

- SQ Fetch produces 1 command every ~10 cycles (8 AXI beats + FSM overhead)
- Admin Exec consumes 1 command every ~512 cycles (Identify data transfer)
- Backpressure latency: Admin Exec ready deassertion → SQ Fetch sees it = 1 cycle (direct wire)

```
FIFO depth = 1 cmd × (1 + 512) / 10 = 51.3 → round up to 2
```

Wait, that doesn't pass the sanity check. The producer rate is 1 cmd/10 cycles = 0.1 cmd/cycle. The consumer takes 512 cycles per command. The producer could issue ~51 commands before noticing the consumer isn't ready. But with a direct wire, the producer sees backpressure immediately.

**Corrected formula for direct backpressure:**
```
FIFO depth ≥ burst_size × (1 - consumer_rate / producer_rate)
         ≥ 1 × (1 - 0.002/0.1) ≈ 1
```

For the admin queue (1 command at a time), depth=2 (SKID buffer) is sufficient.

### SKID Buffer (Depth-2 FIFO)

The minimal buffer for any pipeline interface (Arora 2012, "elastic buffer" pattern). Allows 1 item to be accepted while 1 is being processed. Standard implementation of the forward register slice in AXI pipelines.

```verilog
// SKID buffer: 2-entry FIFO for pipeline decoupling
module skid_buffer #(parameter DW = 64) (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         valid_i,
    output wire         ready_o,
    input  wire [DW-1:0] data_i,
    output wire         valid_o,
    input  wire         ready_i,
    output wire [DW-1:0] data_o
);
    reg [DW-1:0] data_q;     // main register
    reg [DW-1:0] skid_q;     // overflow register
    reg          valid_q;
    reg          skid_valid_q;

    wire stall = !ready_i;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_q      <= 1'b0;
            skid_valid_q <= 1'b0;
        end else if (!stall) begin
            if (valid_i && valid_q) begin
                skid_valid_q <= 1'b1;
                skid_q       <= data_i;  // incoming data goes to skid
            end else begin
                skid_valid_q <= 1'b0;
            end
            valid_q <= valid_i || skid_valid_q;
            data_q  <= skid_valid_q ? skid_q : data_i;
        end
    end

    assign valid_o = valid_q;
    assign data_o  = data_q;
    assign ready_o = !skid_valid_q;  // can accept if skid slot is free
endmodule
```

---

## 2. FIFO Placement Strategy

### Rule: FIFO at Boundaries

Place FIFOs at module boundaries where:
1. **Rate mismatch exists** between producer and consumer
2. **Backpressure latency** exceeds 1 cycle
3. **Clock domain crossing** (CDC FIFO required)
4. **Bursty traffic** needs smoothing

### Placement Patterns

```
Pattern A: Source FIFO (緩解 producer burst)
  [Bursty Producer] ──> [FIFO] ──> [Steady Consumer]

Pattern B: Sink FIFO (緩解 consumer stall)
  [Steady Producer] ──> [FIFO] ──> [Stall-prone Consumer]

Pattern C: Channel FIFO (per-channel buffering)
  [AXI AR] ──> [FIFO_AR] ──> [Read Engine]
  [AXI AW] ──> [FIFO_AW] ──> [Write Engine]
```

### Depth Selection Table

| Scenario | Depth Formula | Typical Value |
|----------|:---:|:---:|
| Direct wire (no rate mismatch) | 2 (SKID) | 2 |
| Single-cycle backpressure latency | `P × 2` | 4-8 |
| Multi-cycle consumer stall | `P × S_max` | 16-64 |
| CDC crossing | `P_src × (T_dst / T_src) × 4` | 8-32 |
| AXI burst forwarding | `burst_length × num_pending` | 16-256 |

---

## 3. Ping-Pong / Double Buffering

### Concept

Two identical buffers. While one is being filled (write buffer), the other is being drained (read buffer). Swap roles when write buffer is full and read buffer is empty.

```
        ┌─ Write Buffer ─┐
Input ──┤                 ├──> Output (via mux)
        └─ Read Buffer  ─┘
```

**Use when:** Continuous streaming input, processing happens in frames/blocks, output side needs uninterrupted access to a complete frame.

### RTL Pattern

```verilog
module ping_pong #(parameter DW = 64, DEPTH = 256) (
    input  wire clk_i, rst_ni,
    input  wire wr_valid_i, output wire wr_ready_o,
    input  wire [DW-1:0] wr_data_i,
    output wire rd_valid_o, input  wire rd_ready_i,
    output wire [DW-1:0] rd_data_o
);
    reg                    buf_sel_q;      // 0=buf0 active write, 1=buf1 active write
    reg [DEPTH-1:0] [DW-1:0] buf0, buf1;
    reg [$clog2(DEPTH):0] wr_ptr_q, rd_ptr_q;
    reg                    buf0_full_q, buf1_full_q;

    // Write side: fill active buffer
    wire active_full = buf_sel_q ? buf1_full_q : buf0_full_q;
    assign wr_ready_o = !active_full;

    // Swap when write completes
    wire swap = active_full && (rd_ptr_q == 0 || ... );  // read side drained

    // Read side: drain inactive buffer
    assign rd_data_o = buf_sel_q ? buf0[rd_ptr_q] : buf1[rd_ptr_q];  // read from OLD buffer
    // ...
endmodule
```

### Tradeoffs

| Aspect | Ping-Pong | Single FIFO |
|--------|:---:|:---:|
| Latency | 1 frame (until swap) | 1 entry |
| Throughput | 1 item/cycle (after swap) | 1 item/cycle |
| Area | 2× depth (plus mux) | 1× depth |
| Use case | Frame-based processing (video, crypto blocks) | Stream processing (packets, beats) |

---

## 4. Arbitration Strategy Comparison

### When Arbitration Matters

When N sources share 1 sink, the arbiter determines which source gets access. The choice affects throughput, fairness, and worst-case latency.

### Comparison Table

| Strategy | Fairness | Max Latency | Area | Use Case |
|----------|:---:|:---:|:---:|------|
| Round-Robin (RR) | Perfect (1/N bandwidth each) | N-1 cycles | O(N) | Equal-priority queues |
| Fixed Priority | None (high priority starves low) | ∞ for low pri | O(N) | Admin > I/O, urgent > normal |
| Weighted RR (WRR) | Proportional to weight | N-1 + W_max | O(N + W) | NVMe URR, QoS shaping |
| Credit-Aware (CCSP) | Earliest credit return wins | N-1 | O(N + credit state) | NVMe SQ arbitration (Åkesson et al. 2008) |

### Deadlock Risk in Arbitration

When the winning source cannot proceed (waiting for a resource held by a losing source), the arbiter deadlocks.

**Prevention:** Grant holder must have guaranteed forward progress. If grant holder stalls waiting for resource R, and R is owned by a non-grant-holder, deadlock.

**Fix:** Pre-allocate resources before arbitration, or allow grant holder to yield.

---

## 5. Prefetch Strategies

### Sequential Prefetch

On access to address A, also fetch A+1. Assumes spatial locality (Smith 1978 — seminal sequential prefetch analysis demonstrating 10-25% effective speedup; Falsafi & Wenisch 2014 §3.1 for stride/stream prefetcher design).

```
Next fetch addr = current_addr + stride
```

**Use case:** Linear DMA transfers, sequential SQ/CQ processing.

### Command-Based Prefetch (NVMe SQ)

The host writes a doorbell with `new_tail`. The controller prefetches commands from `head` up to `min(head + credit_budget, tail)`.

```verilog
// Prefetch credit management
always @(posedge clk_i) begin
    if (doorbell_valid)
        credits_q <= credits_q + (doorbell_tail - tracked_tail_q);  // new work available
    if (fetch_start)
        credits_q <= credits_q - 1;  // consumed one prefetch slot
end
```

### Prefetch Depth

```
prefetch_depth = min(credits_available, max_outstanding_reads)
```

Too shallow: under-utilizes memory bandwidth (read pipeline has bubbles).
Too deep: wastes prefetch on commands that may be cancelled or never processed.

---

## 6. Data Alignment & Reassembly

### Unaligned Access Overhead

When a 64-byte SQE starts at a non-64-byte-aligned address (rare but possible for NVMe PRP lists):
- First read: address & ~0x3F, discard leading bytes up to (address & 0x3F)
- If data crosses page boundary: split into two reads

### WSTRB for Unaligned Writes

```
First beat:  WSTRB = ~{8{1'b0}} << (addr & 0x7)  // mask leading bytes
Middle beats: WSTRB = 8'hFF                         // all bytes valid
Last beat:   WSTRB = {8{1'b0}} >> (total_bytes mod 8 != 0 ? 8 - (total_bytes mod 8) : 0)
```

---

## Design Checklist (add to Step 2a P4+P6 review)

When a design involves memory or buffering:
1. **FIFO depth calculation:** For each FIFO in the design, compute `depth = max_rate × max_stall_cycles`. Show your work.
2. **Deadlock audit:** For each FIFO, check: can the consumer stall indefinitely? If yes, does the producer have an alternative path?
3. **Arbitration fairness:** If multi-source arbitration is used, state the strategy and worst-case starvation time.
4. **Alignment handling:** If addresses may be unaligned, show WSTRB logic for first and last beats.
5. **Prefetch budget:** If prefetch is used, state max outstanding reads and credit management.
