# Requirement extraction template — from vague spec to structured contract

## Purpose

Use this template BEFORE the timing contract (Step 2) when the input spec is underspecified, informal, or missing critical dimensions. It provides a structured framework to surface implicit requirements, document assumptions, and identify gaps that need user clarification.

## When to use

Trigger when ANY of these are unspecified:
- Protocol details (CRC width/poly, packet format, channel mapping)
- Data widths or address ranges
- Clock/reset strategy
- Throughput or latency targets
- Error handling policy
- Boundary conditions (min/max lengths, overflow, underflow)
- Integration context (what drives this module, what consumes its output)

## Classification framework

For each dimension of the design, classify into one of four categories:

| Category | Meaning | Action |
|----------|---------|--------|
| **Required** | Must be specified for the design to function | Ask the user if missing |
| **Implied** | Follows from the spec even if not stated | State the implication explicitly, get confirmation |
| **Assumed** | Designer must choose; document as an explicit assumption | Choose the most common/conservative default, document WHY |
| **Unknown** | Cannot be decided from spec alone | Ask the user with concrete options |

## Extraction checklist (pre-contract)

Before writing any RTL or timing contract, answer these questions:

### 1. Interface protocol
- [ ] Data interface type: AXI-Stream? AXI-Full? APB? Custom handshake?
- [ ] If AXI-Stream: TDATA width? TSTRB? TKEEP? TLAST semantics? TID/TDEST?
- [ ] If AXI-Full: DATA_WIDTH? ID_WIDTH? outstanding capability?
- [ ] Flow control: Valid/ready? Req/ack? Fixed latency? No backpressure?

### 2. Data format
- [ ] Payload width and byte ordering (endianness)
- [ ] Multi-beat structure: how are beats assembled into logical units (packets/frames/blocks)?
- [ ] Framing: length field? fixed size? TLAST? header/trailer?
- [ ] Checksum/CRC: polynomial? width? coverage (header only or full packet)?

### 3. Operational parameters
- [ ] Min/max transfer sizes
- [ ] Throughput target (beats per cycle, or maximum stalls)
- [ ] Addressing: aligned only? unaligned supported? 4KB boundary handling?
- [ ] Concurrency: single or multiple outstanding operations?

### 4. Error handling
- [ ] What errors are possible? (protocol errors, checksum failures, timeouts, overflow)
- [ ] Error response: drop packet? flag error? forward corrupted data? stall?
- [ ] Error reporting: per-packet status? sticky error flag? interrupt?
- [ ] Recovery: continue to next packet? require reset?

### 5. Clock and reset
- [ ] Single or multiple clock domains?
- [ ] Clock frequencies and relationship (synchronous? asynchronous? integer ratio?)
- [ ] Reset: active-high or active-low? synchronous or asynchronous deassertion?
- [ ] Reset value of outputs (0? high-Z? last value?)

### 6. Integration context
- [ ] What drives the input? (another module? external pin? register interface?)
- [ ] What consumes the output? (downstream FIFO? AXI interconnect? custom logic?)
- [ ] Are there any sideband signals? (start, abort, status, interrupts?)

## Design decision log

For every **Assumed** dimension, document:

```markdown
| Decision | Value chosen | Alternatives considered | Why this choice |
|----------|-------------|------------------------|-----------------|
| CRC polynomial | CRC-32 (0x04C11DB7) | CRC-16-CCITT, CRC-8 | Most common; matches IEEE 802.3; skill reference available |
| Channel select | Header bits [1:0] | Dedicated channel field | Simplest mapping; 2 bits = 4 channels |
| Min packet size | 2 beats (8 bytes) | 1 beat | Need at least 1 header beat + 1 CRC beat |
```

This log is part of the deliverable. Future reviewers (or the user) must be able to see every assumption that was made without spec backing.

## Ambiguity resolution — how to ask the user

When a Required or Unknown dimension needs user input, present it as a choice, not an open question:

**Bad:** "What CRC should I use?"
**Good:** "The spec says 'check CRC' but doesn't specify which one. I'll use CRC-32 (IEEE 802.3, 0x04C11DB7) with byte reflection — this is the most common for data paths. Is that acceptable, or do you need a different polynomial?"

The designer proposes a default and asks for confirmation. This minimizes round-trips while keeping the user in control.

## Integration with skill workflow

1. Run this extraction BEFORE Step 2 (timing contract)
2. Attach the filled checklist + decision log to the timing contract
3. If more than 3 Required dimensions are unanswered, pause and ask the user before proceeding
4. Any Assumed dimension that turns out to be wrong is NOT a code bug — it's a spec gap. Document it and move on.
