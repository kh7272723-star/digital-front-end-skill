# Design Principles for Digital Front-End RTL

## Purpose

This document defines 6 core design principles that an experienced digital front-end engineer applies unconsciously. Each principle generates a family of specific bug patterns — the principle is the root, the patterns are branches.

**How to use:** After generating RTL (Step 7) and before structural self-review (Step 8), read each principle and its active-search questions. For each question, scan the design and report findings. Then proceed to Step 8 (structural checklist) and Step 8c (principle-driven review).

**Relationship to bug-pattern-library.md:** The 57 patterns in the bug-pattern library are specific instances of these 6 principles. When you find a violation during principle-driven review, map it to the nearest pattern ID. When you encounter a bug that doesn't match any existing pattern, derive a new pattern from the relevant principle.

---

## Principle 1: Every Signal Has a Timing Contract

**Core insight:** Before you write code, you must know when each signal is valid and when it is sampled. Every signal falls into exactly one of three categories: **pulse** (valid 1 cycle), **level** (sustained until condition changes), or **registered** (delayed 1 cycle from source). If you can't classify a signal, you don't understand your own design.

**Why this matters:** The most common RTL bugs are not logic errors — they are timing mismatches. A consumer samples a pulse before it fires. A level signal is read as if it were registered. A registered output's 1-cycle latency is forgotten by the testbench. These are all failures of timing contract discipline.

**Active-search questions (ask for every module):**

1. For each output port: is it pulse, level, or registered? Document the answer in the interface contract.
2. For each **pulse** output: does it use transition detection (`prev_state != state_q`) or state comparison (`state_q == TARGET`)? State comparison is fragile — it fires on reset, fires in IDLE, and stays asserted. See LP7.
3. For each **level** output: can the consumer sample it at any time, or only during a specific phase? If the consumer might miss it, should it be sticky?
4. For each **registered** output: does the testbench add 1 extra cycle after ACCESS before sampling? See P18, F2, BUG-6.
5. For each **valid/ready handshake**: does VALID hold until READY? Is the payload stable while VALID=1? See H1, H8, P11.
6. For each **AXI W channel**: does WVALID hold for the entire burst (no mid-burst deassertion)? See P12, IHI0022E A3.3.1.

**Covered patterns:** H1, H2, H8, LP7, P11, P12, P18, F1, F2, BUG-6, completion signal style

---

## Principle 2: Every State Machine Must Find Its Way Home

**Core insight:** An FSM must always be able to return to IDLE. From EVERY state, there must be a path out. If the request deasserts while the FSM is in an intermediate state (waiting for bus idle, waiting for FIFO data, waiting for acknowledge), the FSM must abort and return to IDLE. An FSM that can get stuck is a time bomb.

**Why this matters:** Real systems have noise, timeouts, and software bugs. A request signal might be a pulse that's long gone by the time the FSM reaches S_CHECK_IDLE. A bus that was busy might become idle, then busy again. Without abort paths, the FSM locks up and requires a full system reset.

**Active-search questions (ask for every FSM):**

1. Can this FSM get stuck? For every non-IDLE state: what guarantees the transition condition will eventually be true?
2. For states entered on a **request signal**: if the request deasserts, is there an abort path back to IDLE? See SM3.
3. After reset, is the FSM in IDLE with all outputs at safe defaults? Does any pulse output fire spuriously on reset release? See LP7.
4. Are all multi-bit register updates OUTSIDE the FSM combinational block, gated by single-bit enables from the FSM? See SM1, SM2.
5. Does the combinational block have **default assignments before the case statement** (prevents latch inference)? See C3, E2.
6. Is there a **default case** that recovers to IDLE? See C2.
7. Are all state transitions intentional and sequential — no jumps that skip required intermediate states? See LP3.

**Covered patterns:** SM1, SM2, SM3, C2, C3, E2, LP3, LP7

---

## Principle 3: Every Register Has a Known Value at Every Moment

**Core insight:** At every clock cycle, you must be able to state what value every register and memory element holds. After reset, every register must have an explicit value. During operation, no register should ever be 'x' or 'z'. Memories that are not reset must have a documented initialization strategy. Combinational blocks must assign a value to every output in every branch.

**Why this matters:** Uninitialized registers and memories produce 'x' in simulation, which propagates through the design and makes debugging impossible. In silicon, uninitialized state means random values — the chip might work on one power-up and fail on the next. These bugs are notoriously hard to reproduce and debug.

**Active-search questions (ask for every module):**

1. After reset, what value does **every** register hold? Scan the reset branch of every `always @(posedge clk_i)` block.
2. Are there any register arrays or inferred memories that are **not reset**? Document the initialization strategy (software init, valid bit, reset loop). See BUG-4.
3. Does every `always @(*)` block assign a value to every output **before** conditional branches? See E2.
4. Is every net driven by **exactly one** source? No multiply-driven wires, no mixing `assign` with `always` on the same signal. See E1, BUG-5.
5. Are all width mismatches handled with **explicit part-selects**? No implicit truncation. See E3.
6. Are blocking assignments (`=`) used in combinational blocks and nonblocking (`<=`) in sequential blocks — **never mixed** in the same block? See E4.
7. Every `.v` file starts with `` `default_nettype none `` to catch implicit wire declarations. See E8.

**Covered patterns:** E1-E8, BUG-4, BUG-5, DP4

---

## Principle 4: Independent Things Must Stay Independent

**Core insight:** The AXI spec says channels are independent. Clock domains are independent. Read and write command paths are independent. When your RTL couples independent things — e.g., blocking AW channel on B response, or sharing a single FSM for read and write — you create unnecessary dependencies that violate protocol intent and cause deadlocks.

**Why this matters:** Coupling independent channels/paths/domains works in simple test cases but fails under real traffic with outstanding transactions, backpressure, and concurrent reads and writes. The spec authors separated these channels for a reason — respect their intent.

**Active-search questions (ask for every AXI module and CDC design):**

1. Are AXI **AW, W, B channels** independently controlled (separate valid/ready)? See P13.
2. Are **read and write command paths** decoupled? Can a read be issued while a write is in progress? See read/write decoupling.
3. For each **clock domain crossing**: is the synchronizer appropriate for the signal type? Multi-bit → gray code or handshake. Single-bit → 2FF. Gated domain → pulse synchronizer. See LP4, CDC guidelines.
4. Is there any **combinational path** across a clock domain boundary? This is always wrong.
5. Does the **outstanding transaction counter** saturate without blocking drain? See P9.
6. Are **completion signals** derived from protocol responses (BVALID for writes, RVALID+RLAST for reads), not from internal pipeline states? See P4.

**Covered patterns:** P4, P5, P9, P13, LP4, CDC patterns, read/write decoupling, channel separation

---

## Principle 5: The Physical World Always Wins

**Core insight:** RTL is not abstract logic — it becomes physical gates, wires, and flip-flops. Every register burns power. Every combinational path has delay. Every wire has resistance and capacitance. Write RTL that anticipates physical implementation: register your I/O, isolate idle logic, gate your clocks, group your buses.

**Why this matters:** RTL that simulates correctly but synthesizes to a design that can't close timing, burns too much power, or can't be routed is not "working" RTL. Physical constraints are not an afterthought — they must influence RTL structure from the start.

**Active-search questions (ask for every module):**

1. **Power:** Are isolation enables asserted BEFORE power-off? See LP1. Is retention save complete before power-off and restore after power-on? See LP2. Is clock gating done with enables (not gated clock primitives)? See LP5.
2. **Timing:** Are module I/O registered to create clean partition boundaries? See PH1. Do high-fanout (>50) signals have `max_fanout` attributes? See PH2. Are long combinational paths pipelined?
3. **Area:** Are wide (>32-bit) combinational paths isolated when unused? See LP6. Are resource-sharing opportunities identified?
4. **Placement:** Are memories in the same hierarchy as their consumers? See PH3. Are bus signals grouped by channel in port declarations? See PH4.
5. **DVFS:** Is frequency change gated by bus idle? See LP5. Is operand isolation applied during frequency transitions? See LP6.

**Covered patterns:** LP1, LP2, LP5, LP6, PH1-PH4

---

## Principle 6: Boundaries Are Where Bugs Hide

**Core insight:** Module boundaries, clock boundaries, power boundaries, protocol boundaries — these are the interfaces where assumptions diverge. Module A assumes a pulse; Module B expects a level. Producer drives 8 bits; consumer expects 16. Every boundary needs an explicit contract that covers: port widths, signal types (pulse/level/registered), timing, error handling, and reset behavior.

**Why this matters:** In multi-module designs, the most common integration bugs are interface mismatches. Sub-agents make different assumptions about the same signal. A port width derived from parameter X in one module doesn't match parameter Y in another. Without explicit contracts, these mismatches are found only at integration time — when they're most expensive to fix.

**Active-search questions (ask for every module boundary):**

1. Does every module boundary have an **interface contract** that specifies: port widths, signal types (pulse/level/registered), handshake rules, reset behavior? See interface-contract-template.md.
2. Do producer and consumer **port widths** match exactly? Are they derived from the same parameter?
3. Are **all errors** propagated from sub-modules to a completion/error output? See DP5.
4. Is the **completion signal** style (pulse vs level) consistent across the integration chain?
5. For **multi-module pipelines**: is the module ordering defined? Does each module know when the previous module is done?
6. Are there any **dead ports** (declared but unused) or **dead modules** (instantiated but output unused)?
7. Does the **reset** clear all valid-like outputs across all modules in the chain?

**Covered patterns:** DP5, interface contracts, integration invariants, multi-module handshake, BUG-7

---

## Principle-to-Pattern Mapping

| Principle | Patterns Covered |
|-----------|-----------------|
| P1: Timing Contract | H1, H2, H8, LP7, P11, P12, P18, F1, F2, completion signal |
| P2: FSM Safety | SM1, SM2, SM3, C2, C3, E2, LP3, LP7 |
| P3: Known Values | E1-E8, BUG-4, BUG-5, DP4 |
| P4: Independence | P4, P5, P9, P13, LP4, CDC, channel separation |
| P5: Physical World | LP1, LP2, LP5, LP6, PH1-PH4 |
| P6: Boundaries | DP5, interface contracts, integration invariants, BUG-7 |

Note: some patterns serve multiple principles. LP7 (pulse transition detection) is both a timing contract issue (P1) and an FSM safety issue (P2) — this is expected. The principles overlap because real bugs don't respect clean category boundaries.

## From Principles to New Patterns

When you discover a bug that doesn't match any existing pattern:

1. Identify which principle it violates (there may be more than one)
2. Check if the violation is a **new instance** of the principle (→ add a new pattern under that principle) or a **new principle entirely** (→ this is rare; discuss first)
3. Write the new pattern in bug-pattern-library.md with the principle tag in its header

**Example:** The LP7 discovery path:
- Bug: wake_ack fired on reset → violated P1 (pulse timing contract) and P2 (FSM output after reset)
- Classification: new instance, not new principle
- Action: added LP7 pattern, tagged P1+P2

## How This Differs from the Old Approach

**Old approach (flat patterns only):**
1. Generate RTL
2. Scan against 57 patterns one by one
3. Miss anything that doesn't exactly match a pattern
4. Bug found → add pattern #58

**New approach (principles + patterns):**
1. Generate RTL
2. Read 6 principles + active-search questions
3. For each principle, scan the design holistically — does anything "feel wrong"?
4. Match any "wrong" findings to specific patterns
5. If no pattern matches → potential new principle instance → add pattern
6. The principles help you find bugs BEFORE they become patterns

The principles are not a replacement for patterns — they are a **lens** that makes patterns visible before you know what to look for.
