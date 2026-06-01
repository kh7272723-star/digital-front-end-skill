# NVMe I/O Data Path — Development Log

**Project:** NVMe Phase 3: NVM Read Data Path  
**Date:** 2026-06-01  
**Status:** ALL_TESTS_PASS (3/3) — **但开发过程判定为失败**

---

## 7. Project Retrospective — Why This Process Failed

### 7.1 The Honest Assessment

The simulation passes. 5184/5184 data beats are correct. But the development process was **inefficient and unreliable** — the same class of bug recurred six times, architectural flaws were caught only by user intervention, and debugging was trial-and-error throughout. This is not a sustainable methodology for production RTL development.

### 7.2 Root Causes

#### A. NBA Timing — The Biggest Time Sink

Bugs B2, B3, B4, B5, B6, and B9 are all manifestations of a single root cause: **the agent writes Verilog as sequential code, not as a parallel hardware description.** When two registers are updated via `<=` in the same `always @(posedge clk)` block, their new values take effect simultaneously in the next cycle — but the agent's mental model treats them as sequential updates where "A changes, then B sees A's new value."

Six bugs, each requiring 3-8 iterations of `$display`-driven guesswork to fix. The agent has no systematic method for diagnosing NBA ordering problems.

#### B. Architecture Blindness

The AW-FIFO coupling (B11), monolithic always block (28 registers), and blocking/nonblocking mixing (B12) were all caught by the user, not by the agent's own review process. The agent can write code that compiles and passes tests, but **cannot evaluate whether the architecture is sound** without external feedback.

#### C. Code Quality Drift

C19 (explicit else) and C20 (grouped always blocks) were added mid-session in response to problems found. They should have been in place before any RTL was written. The agent's Step 7 (Generate RTL) and Step 8 (Self-Review) workflows did not enforce these standards.

#### D. Late Synthesis

If Yosys had been run immediately after RTL generation (Step 7), it would have caught the blocking-assignment-in-sequential-block issue (B12) and the local variable declarations (Yosys error) within seconds. Instead, synthesis was deferred to the end and these issues were found only when the user asked.

#### E. No Diagnostic Methodology

When simulation failed, the agent's only tool was `$display`. There was no structured approach to:
1. Identify which module/state is stuck
2. Trace the stuck signal back to its driver
3. Check whether the driver and consumer are in NBA-sync
4. Verify with targeted minimal tests

### 7.3 Skill Gaps Exposed

| # | Gap | Symptom | Severity |
|---|------|---------|:---:|
| G1 | No NBA timing checklist in self-review | B2-B6, B9 — six NBA-ordering bugs, zero caught by Step 8 | **Fatal** |
| G2 | No intra-module coupling check in P4 | B11 — AW dependent on FIFO count, caught by user not agent | **Severe** |
| G3 | No always-block size/complexity gate | 28-register monolithic block, caught by user | Moderate |
| G4 | No pre-synthesis step before self-review | B12 + Yosys errors found hours late | Moderate |
| G5 | No structured debug methodology in sim-loop | Every failure: `$display` scatter-fire, no signal tracing | **Severe** |
| G6 | Coding standards added reactively, not proactively | C19/C20 created mid-session | Moderate |

### 7.4 Fixes Applied (This Session)

| Gap | Fix | File(s) Changed |
|-----|-----|-----------------|
| G1 | NBA timing checklist with code examples | `references/verification/self-review-checklist.md` — new "NBA Ordering Hazards" section |
| G2 | Intra-module coupling questions in P4 | `SKILL.md` Step 2a — added "Intra-Module" sub-check |
| G3 | Always-block size (>8 regs / >50 lines) → split | `references/design/engineering-intuition-checklist.md` — new check item |
| G4 | Step 7b: mandatory pre-synthesis for L1/L2 | `SKILL.md` — new step between Step 7 and Step 8 |
| G5 | Structured failure diagnosis in sim-loop Phase 4 | `references/verification/simulation-loop.md` — new diagnostic flow |
| G6 | Step 7: mandatory read of coding standards before writing RTL | `SKILL.md` Step 7 — added hard requirement |

### 7.5 Deep Reflection

The deepest lesson of this project is not about any specific bug pattern. It is:

> **The agent sees Verilog text. The silicon sees registers and combinational logic updating in parallel. The skill must bridge this gap.**

NBA timing is the most concrete expression of this gap. The agent writes `a <= a + 1; b <= (a == 6);` thinking "a increments, then b checks if a is 6." In hardware, both right-hand sides are evaluated with the old value of `a`, and both updates take effect at the same clock edge. The agent needs to be trained to see this — not as a Verilog language quirk, but as the fundamental nature of synchronous digital circuits.

The fixes above (G1-G6) are structural improvements to the skill's workflow. But the deeper fix — teaching the agent to think in hardware, not in code — requires more fundamental changes to how the skill's design principles and examples are presented. This is a topic for a future skill iteration.

---

## 1. Project Overview

### Scope
Build the NVM I/O data path that exercises the PRP traversal algorithm studied in Phase 2. Read command (OPC=02h) only — Write and Flush deferred to Phase 3b.

### Modules

| Module | Lines | Status | Notes |
|--------|:---:|:---:|------|
| `nvme_cmd_tracker` | ~200 | NEW | 4-slot outstanding command tracker |
| `nvme_prp_walker` | ~350 | NEW | PRP traversal FSM (7 states) + list fetch engine |
| `nvme_read_engine` | ~350 | NEW | NVM read → FWFT FIFO → AXI W data path |
| `nvme_axi_adapter` | ~200 | EXTENDED | 4-source AXI mux with per-burst source tracking |
| `nvme_io_top` | ~300 | NEW | Top-level integration + command demux |
| `nvme_sq_fetch` | 297 | REUSED | Phase 1, I/O SQ fetch |
| `nvme_cq_post` | 253 | REUSED | Phase 1, CQE post |
| `tb_nvme_io` | ~500 | NEW | Testbench + golden reference scoreboard |
| **Total** | **~2450** | | |

### Test Results

| Test | Scenario | Data Size | PRP2 Role | Result |
|:---:|------|:---:|:---:|:---:|
| T1 | NLB=0, single 512B page | 512B | Reserved | ✅ 64/64 |
| T2 | NLB=15, 2-page exact | 8KB | Page | ✅ 1024/1024 |
| T3 | NLB=63, 8-page via list | 32KB | List | ✅ 4096/4096 |

---

## 2. Bug Chronology

### B1: cmd_tracker sequential start deadlock
- **Symptom:** PRP walker stuck in PAGE_TX, read engine never started
- **Root cause:** cmd_tracker FSM issued `prp_start` first, waited for `prp_done`, then issued `rd_start`. But PRP walker's PAGE_TX waits for `page_done` from read engine — which hadn't started. Circular wait.
- **Fix:** Redesigned FSM to pulse both `prp_start` and `rd_start` simultaneously in a single `ISSUE_BOTH` state. Added `prp_done_seen_q` and `rd_done_seen_q` flags to track completion independently.
- **Skill impact:** Multi-engine subsystems need simultaneous start, not sequential. Add to integration-invariants.md.

### B2: WLAST NBA delay — last beat lost
- **Symptom:** AXI W burst sent 63 beats instead of 64; WLAST never asserted
- **Root cause:** `axi_w_last_o <= (w_beat_q == w_burst_len_q)` is NBA-registered. When w_beat_q advances to 63 (the last beat), WLAST was computed on the previous cycle when w_beat_q was 62. The slave sees WLAST=0 for beat 63, then WVALID deasserts. Last beat lost.
- **Fix:** Changed `axi_w_last_o` from registered (`output reg`) to combinational (`assign axi_w_last_o = w_active_q && (w_beat_q == w_burst_len_q)`).
- **Skill impact:** All AXI channel outputs that depend on beat counters should be combinational, not registered. This is a general NBA-timing pattern. Add to bug-pattern-library.md.

### B3: WDATA NBA data lag — 1-beat shift
- **Symptom:** All data shifted by 1 beat. Scoreboard: got=NVM[n], expected=NVM[n+1]
- **Root cause:** `axi_w_data_o <= fifo_rdata` is NBA-registered. When a W handshake fires, the data was sampled on the PREVIOUS cycle from the OLD `fifo_rd_ptr_q`. The `fifo_rd_ptr_q` advances via NBA simultaneously — too late for the data.
- **Fix:** W data pipeline: `w_data_pipe_q` loaded on handshake from `fifo_mem[rd_ptr_q + 1]` (pre-fetch next entry). `axi_w_data_o = w_data_pipe_q` (combinational assign). First beat is pre-loaded on W start from `fifo_rdata`.
- **Skill impact:** FWFT FIFO consumers need pipe register + combinational output. Same NBA pattern as B2. Document in fifo-examples.md.

### B4: W beat counter premature advance
- **Symptom:** First W beat skipped (beat 0 data presented as beat 1)
- **Root cause:** Beat counter advanced on `axi_w_ready_i` alone, without checking `axi_w_valid_o`. On the first W cycle, w_valid is still 0 (NBA not yet taken effect), but w_ready is 1. Beat counter advances to 1 before the first valid beat.
- **Fix:** Gated beat advance with `if (axi_w_valid_o && axi_w_ready_i)` — only advance on actual handshake.

### B5: NVM address duplicate reads
- **Symptom:** First two FIFO entries both contain NVM[0] instead of NVM[0], NVM[1]
- **Root cause:** `nvm_offset_q` advanced on `fifo_wr_en` (data arrival). But `nvm_addr_o` is combinational from `nvm_offset_q`, and `nvm_rd_en_o` fires every cycle. On the first read cycle, rvalid hasn't arrived yet, so `fifo_wr_en=0` — offset stays at 0. Second read also reads addr 0. Duplicate.
- **Fix:** Advance `nvm_offset_q` on `nvm_rd_en_o` (read issue) instead of `fifo_wr_en` (data arrival).

### B6: Last NVM beat FIFO write lost
- **Symptom:** Last beat of each page has X data in FIFO
- **Root cause:** `fifo_wr_en = nvm_rd_en_o && nvm_rvalid_i`. When `page_remain_q` reaches 0, `nvm_rd_en_o` deasserts. But the last read's `nvm_rvalid_i` arrives 1 cycle later — gated by `nvm_rd_en_o=0` → `fifo_wr_en=0`. Last beat lost.
- **Fix:** Changed `fifo_wr_en = nvm_rvalid_i` (unconditionally accept NVM data when valid). NVM only asserts rvalid after a read was issued, so no spurious writes.

### B7: 8-bit overflow in burst_len + 1
- **Symptom:** AW page state never updates; infinite AW bursts
- **Root cause:** `(w_burst_len_q + 8'd1)` overflows when w_burst_len_q=255: 255+1=0 in 8 bits. `aw_page_remain_q -= 0` → never reaches 0 → AW re-issues forever.
- **Fix:** Changed to `(w_burst_len_q + 9'd1)` — 9-bit prevents overflow.

### B8: compute_aw_len internal 8-bit truncation
- **Symptom:** Burst length miscalculation for large pages
- **Root cause:** Internal `reg [7:0] total_beats` can't hold 256 or 512. Truncation produces wrong burst_len.
- **Fix:** All internal regs widened to 9-bit (`reg [8:0]`). Part-select `[7:0]` used when assigning to 8-bit output.

### B9: Page double-accept on completion
- **Symptom:** PAGE accept fires again on the same cycle as PAGE done
- **Root cause:** `page_valid_o` is continuously asserted in S_PAGE_TX state. When `page_ready_o` goes high again (set by page completion), the read_engine re-accepts the same page.
- **Fix:** Added `page_accepted_q` flag. `page_valid_o` only asserted until `page_ready_i` is received, then stays deasserted until `page_done_i` clears the flag.

### B10: AW issued with zero page_remain → infinite loop
- **Symptom:** AW re-issues with len=255 when no data remains
- **Root cause:** `compute_aw_len(0)` returns 255 (underflow from `total_beats-1` with total_beats=0). AW guard didn't check `aw_page_remain_q > 0`.
- **Fix:** Added `aw_page_remain_q > 0` guard to AW issue condition.

### B11: AW coupled to FIFO count — architectural anti-pattern
- **Symptom:** Required FIFO_DEPTH=8192 to pass T3. Any smaller depth caused data loss on multi-page transfers.
- **Root cause:** AW issue condition checked `fifo_count_q >= beats` — coupling protocol control (AW) to data availability (FIFO level). This forced FIFO depth to exceed total transfer size + pipeline latency. The root mechanism: when count equals FIFO depth, `fifo_full` triggers, NVM reads pause, and the count-update-vs-data-write NBA timing creates a window where AW sees "enough data" but the target FIFO slot hasn't been written yet.
- **Fix:** AW fires independently from page info alone — checks only `page_active_q && !aw_active_q && aw_page_remain_q > 0`. WVALID gated by `w_active_q && !fifo_empty` — data pacing handled by FIFO empty check. Result: FIFO_DEPTH reduced from 8192 → 64 (128× reduction). T3 simulation time reduced from 8219 → 5595 cycles (32% faster).
- **Skill impact:** Protocol controllers (AW) must not depend on data-path state (FIFO count). Data pacing belongs on the data channel (W gated by empty), not the control channel. This is an instance of P4 (Independence) at the intra-module level.

### B12: Blocking assignments in sequential block (code style)
- **Symptom:** `reg [7:0] blen; blen = compute_aw_len(...)` inside `always @(posedge clk_i)`
- **Root cause:** Computation logic mixed into sequential block using blocking assignments. Valid Verilog but violates coding standard C20 and obscures the sequential/combinational boundary.
- **Fix:** Moved all `compute_aw_len` logic to a separate `always @(*)` combinational block. AW controller now uses combinational `aw_burst_len`, `aw_burst_beats`, `aw_burst_addr` wires.

### B13: AXI adapter R-channel routing corruption (dormant)
- **Symptom:** (Not triggered in Phase 3 — only one AR source active)
- **Root cause:** `ar_source_s2_q` single bit can be overwritten if a second AR is accepted before the first AR's R burst completes. Similarly `aw_source_s3_q` for AW/W.
- **Fix:** Added `ar_busy_q` / `aw_busy_q` flags implementing one-outstanding-per-channel discipline. New AR/AW blocked while burst in flight. Source tracking bit then guaranteed stable for the entire R/W burst duration.

---

## 3. Skill Iterations Triggered

### 3.1 Coding Standards (this session)

| Change | File | Trigger |
|--------|------|---------|
| C19 (M): explicit else in sequential blocks | `rtl-coding-standards.md` | User's导师practice — every register assigned in all code paths |
| C20 (S): group registers by function | `rtl-coding-standards.md` | Monolithic always block in read_engine — unreadable, synthesis-unfriendly |
| Removed array encoding ban | `rtl-coding-standards.md` | User feedback — unavoidable for FIFO/RAM |
| Translated to English | `rtl-coding-standards.md`, `naming-guidelines.md` | User feedback — English more effective for HDL docs |
| Unified naming: `cstate`/`nstate`, `_r` delay, `inst_` prefix | `naming-guidelines.md`, `fsm-examples.md` | User's coding standards — single source of truth, no conflicts |

### 3.2 Bug Patterns Discovered

| Pattern | Description | First Seen |
|---------|-------------|:---:|
| NBA-data-lag | Registered AXI outputs lag 1 beat behind beat counters. Fix: combinational `assign`. | B2, B3 |
| addr-advance-on-issue | Address counters must advance on read-issue, not data-arrival, to avoid duplicate reads. | B5 |
| data-arrive-after-enable | Last data beat arrives after `nvm_rd_en_o=0`. Fix: don't gate `fifo_wr_en` on rd_en. | B6 |
| burst-len-overflow | 8-bit `burst_len + 1` overflows at 255. Fix: use 9-bit constant. | B7 |
| page-reaccept | Continuous `page_valid` causes re-accept on `page_ready` re-assertion. Fix: accepted flag. | B9 |
| AW-FIFO-coupling | Protocol control checks data-path FIFO level → FIFO depth tied to transfer size. Fix: AW independent, W gated by empty. | B11 |

### 3.3 Skill Gap Analysis

| Gap | Severity | Description |
|-----|:---:|------|
| Multi-module start sequencing | High | cmd_tracker must start both engines simultaneously. Skill should have a pattern for this. |
| NBA-aware AXI output coding | High | WLAST/WDATA must be combinational, not registered. Skill's AXI guidelines should explicitly state this. |
| FIFO depth sizing formula | Medium | `depth ≥ 2 × pipeline_latency` is sufficient when AW is decoupled. Skill should provide this formula. |
| Page-based streaming interface | Medium | PRP walker → read_engine page handshake needed `page_accepted` flag. Skill's handshake patterns only cover valid/ready, not valid/ready + done. |

---

## 4. Golden Reference Methodology Validation

### Strategy Used
**Strategy D — Data Integrity Scoreboard.** NVM SRAM pre-loaded with address-describing pattern (`nvm_sram[i] = {8{i[7:0]}}`). Expected host memory content computed independently from SLBA, NLB, and page addresses — no DUT code was read to derive expected values.

### Scoreboard Operation
1. `compute_golden()` runs before each test, maps NVM data to expected host memory addresses
2. AXI W slave captures observed writes to `sb_observed[]` array
3. After CQE post, `verify_sb()` compares observed vs expected
4. CQE area (0x2000-0x2FFF) excluded from scoreboard to avoid false positives from CQE writes

### Results
- T1: 64/64 beats match — zero false positives, zero false negatives
- T2: 1024/1024 beats match — PRP2=Page role validated
- T3: 4096/4096 beats match — PRP2=List role validated, including list chain traversal

---

## 5. Final Architecture Quality Assessment

### Strengths
- PRP traversal algorithm correctly implements NVMe Base Spec 2.3 §4.3
- Three PRP2 roles (Reserved, Page, List) all verified
- AW/W independent controllers (P13 compliance)
- WVALID stability (P12 compliance) — holds for entire burst
- FWFT FIFO (F1 compliance) — combinational read output
- 4KB boundary splitting (DP4 compliance)
- CQE Phase Tag = 1 (Phase 1 Bug #5 regression fix verified)

### Known Limitations
- Single I/O queue only (Phase 3b: multi-queue)
- Read-only (Phase 3b: Write path)
- No MSI-X interrupt generation
- PRP walker FSM merges page handshake + list fetch — works but could be split for clarity
- Testbench uses direct command injection (sq_fetch bypassed) for bringup speed
- `nvme_io_top` assembly is manual — `inst_` prefix and FSM/datapath split deferred to Phase 4

---

## 6. Key Metrics

| Metric | Before | After | Delta |
|--------|:---:|:---:|:---:|
| RTL lines (new) | — | ~1350 | — |
| RTL lines (total) | — | ~2450 | — |
| FIFO depth | 64 (pipeline) | — | vs 8192 (broken approach) |
| T3 simulation cycles | — | 5595 | — |
| Bugs found & fixed | — | 13 | — |
| Skill standards updated | — | 6 files | — |
| Test pass rate | — | 3/3 (100%) | — |
| Golden ref data integrity | — | 5184/5184 (100%) | — |
