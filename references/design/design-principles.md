# Design Principles for Digital Front-End RTL

## Purpose

This document defines 6 core design principles that an experienced digital front-end engineer applies unconsciously. Each principle generates a family of specific bug patterns — the principle is the root, the patterns are branches.

**How to use:** The 6 principles are reviewed at three checkpoints during the design flow — not all at once at the end. This distributes the review burden and catches issues at the cheapest fix point:

| Checkpoint | Principles | Why this timing |
|------------|-----------|-----------------|
| **Step 2a** (after timing contract) | P4 Independence, P6 Boundaries | Architecture coupling and boundary mismatches are cheapest to fix before any RTL exists |
| **Step 5a** (after cycle trace) | P1 Timing Contract, P2 FSM Safety | The cycle trace is the best place to verify signal timing and FSM behavior — before code |
| **Step 8c** (after RTL generation) | P3 Known Values, P5a Output Discipline | These require actual RTL code to review: register initialization, output driving |
| **Step 8c extra** (L2/ASIC only) | P5b Physical Implementation | Power gating, placement, DVFS — only for complex/ASIC designs |

**Complexity gate:** Not all checkpoints apply to all projects. See "When to skip/lite" in each principle:
- **L0 (Trivial):** ≤200 lines, ≤8 FSM states, linear flow → Skip 2a, Skip 5a. At 8c: P3 only.
- **L1 (Leaf):** 200-500 lines, or nonlinear FSM, or dual protocol → P1-P6 all applicable. FAST mode (1-2 questions each). P5b skipped.
- **L2 (Subsystem):** >500 lines, or multi-module, or multi-clock → Full P1-P6 including P5b. 3-5 questions each.

For each checkpoint, do NOT treat this document as a checklist to fill out. Instead:

1. Read each principle and its active-search questions.
2. For each principle, look at YOUR specific RTL code — your signal names, your FSM states, your module boundaries.
3. Generate 3-5 specific questions that target YOUR design. (Example: not "is every pulse using transition detection?" but "done_o is set in S_DONE state of pattern_gen_fsm — if continuous=1 and S_DONE transitions to S_GENERATE, is done_o still exactly 1 cycle wide?")
4. Answer each question by tracing actual signal paths through your code.
5. Fix everything that doesn't pass your own scrutiny.
6. Then proceed to Step 8 (structural checklist) and Step 8c (principle-driven self-interrogation in SKILL.md).

The active-search questions below are **prompts to help you generate your own questions** — they are not a prefabricated checklist. A YES/NO answer to a generic question is worthless. A concrete answer that references your specific signals and traces their cycle-level behavior is valuable.

**Relationship to bug-pattern-library.md:** The 57 patterns in the bug-pattern library are specific instances of these 6 principles. When you find a violation during principle-driven review, map it to the nearest pattern ID. When you encounter a bug that doesn't match any existing pattern, derive a new pattern from the relevant principle.

---

## Principle 1: Every Signal Has a Timing Contract

**Core insight:** Before you write code, you must know when each signal is valid and when it is sampled. Every signal falls into exactly one of three categories: **pulse** (valid 1 cycle), **level** (sustained until condition changes), or **registered** (delayed 1 cycle from source). If you can't classify a signal, you don't understand your own design.

**Why this matters:** The most common RTL bugs are not logic errors — they are timing mismatches. A consumer samples a pulse before it fires. A level signal is read as if it were registered. A registered output's 1-cycle latency is forgotten by the testbench. These are all failures of timing contract discipline.

**When to skip/lite:**
- Always applicable for L1/L2. Even the simplest UART needs signal classification (pulse vs level vs registered).
- For L0: signal classification is done inline during contract writing — no separate P1 review needed.

**Active-search questions (ask for every module):**

1. For each output port: is it pulse, level, or registered? Document the answer in the interface contract.
2. For each **pulse** output: does it use transition detection (`prev_state != state_q`) or state comparison (`state_q == TARGET`)? State comparison is fragile — it fires on reset, fires in IDLE, and stays asserted. See LP7.
3. For each **level** output: can the consumer sample it at any time, or only during a specific phase? If the consumer might miss it, should it be sticky?
4. For each **registered** output: does the testbench add 1 extra cycle after ACCESS before sampling? See P18, F2, BUG-6.
5. For each **valid/ready handshake**: does VALID hold until READY? Is the payload stable while VALID=1? See H1, H8, P11.
6. For each **AXI W channel**: is the W data mode declared (continuous/full-burst-buffered or elastic/per-beat buffered)? Does each presented beat keep `WVALID`/`WDATA`/`WSTRB`/`WLAST` stable until `WREADY`? See P12, IHI 0022 A3.3.

**Covered patterns:** H1, H2, H8, LP7, P11, P12, P18, F1, F2, BUG-6, completion signal style

---

## Principle 2: Every State Machine Must Find Its Way Home

**Core insight:** An FSM must always be able to return to IDLE. From EVERY state, there must be a path out. If the request deasserts while the FSM is in an intermediate state (waiting for bus idle, waiting for FIFO data, waiting for acknowledge), the FSM must abort and return to IDLE. An FSM that can get stuck is a time bomb.

**Why this matters:** Real systems have noise, timeouts, and software bugs. A request signal might be a pulse that's long gone by the time the FSM reaches S_CHECK_IDLE. A bus that was busy might become idle, then busy again. Without abort paths, the FSM locks up and requires a full system reset.

**When to skip/lite:**
- **LITE (linear FSM):** If all states transition only on counter completion (baud_tick, DIVIDER overflow) and there are no external request/wait signals in intermediate states, skip abort-path analysis (Q2, Q6). The FSM can't get stuck because counters always complete.
- **FULL (nonlinear FSM):** If any state waits on an external signal (request, busy, ack, data_available, fifo_empty), do all 7 questions. These are the FSMs that can deadlock.
- **No FSM:** If the design uses beat counters instead of explicit FSM states, skip P2 entirely.

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

**When to skip/lite:**
- **Always applicable (all levels).** P3 is the one principle that consistently catches bugs even in simple modules (R8 Agent B's name mismatch was found during P3 register audit). Even L0 projects must do P3.
- For L0: inline 1-paragraph register audit (list all registers + reset values). No separate file needed.
- For L1/L2: full register/memory scan with signal tracing.

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

**When to skip:**
- **SKIP if:** single channel, single clock domain, single protocol, no concurrent operations. Example: UART TX only (no RX), simple APB register block, single-direction SPI master.
- **LITE if:** dual-channel but single-direction (e.g., UART TX+RX with independent FSMs already).
- **FULL if:** multi-channel AXI, multi-clock CDC, concurrent read/write, or any design where one channel's backpressure could block another.

**Active-search questions (ask protocol-independent first, then protocol-specific):**

*Protocol-independent (always ask first):*
1. What **independent concerns** exist in this design? List them: data vs control, TX vs RX, protocol engine vs configuration interface, multi-channel. Are they actually decoupled in the architecture?
2. Can a transaction on one concern **accidentally consume or corrupt** data on another? (R1: APB config read corrupted AXI-Stream data because tready was shared.)

*Protocol-specific (ask the ones that match your interfaces):*
3. **[AXI]** Are AW, W, B channels independently controlled (separate valid/ready)? See P13.
4. **[AXI]** Are read and write command paths decoupled? Can a read be issued while a write is in progress?
5. **[AXI]** Are completion signals derived from protocol responses (BVALID for writes, RVALID+RLAST for reads), not from internal pipeline states? See P4.
6. **[AXI]** Does the outstanding transaction counter saturate without blocking drain? See P9.
7. **[Serial (I2C/UART/SPI)]** Is TX independent of RX? Can a config register change corrupt an ongoing transfer?
8. **[Serial]** Does the configuration interface (APB/AXI-Lite) share state with the protocol engine? Can a register write during an active transfer cause data corruption?
9. **[CDC]** For each clock domain crossing: is the synchronizer appropriate? Multi-bit → gray code or handshake. Single-bit → 2FF. No combinational paths across domains. See LP4, CDC guidelines.

**Covered patterns:** P4, P5, P9, P13, LP4, CDC patterns, read/write decoupling, channel separation

---

## Principle 5a: Every Output Respects the Next Engineer

**Core insight:** When another engineer (or your future self) instantiates your module, they should never have to guess when to sample your outputs. Module boundary outputs driven from registered state are predictable — they change exactly on the clock edge. Combinational outputs from `case(state_q)` create glitch windows during FSM transitions and force the consumer to understand your internal timing. Registered outputs cost 1 cycle of latency and buy a clean contract.

**Why this matters:** R8 experiment: Agent A's UART TX drove `tx_o` combinationally from `case(state_q)`. The design simulated correctly but would create a glitch window on every FSM transition, and the testbench had to carefully time sampling around the FSM state. Agent B's registered output had 1 cycle more latency but zero timing ambiguity. Four rounds of A/B experiments showed that agents with combinational boundary outputs always mark P5 as PASS because the original P5's LP/PH questions don't target this issue.

**When to skip/lite:**
- **L0 (Trivial, ≤200 lines):** SKIP P5a entirely. Single-bit outputs with simple state machines don't have meaningful output discipline issues.
- **L1/L2:** Full P5a review.

**Active-search questions:**

1. Are all module boundary outputs driven from registers (not combinational `case(state_q)` or `assign` from FSM state)? Combinational outputs glitch during state transitions. See PH1.
2. Are internal counters gated by state (not free-running when idle)? A free-running baud counter toggles on every cycle, burning power and potentially wrapping unexpectedly.
3. Are bit widths derived from `$clog2` or parameters (not hardcoded)? Hardcoded widths create silent bugs when parameters change. See A3.
4. Is the terminal count for counters correct? A counter that counts DIVIDER cycles needs `cnt == DIVIDER-1` (0-indexed), not `cnt == DIVIDER`.
5. Do pulse outputs stay exactly 1 cycle wide in all FSM paths? Use transition detection, not state comparison. See LP7, BUG-1.

**Covered patterns:** PH1, PH2, LP7, BUG-1, counter wrap, baud timing

---

## Principle 5b: The Physical World Always Wins

**Core insight:** RTL is not abstract logic — it becomes physical gates, wires, and flip-flops. Every register burns power. Every combinational path has delay. Every wire has resistance and capacitance. For designs targeting ASIC or timing-critical FPGA, physical constraints must influence RTL structure from the start.

**Why this matters:** RTL that simulates correctly but synthesizes to a design that can't close timing, burns too much power, or can't be routed is not "working" RTL.

**When to skip:**
- **L0/L1:** SKIP. These modules are too small for physical implementation to be a concern.
- **FPGA target:** SKIP PH2-PH4 (placement constraints don't apply).
- **L2 / ASIC target / power-managed:** Full P5b review.

**Active-search questions (L2/ASIC only):**

1. **Power:** Are isolation enables asserted BEFORE power-off? See LP1. Is retention save complete before power-off and restore after power-on? See LP2. Is clock gating done with enables (not gated clock primitives)? See LP5.
2. **Timing:** Do high-fanout (>50) signals have `max_fanout` attributes? See PH2. Are long combinational paths pipelined?
3. **Area:** Are wide (>32-bit) combinational paths isolated when unused? See LP6. Are resource-sharing opportunities identified?
4. **Placement:** Are memories in the same hierarchy as their consumers? See PH3. Are bus signals grouped by channel in port declarations? See PH4.
5. **DVFS:** Is frequency change gated by bus idle? See LP5. Is operand isolation applied during frequency transitions? See LP6.

**Covered patterns:** LP1, LP2, LP5, LP6, PH2-PH4

---

## Principle 6: Boundaries Are Where Bugs Hide

**Core insight:** Module boundaries, clock boundaries, power boundaries, protocol boundaries — these are the interfaces where assumptions diverge. Module A assumes a pulse; Module B expects a level. Producer drives 8 bits; consumer expects 16. Every boundary needs an explicit contract that covers: port widths, signal types (pulse/level/registered), timing, error handling, and reset behavior.

**Why this matters:** In multi-module designs, the most common integration bugs are interface mismatches. Sub-agents make different assumptions about the same signal. A port width derived from parameter X in one module doesn't match parameter Y in another. Without explicit contracts, these mismatches are found only at integration time — when they're most expensive to fix.

**When to skip/lite:**
- **LITE (single module, APB or simple bus):** Check port widths and PSLVERR handling. Skip integration-chain questions (Q5, Q6).
- **FULL (multi-module, multi-agent):** All 7 questions. Interface contracts must be written and cross-checked before RTL.

**Active-search questions (ask protocol-independent first):**

*Protocol-independent (always ask first):*
1. Does this design have a **module boundary** that another engineer (or sub-agent) needs to interface with? If yes: is there an explicit contract (port widths, signal types, handshake rules, reset behavior)?
2. Are all **ports actually used** in the module body? No dead ports declared but unreferenced.

*Boundary-specific:*
3. Do producer and consumer **port widths** match exactly? Are they derived from the same parameter? See interface-contract-template.md.
4. Are **all errors** propagated from sub-modules to a completion/error output? See DP5.
5. Is the **completion signal** style (pulse vs level) consistent across the integration chain? See timing-contract-template.md.
6. For **multi-module pipelines**: is the module ordering defined? Does each module know when the previous module is done?
7. Does the **reset** clear all valid-like outputs across all modules in the chain? See R2.
8. **[APB/AXI-Lite]** Do all register addresses decode correctly with no aliasing? Is PSLVERR asserted on invalid addresses?
9. **[AXI-Stream]** Do TKEEP/TLAST propagate correctly through the pipeline? Are packet boundaries preserved?
10. **[Serial (I2C/UART/SPI)]** Is the bus timing contract clear? Who drives SDA during ACK? When does TX transition from idle to active?

**Covered patterns:** DP5, interface contracts, integration invariants, multi-module handshake, BUG-7

---

## Principle-to-Pattern Mapping

| Principle | Patterns Covered |
|-----------|-----------------|
| P1: Timing Contract | H1, H2, H8, LP7, P11, P12, P18, F1, F2, completion signal |
| P2: FSM Safety | SM1, SM2, SM3, C2, C3, E2, LP3, LP7 |
| P3: Known Values | E1-E8, BUG-4, BUG-5, DP4 |
| P4: Independence | P4, P5, P9, P13, LP4, CDC, channel separation |
| P5a: Output Discipline | PH1, LP7, BUG-1, counter wrap, baud timing, glitch prevention |
| P5b: Physical Implementation | LP1, LP2, LP5, LP6, PH2-PH4 |
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
