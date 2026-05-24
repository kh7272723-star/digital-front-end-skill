# Debug cases for digital front-end work

## Source policy

Only include cases that are well understood, reproducible, and consistent with standard RTL methodology.
Prefer cases that expose an actual timing or protocol mistake, not just stylistic disagreement.

## Case template

For each case, record:

- symptom
- root cause
- failing waveform or log clue
- fix
- regression test
- prevention rule

## Common cases

### 1. Reset release leaves invalid state

Symptom:

- outputs look correct during reset but misbehave for one or more cycles after reset deassertion.

Likely cause:

- state registers and output registers are not initialized consistently.

What to inspect:

- first post-reset cycle
- default assignments
- state encoding after release

Prevention:

- define post-reset cycle behavior explicitly
- add reset assertions

### 2. Ready/valid transfer loses data under backpressure

Symptom:

- simulation shows missing or duplicated transactions when downstream stalls.

Likely cause:

- valid/data are not held stable until accepted.

What to inspect:

- handshake cycle
- buffering path
- acceptance condition

Prevention:

- assert data stability while valid is asserted and ready is low

### 3. FIFO full/empty off-by-one error

Symptom:

- FIFO reports full too early or accepts one write too many.

Likely cause:

- pointer or occupancy update is mis-specified around wraparound.

What to inspect:

- simultaneous write/read
- boundary transitions
- reset initialization

Prevention:

- model occupancy explicitly in tests
- add boundary-directed tests

### 4. FSM gets stuck in a state

Symptom:

- controller never exits a state after a rare event.

Likely cause:

- a transition condition is missing, inverted, or masked by reset/enable logic.

What to inspect:

- all outgoing transitions from the stuck state
- default branch behavior
- event ordering over consecutive cycles

Prevention:

- table-driven state review
- cover each transition in directed tests

### 5. Pipeline stage duplicates or drops a bubble

Symptom:

- output stream is shifted or inconsistent by one cycle.

Likely cause:

- valid and data are not advanced together, or stall logic is asymmetric.

What to inspect:

- stage enable path
- data/valid alignment
- flush behavior

Prevention:

- check cycle-by-cycle propagation with a tagged transaction

### 6. Combinational latch appears in synthesis or lint

Symptom:

- lint warns about incomplete assignment or inferred latch.

Likely cause:

- not all branches assign the signal.

What to inspect:

- combinational default assignments
- case/if coverage

Prevention:

- assign defaults at the top of combinational blocks

### 7. CDC crossing behaves randomly

Symptom:

- sporadic failures or metastability-like behavior in hardware or gate-level sim.

Likely cause:

- crossing is unsynchronized or protocol is incomplete.

What to inspect:

- clock domains involved
- synchronizer pattern
- transfer width and handshake discipline

Prevention:

- require CDC review before implementation

## Debugging style

- Start from observable evidence.
- State the minimal hypothesis that explains the failure.
- Change one thing at a time.
- Re-run the smallest relevant regression.
- Capture the prevention rule so the bug does not return.
