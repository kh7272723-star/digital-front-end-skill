# Development Log Template

## Purpose

Every project must produce a development log for 复盘 (retrospective analysis) and 问题回溯 (issue traceability). Fill sections **as you go** — do not wait until the end.

This template is mandatory for L1/L2 projects. L0 projects may use a condensed one-paragraph version inline in their working notes.

---

## 1. Project Header

```
# DEVELOPMENT_LOG.md — <project_name>

**Module:** <top_module>
**Classification:** L0 / L1 / L2
**Workflow:** Standard / Distributed Checkpoints
**Date:** YYYY-MM-DD
**Agent:** <agent_id>
```

---

## 2. Bug Tracking Table (fill as you go — most important section for 复盘)

| # | Symptom | Found at | Principle | Root Cause | Fix | Iteration |
|:---:|------|:---:|:---:|------|------|:---:|
| 1 | TX_DONE never asserts | Step 9 iter 1 | P2 (FSM) | STOP state always returns to IDLE, ignoring FIFO back-to-back chain | Added `if (!fifo_empty) state_d = S_START` in STOP case | 2 |

**Columns:**
- **#:** Sequential bug ID
- **Symptom:** What the testbench/simulation reported (copy the actual FAIL message)
- **Found at:** Which workflow step caught it — "Step 5a P2 review", "Step 7b yosys", "Step 9 iter 2"
- **Principle:** Which design principle was violated (P1-P6, P5a, P5b). Leave blank if it's a testbench or tool issue
- **Root Cause:** The actual RTL/contract/testbench error — not the symptom, the cause
- **Fix:** What changed. Cite the file and line if possible
- **Iteration:** Which simulation iteration was the fix verified in

**Key insight for 复盘:** The "Found at" column is the single most valuable data point. Bugs caught at Step 2a/5a cost 10× less to fix than bugs caught at Step 9.

---

## 3. Simulation Iteration Log (fill per iteration)

```
### Iteration 1
**Command:** `iverilog -g2012 -o sim.vvp <src> <tb> && vvp sim.vvp`
**Result:** Compile error / Simulation FAIL / ALL_TESTS_PASS
**Failures (if any):**
  - T2: <symptom>
  - T4: <symptom>
**Actions:**
  - <what you changed before re-running>

### Iteration 2
...
```

Number iterations starting from 1. Include the exact command and output markers (`TEST_START`, `TEST_PASS`, `TEST_FAIL`, `ALL_TESTS_PASS`, `SIMULATION_DONE`).

---

## 4. Principle Review Findings (fill at each checkpoint)

### Step 2a — P4 (Independence) + P6 (Boundaries)
- **Issues found:** 0
- **Design decisions changed:** <list or "none">
- **Risks deferred:** <list or "none">

### Step 5a — P1 (Timing) + P2 (FSM Safety)
- **Issues found:** <count>
- **Details:** <bug ID(s) and summary>
- **Design decisions changed:** <list>

### Step 8c — P3 (Known Values) + P5a (Output Discipline)
- **Issues found:** <count>
- **Register audit:** <N>/<total> registers checked, <M> without reset
- **Output discipline:** <issues found>

---

## 5. Design Decision Log (fill whenever you make a choice)

| # | Decision | Alternatives Considered | Why This Choice | Date/Step |
|:---:|------|------|------|:---:|
| 1 | Registered vs combinational tx_o | Combinational from `case(cstate)` | Registered per PH1 — avoids glitch during state transitions, costs 1 cycle latency | Step 7 |
| 2 | Depth-2 pipeline vs depth-3 | Depth-3 for lower backpressure | Depth-2 sufficient for single-packet-in-flight design. Depth-3 increases latency without benefit | Step 6 |

---

## 6. Residual Risk Register (fill at project completion)

| # | Risk | Likelihood | Impact | Why Not Fixed |
|:---:|------|:---:|:---:|------|
| 1 | Beat counter wraps at 255 beats | Low | Wrong beat_count_o for very long packets | Outside project scope; 8-bit counter sufficient for validation |
| 2 | No timeout on pipeline stall | Low | Permanent hang if downstream never asserts tready | Not needed for directed test; would be added in production |

---

## 7. Final Summary

| Metric | Value |
|--------|-------|
| Total bugs found | <N> |
| Bugs found pre-simulation (Step 2a/5a/7b/8/8c) | <N> |
| Bugs found at simulation (Step 9) | <N> |
| Simulation iterations | <N> |
| Tests passing | <M>/<total> |
| RTL lines | <N> |
| Yosys latch count | 0 / <N> |
| Principle review docs written | <list files> |

---

## Usage Notes

1. **Fill as you go.** Don't reconstruct from memory at the end. The Bug Tracking Table is designed to be appended to with each discovered bug.
2. **Be honest.** A bug found at Step 9 that could have been caught at Step 5a is valuable data — it tells us the checkpoint didn't work. Don't hide it.
3. **Cite the FAIL message verbatim** in the Symptom column. "T3 failed" is useless; `TEST_FAIL T3_back_to_back: pkt2 beat_count=5 expect 1` tells you exactly what was wrong.
4. **Link bugs to principles.** If a bug doesn't map to any of the 6 principles, it may indicate a gap in the principle coverage — also valuable data.
