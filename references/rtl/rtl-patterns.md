# Curated RTL patterns

## Source policy
This library should be built from authoritative, engineering-grade references and validated project patterns.
Prefer patterns that are common in real flows and easy to verify.
Do not promote a style just because it appears in a random example.

## Pattern selection principles
- Choose the simplest pattern that satisfies the requirement.
- Prefer readable, synthesizable structures over dense micro-optimized code.
- Keep protocol semantics and verification hooks visible.
- Reject patterns that are ambiguous about latency, reset, or backpressure.
- When a pattern depends on memory, reset, or protocol boundary policy, state the policy before code.

## High-value patterns

### 1. Ready/valid register slice
Use when a boundary needs controlled decoupling with one-cycle storage.
Key points:
- define when data is accepted
- define when data is held
- define how backpressure propagates
- preserve sideband alignment
Default contract:
- `ready_o = !valid_o || ready_i`
- accept input when `valid_i && ready_o`
- hold output while `valid_o && !ready_i`
- registered output is visible after the active clock edge
Do not use when the user needs zero-latency pass-through.

### 2. Skid buffer
Use when single-cycle backpressure tolerance is required.
Key points:
- identify pass-through versus buffered cycles
- keep acceptance and forwarding rules explicit
- verify no data duplication or loss
Do not generate a skid buffer unless the contract says whether pass-through is allowed and whether output data is combinational or registered.

### 3. FIFO
Use when ordering and bounded storage are needed.
Key points:
- choose pointer or occupancy based implementation
- define full/empty boundary semantics
- define simultaneous write/read behavior
- include reset and flush policy if needed
Default contract:
- count tracks accepted writes minus accepted reads
- overflow and underflow attempts are ignored or flagged according to contract
- full+read and empty+write same-cycle behavior must be explicit
- memory read data timing must be explicit

### 4. Pipeline stage
Use when timing closure or latency control is the goal.
Key points:
- specify stage latency
- define stall and flush behavior
- keep data and valid aligned
- preserve bypass semantics if any
Default contract:
- `advance` moves every protected field together
- `stall` freezes valid, payload, and sideband
- `flush` clears valid and defines what happens to payload

### 5. FSM controller
Use when the block is control-heavy and state dependent.
Key points:
- enumerate legal states
- define transition conditions
- define outputs per state
- define reset state and illegal-state handling

### 6. Arbiter
Use when multiple requesters compete for a single resource.
Key points:
- define arbitration policy
- define fairness expectations
- define grant hold and revoke behavior
- define interaction with backpressure

### 7. Counter and event detector
Use for simple sequencing, timeout, pulse generation, and edge detection.
Key points:
- define count enable, wrap, and saturation behavior
- define pulse width and alignment
- define reset values precisely

### 8. CDC synchronizer wrapper
Use only for known safe crossing patterns.
Key points:
- treat single-bit and multi-bit cases differently
- define handshake or toggle scheme when needed
- require explicit review for any multi-bit transfer

For arbiter, req/ack, counter/event, and CDC planning details, read `advanced-patterns.md`.

## For each pattern, store
- Purpose
- Interface contract
- Cycle behavior summary
- Reference RTL
- Directed tests
- Assertions
- Common bugs
- Do not use when

## What the agent should learn from patterns
- Which structure fits which problem
- What assumptions are required before coding
- How to explain timing in a repeatable way
- Which checks should accompany the code
