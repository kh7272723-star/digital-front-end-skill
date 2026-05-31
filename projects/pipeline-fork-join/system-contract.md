# System Contract — Split-Path Pipeline with Completion Join

## Purpose

Validate two pipeline patterns from `references/architecture/pipeline-design-patterns.md`:
1. **Fork-Join (§4):** Input splits into Data Path + Stats Path, rejoin at output
2. **Feedback Completion (§2):** pkt_done_o level flag feeds back to gate next input

## Pipeline Topology

```
                       ┌──> Data Path (2-stage feed-forward) ──┐
s_axis (AXI-Stream) ──> Splitter                               Joiner ──> m_axis (AXI-Stream)
                       └──> Stats Path (beat counter) ──────────┘
                                                                    │
                       pkt_done_o (level flag) <── completion ─────┘
```

- **Splitter:** Accepts AXI-Stream beats, increments beat counter, routes data into pipeline
- **Data Path:** 2-stage feed-forward pipeline (each stage = 1 cycle latency, stallable)
- **Stats Path:** Beat counter + final capture on TLAST + 2-cycle alignment delay
- **Joiner:** Monitors pipeline output TLAST + aligned stats → asserts pkt_done_o

## Module: `fork_join_pipeline`

**Classification:** L1 (Leaf) — single module, ~250 lines, AXI-Stream + internal fork

**Parameters:**
| Parameter | Default | Description |
|-----------|---------|-------------|
| DATA_WIDTH | 8 | Width of data beats |
| PIPELINE_STAGES | 2 | Number of feed-forward stages in data path |

**Ports:**
| Signal | Width | Dir | Description |
|--------|-------|-----|-------------|
| clk_i | 1 | in | Clock |
| rst_ni | 1 | in | Async active-low reset |
| s_axis_tvalid_i | 1 | in | Input valid |
| s_axis_tready_o | 1 | out | Input ready |
| s_axis_tdata_i | DATA_WIDTH | in | Input data |
| s_axis_tlast_i | 1 | in | Input last beat of packet |
| m_axis_tvalid_o | 1 | out | Output valid |
| m_axis_tready_i | 1 | in | Output ready |
| m_axis_tdata_o | DATA_WIDTH | out | Output data |
| m_axis_tlast_o | 1 | out | Output last beat |
| pkt_done_o | 1 | out | Packet complete (level flag) |
| beat_count_o | 8 | out | Number of beats in packet (valid when pkt_done_o=1) |

## Timing Contract

### Signal Types
| Signal | Type | Description |
|--------|------|-------------|
| s_axis_tready_o | Combinational | `= !pipe_full` — accepts when pipeline can take data |
| m_axis_tvalid_o | Registered | Pipeline stage N-1 valid output |
| m_axis_tdata_o | Registered | Pipeline stage N-1 data output |
| m_axis_tlast_o | Registered | Pipeline stage N-1 tlast output |
| pkt_done_o | Level | High from joiner completion until next packet starts |
| beat_count_o | Registered | Captured at TLAST, held until next TLAST |

### Pipeline Latency
- Data: PIPELINE_STAGES cycles (2 for default)
- Stats alignment: PIPELINE_STAGES cycle delay line to match data path

### Completion Protocol
- `pkt_done_o` asserts when BOTH:
  1. Pipeline output TLAST emerges (data path complete)
  2. Stats alignment delay expires (stats path complete)
- `pkt_done_o` deasserts when next packet's first beat enters the pipeline (splitter accepts new data after done)

### Backpressure
- Input backpressure: `s_axis_tready_o = !(pipe_full)` — blocks when pipeline stage 0 is occupied
- Pipeline stages follow standard `ready_o = ready_i || !valid_o` backpressure propagation
- No credit mechanism — single packet in-flight (simplified for validation)

## Key Design Decisions

1. **Level flag for completion (not pulse):** Prevents the NVMe Phase 1 bug where `cq_data_done` pulse was missed by a consumer not yet monitoring. `pkt_done_o` is a level flag that persists until the next packet starts.

2. **Stats alignment delay = PIPELINE_STAGES:** The beat counter captures at input TLAST (cycle N). The data path TLAST emerges at cycle N+PIPELINE_STAGES. A shift register delays the stats valid signal to align.

3. **Single-packet in-flight:** Simplifies credit management. The splitter blocks input while a packet is in the pipeline. This avoids the full credit-based flow control complexity while still testing the fork-join and feedback patterns.

## States
- **IDLE:** No packet in pipeline. Wait for input valid. Clear done flags.
- **BUSY:** Packet flowing through. Wait for joiner to see pipeline output TLAST + aligned stats.
  - Transition to DONE when `pipe_tlast_out && stats_aligned`
- **DONE:** Assert pkt_done_o. Wait for external consumer to acknowledge (implicit — next packet start clears).

## Test Plan
1. **T1 (single beat packet):** 1 beat with TLAST=1 → verify pkt_done_o after 2-cycle pipeline latency + stats alignment
2. **T2 (multi-beat packet, 5 beats):** Verify data integrity, beat_count_o = 5, pkt_done_o timing
3. **T3 (back-to-back packets):** 2 packets in sequence, verify pkt_done_o deasserts between packets
4. **T4 (backpressure):** Downstream m_axis_tready_i=0 stalls pipeline, verify data not lost, pkt_done_o delayed correctly
5. **T5 (Fork-Join timing):** Verify that pkt_done_o does NOT assert before BOTH data TLAST AND stats alignment complete
