# Pipeline Design Patterns for Hardware

## Purpose

Pipeline design is the most fundamental system architecture skill after RTL craftsmanship. Every non-trivial digital design involves pipelines — whether explicit (AXI-Stream processing chains) or implicit (FSM→datapath→output paths). This document defines the 5 core pipeline topologies, their backpressure propagation rules, buffer sizing requirements, and common failure modes.

**When to use:** Any design with ≥2 processing stages, any multi-module data path, any protocol adapter with rate mismatch.

**Authority (Tier 1-4):** Dally & Towles "Principles and Practices of Interconnection Networks" (Morgan Kaufmann, 2004) §13.1 Packet-Buffer Flow Control (store-and-forward), §13.2 Flit-Buffer Flow Control (cut-through/wormhole), §13.3.1 Credit-Based Flow Control with Eq.13.1 buffer sizing formula `F ≥ ceil(t_crt × b / L_f)`, §13.3.2 On/Off Backpressure, §16.2 Stalls, §16.3 Credit Loop Closure, §18 Arbiters; Carloni, McMillan, Sangiovanni-Vincentelli "Theory of Latency-Insensitive Design" IEEE TCAD 20(9):1059-1076, 2001 (formal valid/stop backpressure protocol); ARM IHI 0022E §A3.3.1-A3.3.2 (VALID/READY handshake), §A3.5 (VALID must NOT depend on READY — deadlock prevention), §A5 Transaction IDs, §A6 Ordering Model; Hennessy & Patterson "Computer Architecture: A Quantitative Approach" 6th ed. §1.8 Performance Metrics, §1.9 Amdahl's Law, App.C Pipeline CPI/Stalls; Little, J.D.C. "A Proof for the Queuing Formula: L=λW" Operations Research 9(3):383-387, 1961; IETF RFC 1242 §3.8 (cut-through vs store-and-forward latency definitions). Additional: Patterson & Hennessy "Computer Organization and Design" §4.5-4.8 (CPU pipeline — not applicable to valid/ready handshake); Sutherland "Verilog Gotchas" Ch.6 (registered vs combinational outputs).

**Note on pipeline topology classification:** The 5-pattern taxonomy (Feed-forward, Feedback, Multi-rate, Fork-Join, Cut-through vs Store-forward) is a design abstraction synthesized from the sources above — it does not appear as a named classification in any single textbook. Dally & Towles provides the flow control mechanisms (§13) and router microarchitecture (§16); Carloni provides the formal valid/ready protocol; H&P provides the performance analysis framework. The synthesis is ours, verified by NVMe Phase 1 empirical data.

---

## 1. Feed-Forward Pipeline

### Concept

Data flows unidirectionally through N stages. Each stage can independently assert backpressure. The pipeline as a whole propagates stall signals upstream.

```
Stage 0 ──(v0,r0)──> Stage 1 ──(v1,r1)──> Stage 2 ──(v2,r2)──> output
```

### Valid/Ready Propagation Rules

The valid/ready protocol was formally defined by Carloni et al. (2001) as the "latency-insensitive design" (LID) relay station. The backpressure propagation formula below is the standard Forward Register Slice implementation of the LID protocol.

For a single pipeline stage:
```
valid_out = valid_in_registered   (1 cycle delayed from input valid)
ready_in  = ready_out OR !valid_out  (can accept if downstream ready or stage empty)
```

Full backpressure link: `ready_N-1 = ready_N || !valid_N-1`

**Critical rule:** valid and data must move together. When stall occurs, ALL stage state (valid, data, sideband) freezes.

### RTL Template (Single Stage)

```verilog
// Pipeline stage: 1 cycle delay, stallable
module pipeline_stage #(parameter DW = 64) (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         valid_i,
    output wire         ready_o,
    input  wire [DW-1:0] data_i,
    output wire         valid_o,
    input  wire         ready_i,
    output wire [DW-1:0] data_o
);
    reg         valid_q;
    reg [DW-1:0] data_q;

    wire stall = !ready_i;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_q <= 1'b0;
            data_q  <= {DW{1'b0}};
        end else if (!stall) begin
            valid_q <= valid_i;
            data_q  <= data_i;
        end
    end

    assign valid_o = valid_q;
    assign data_o  = data_q;
    assign ready_o = ready_i || !valid_o;  // accept if downstream ready or stage empty
endmodule
```

### Multi-Stage Chain (N stages in series)

```verilog
// Instantiate N stages, connect ready backward (downstream → upstream)
wire [N:0] valid;   // valid[0] = input, valid[N] = output
wire [N:0] ready;   // ready[N] = downstream_ready, ready[0] = upstream_ready
wire [N-1:0] [DW-1:0] data;

assign valid[0] = valid_i;
assign ready_o  = ready[0];
assign valid_o  = valid[N];
assign ready[N] = ready_i;

genvar i;
generate for (i = 0; i < N; i = i + 1) begin : stage
    pipeline_stage #(.DW(DW)) u_stage (
        .clk_i, .rst_ni,
        .valid_i(valid[i]),
        .ready_o(ready[i]),
        .data_i(i == 0 ? data_i : data[i-1]),
        .valid_o(valid[i+1]),
        .ready_i(ready[i+1]),
        .data_o(data[i])
    );
end endgenerate
```

### Common Errors

| Error | Symptom | Fix |
|-------|---------|-----|
| valid advances but data stalls | Data corruption — stale values forwarded | Freeze data register when stall=1 |
| ready computed as `ready_i` only | Stage 0 stalls even when stage 1 empty | `ready_o = ready_i \|\| !valid_o` |
| Data path skips stall register | First beat lost, subsequent beats shifted | All data paths go through stage register |
| No explicit valid reset | X propagation after reset | Reset valid_q to 0 |

### Performance

- **Latency:** N cycles (1 per stage)
- **Throughput:** 1 item/cycle (when no stalls) — ideal for balanced pipelines
- **Buffer requirement:** 1 register per stage per data item (inherent in the stage registers)

---

## 2. Feedback / Backpressure Pipeline

### Concept

When a downstream module's backpressure signal depends on upstream processing completion, the pipeline forms a feedback loop. This is common in multi-module systems where completion posting must wait for data transfer.

```
Producer ──data──> Consumer ──completion──> Poster
    ^                                              │
    └──────────── backpressure ─────────────────────┘
```

### NVMe Example (from Phase 1)

```
SQ Fetch ──cmd──> Admin Exec ──cpl──> CQ Post
                          │                │
                          └── data ──> host mem
                                       │
                          cq_data_done? (feedback to CQ Post)
```

**The bug:** Admin Exec finished DATA_XFER before CQ Post entered WAIT_DATA. The cq_data_done pulse was missed.

**The fix pattern:** Use a **level flag** (not a pulse) for cross-module completion signals, or use a **stored event register** that persists until acknowledged:

```verilog
// Cross-module completion: use stored event, not pulse
reg data_xfer_done_q;

always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
        data_xfer_done_q <= 1'b0;
    else if (data_xfer_last && data_valid && data_ready)
        data_xfer_done_q <= 1'b1;           // set on completion
    else if (consumer_ack)
        data_xfer_done_q <= 1'b0;           // clear when consumer acknowledges
end
```

### Backpressure Deadlock Detection

A feedback pipeline deadlocks when:
1. Module A waits for B to complete before sending more data
2. Module B waits for A to send data before completing

**Detection formula:** Check the dependency graph for cycles. If A→B→A exists, ensure at least one link has a bypass or buffer.

```
Depth needed = rate_A × latency_B
```
If A produces at rate R items/cycle and B takes L cycles to respond, the feedback path needs at least R×L buffer slots to prevent deadlock.

### Common Errors

| Error | Symptom | Fix |
|-------|---------|-----|
| Pulse completion missed | Consumer waits forever | Use level flag or event register |
| Feedback path unbuffered | Deadlock on first item | Add FIFO depth = throughput × feedback_latency |
| Circular wait (A waits B, B waits A) | Both modules stuck | Break cycle with buffer or timeout |

---

## 3. Multi-Rate Pipeline

### Concept

Producer and consumer operate at different rates. An adapter module is needed to match the rates.

```
Source (1 item every M cycles) ──> Rate Adapter ──> Sink (1 item every N cycles)
```

| Type | M > N | M < N |
|------|-------|-------|
| Source faster | Adapter needs FIFO (buffer excess) | — |
| Sink faster | — | Adapter inserts idle cycles |

### NVMe SQ Fetch (M=8, N=1)

The SQ fetch reads 8 AXI beats (one per cycle at the AXI interface) to assemble 1 SQE.
- Source rate: 1 beat/cycle × 8 beats = 1 SQE every 8 cycles + overhead
- Sink rate: 1 command/cycle (admin_exec processes 1 command at a time)
- Adapter: assembly buffer (512-bit fetch_buf) + valid generation on last beat

### RTL Pattern: Assembly Buffer (N-to-1)

```verilog
// Assembles N beats of WIDTH into one ITEM
module beat_assembler #(parameter BEATS = 8, parameter WIDTH = 64) (
    input  wire                  clk_i,
    input  wire                  rst_ni,
    input  wire                  beat_valid_i,
    output wire                  beat_ready_o,
    input  wire [WIDTH-1:0]     beat_data_i,
    input  wire                  beat_last_i,   // last beat of item
    output wire                  item_valid_o,
    input  wire                  item_ready_i,
    output wire [BEATS*WIDTH-1:0] item_data_o
);
    reg [$clog2(BEATS)-1:0] beat_cnt_q;
    reg [BEATS*WIDTH-1:0]   buffer_q;

    wire assembling = (beat_cnt_q != 0) || beat_valid_i;
    wire item_done  = beat_valid_i && beat_last_i;

    assign beat_ready_o = !item_done || item_ready_i;  // stall if item ready but not consumed

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            beat_cnt_q <= 0;
            buffer_q   <= 0;
        end else begin
            if (beat_valid_i && beat_ready_o) begin
                buffer_q[beat_cnt_q*WIDTH +: WIDTH] <= beat_data_i;
                beat_cnt_q <= item_done ? 0 : beat_cnt_q + 1;
            end
        end
    end

    assign item_valid_o = item_done;
    assign item_data_o  = buffer_q;
endmodule
```

### RTL Pattern: Rate Decoupler (1-to-N with FIFO)

When the producer is bursty and consumer is slower, insert a FIFO:
```
Producer (bursty) ──> FIFO (smoothing) ──> Consumer (steady)
```

FIFO depth formula:
```
depth_min = burst_size × (1 - consumer_rate / producer_rate)
depth_safe = burst_size  (conservative: buffer the entire burst)
```

### Common Errors

| Error | Symptom | Fix |
|-------|---------|-----|
| Beat counter not reset on last | Item assembly corrupt (beats from different items mixed) | Reset counter on beat_last_i |
| Consumer rate assumed to match | Overflow (FIFO full drops data) | Size FIFO using rate formula |
| Backpressure not propagated to beats | Overflow at assembler | `beat_ready_o = !item_done \|\| item_ready_i` |

---

## 4. Fork-Join Pipeline

### Concept

Data enters a single input, splits into parallel processing paths, and rejoins at a synchronization point.

```
                      ┌──> Path A (e.g., data write) ──┐
Input ──> Splitter ──┤                                 ├──> Joiner ──> Output
                      └──> Path B (e.g., completion) ──┘
```

### NVMe Identify (Fork-Join Bug)

The Identify command forks into two paths:
1. **Data path:** 512 beats of controller data → PRP1 address in host memory
2. **Completion path:** CQE assembly and posting after data completes

**The bug:** The joiner (CQ Post WAIT_DATA) was waiting for a pulse that had already passed.

### Design Rules

1. **Splitter must duplicate or fan-out:** All downstream paths receive the same input (or mutually exclusive subsets)
2. **Joiner must wait for ALL paths:** Use a counter or flag-per-path
3. **Buffering at join point:** Each path may have different latency; the joiner must tolerate the worst case
4. **Deadlock prevention:** No path should wait for another path's output as its own input

### RTL Pattern: Join Counter

```verilog
// Join controller: waits for all N paths to complete
module join_controller #(parameter N = 2) (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire [N-1:0] path_done_i,   // one-bit per path
    output wire         all_done_o
);
    reg [N-1:0] done_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            done_q <= {N{1'b0}};
        else
            done_q <= done_q | path_done_i;  // accumulate done flags
    end

    assign all_done_o = &done_q;  // all paths done?
endmodule
```

**Note:** Use level flags (not pulses) for `path_done_i`. If a path completes before the joiner starts monitoring, the level flag preserves the event.

---

## 5. Cut-Through vs Store-and-Forward

### Cut-Through

Data is forwarded beat-by-beat. First output beat appears before the entire item is received.

```
Beat 0 in ──> [register] ──> Beat 0 out
Beat 1 in ──> [register] ──> Beat 1 out (while Beat 2 is arriving)
...
```

**Use when:** Low latency required, input and output rates are matched, no data-dependent processing.
**Latency:** 1 cycle (single stage delay)
**Buffer needed:** 1 register per beat width

### Store-and-Forward

The entire item is buffered before any output is produced.

```
Beat 0..N-1 in ──> [assembly buffer] ──> output all at once when complete
```

**Use when:** Processing requires the full item (CRC, parsing, encryption), output format differs from input (64-byte SQE → parsed fields), rate matching needed.

**Latency:** N cycles (full item reception) + processing time
**Buffer needed:** item_size (full item storage)

### Decision Matrix

| Criterion | Cut-Through | Store-and-Forward |
|-----------|:---:|:---:|
| Latency | 1-2 cycles | Item time |
| Buffer cost | 1 beat | Full item |
| Throughput | 1 beat/cycle | Bursty (item-level) |
| Out-of-order tolerance | Beat-level reorder | Item-level only |
| Use case | AXI W channel forwarding | SQE assembly, CRC check |

---

## Pipeline Principle Mappings

| Pattern | P1 (Timing) | P4 (Independence) | P6 (Boundaries) |
|---------|:---:|:---:|:---:|
| Feed-forward | valid/data alignment across stages | Each stage independent backpressure | Stage port widths must match |
| Feedback | Completion signal timing (level vs pulse) | Feedback path must not couple data path | Cross-module handshake contract |
| Multi-rate | Beat counter timing, rate contract | Rate adapter decouples producer/consumer | Rate ratio documented in contract |
| Fork-Join | Path completion detection (pulse→level) | Forked paths must be independent | Joiner must know N paths |
| Cut-through | Beat-level valid stability | Forward regardless of remaining beats | Buffer depth exposed at boundary |

---

## Design Checklist (add to Step 2a P4+P6 review)

When a design involves a pipeline:
1. **Topology:** Which pipeline pattern(s) apply? Draw the valid/ready connection graph.
2. **Buffer sizing:** For each rate mismatch or feedback path, compute minimum FIFO depth.
3. **Backpressure propagation:** Trace `ready` from each sink back to each source. Any missing links?
4. **Deadlock check:** Does the dependency graph have cycles? Is every cycle broken by a buffer?
5. **Completion signal type:** Are cross-module completion signals level (flag) or pulse? If pulse, is there a risk of the consumer missing it?
