# Low-Power SoC Subsystem — Skill Gap Analysis

## Project Summary

| Metric | Value |
|--------|-------|
| RTL Modules | 6 (psm, dvfs_ctrl, clk_gate_ctrl, phys_aware_datapath, apb_regs, soc_top) |
| Total RTL Lines | ~1,500 |
| Sub-agents | 5 (all completed, self-review PASS) |
| Tests | 28 |
| Passed | 24 (85.7%) |
| Failed | 4 (all real RTL bugs, not testbench errors) |
| Yosys Latches | 0 |
| Yosys Cells | 25,496 (phys_aware: 24,732 from 256x32 SRAM) |

## RTL Bugs Discovered (7)

### BUG-1: PSM wake_ack_o spuriously fires on reset [LP-NEW]
**Module:** psm.v
**Symptom:** After reset release, `wake_ack_o` asserts and stays high because `state_q==S_ON && wait_cnt_q==0` is true.
**Root cause:** wake_ack_o condition is state-based (`state_q==S_ON && wait_cnt_q==0`) instead of transition-based (previous_state==S_RESTORE → current_state==S_ON).
**Impact:** apb_regs psm_status_q shows busy bit stuck at 1 after reset.
**Fix:** Add transition detection: `if (state_q == S_ON && prev_state == S_RESTORE) wake_ack_o <= 1'b1;`
**Skill gap:** Low-power guidelines §4 lacks "pulse output must use transition detection, not state comparison" rule.

### BUG-2: DVFS freq_req is level, not pulse [LP5-RELATED]
**Module:** dvfs_ctrl.v (in apb_regs, dvfs_freq_req_o = dvfs_ctrl_q[4])
**Symptom:** After software writes freq_req=1, DVFS FSM runs once but freq_req stays high, causing infinite FSM loops.
**Root cause:** CSR bit is level-held. PSM sleep_req is correctly implemented as pulse (wr_do & pwdata[0]), but DVFS freq_req is wired directly from CSR register bit.
**Impact:** DVFS FSM keeps cycling; busy_o oscillates; blocks PSM sleep.
**Fix:** Either auto-clear dvfs_ctrl_q[4] after FSM accepts the request, or make it a pulse in apb_regs.
**Skill gap:** Interface contract template lacks mandatory "signal type" field (pulse/level/registered).

### BUG-3: DVFS FSM no abort path from S_CHECK_IDLE [LP5-GAP]
**Module:** dvfs_ctrl.v
**Symptom:** If freq_req_i deasserts while FSM is in S_CHECK_IDLE (waiting for bus_idle), the FSM is permanently stuck.
**Root cause:** S_CHECK_IDLE state only transitions on `bus_idle_i==1`; no path back to S_IDLE on `freq_req_i==0`.
**Impact:** busy_o stays high forever; PSM sleep blocked; system requires reset.
**Fix:** Add abort condition: `if (!freq_req_i) state_d = S_IDLE;` in S_CHECK_IDLE.
**Skill gap:** Bug-pattern-library lacks "FSM no abort on request deassertion" pattern.

### BUG-4: phys_aware_datapath SRAM uninitialized → 'x' propagation [PH-RELATED]
**Module:** phys_aware_datapath.v
**Symptom:** MAC computation returns 'x' because SRAM (`reg [31:0] mem_q [0:255]`) is not reset.
**Root cause:** Agent intentionally skipped SRAM reset (256 entries "too large"), but first MAC read accesses uninitialized SRAM entries.
**Impact:** First MAC computation always returns 'x'; all subsequent computations using accumulated state also corrupt.
**Fix:** Either: (a) add explicit SRAM initialization loop on reset (acceptable for FPGA, not for ASIC), (b) add `valid` bit per SRAM entry with first-use check, or (c) document that software must write SRAM before first MAC.
**Skill gap:** Physical-awareness guidelines §2 (Macro placement) lacks "SRAM/register-file initialization" guidance.

### BUG-5: clk_gate_ctrl mixed reg/assign driver [YOSYS-WARN]
**Module:** clk_gate_ctrl.v
**Symptom:** Yosys warning: "reg '\domain_clk_en_o' is assigned in a continuous assignment at line 148".
**Root cause:** `domain_clk_en_o` declared as `output reg [3:0]` in port list but driven by `assign domain_clk_en_o = domain_clk_en_q;` (continuous assignment on reg type).
**Fix:** Change to `output wire [3:0] domain_clk_en_o` in port declaration.
**Skill gap:** coding-guidelines.md E1 already covers this (one driver per signal), but the agent's self-review missed it. The self-review checklist doesn't explicitly check for "output reg driven by assign".

### BUG-6: APB registered PRDATA latency undocumented [GAP-GR3-REGRESSION]
**Module:** apb_regs.v + testbench
**Symptom:** Testbench captures prdata one cycle too early, gets stale value.
**Root cause:** `prdata_o = prdata_q` (registered) adds 1 cycle of latency. Testbench `apb_read` task captured data on the same cycle as ACCESS, before prdata_q updates.
**Fix:** Testbench must wait 1 extra cycle after ACCESS before capturing prdata.
**Skill gap:** This is a regression of GAP-GR3 from the golden reference validation (2026-05-28). The simulation-loop.md does not mention this testbench timing requirement. The verification guidance lacks "registered output needs N+1 cycle sampling."

### BUG-7: CG gate_en bit mapping ambiguity [INTERFACE-GAP]
**Module:** clk_gate_ctrl + testbench
**Symptom:** Testbench writes `0x01` intending to set `force_on[0]=1`, but actually sets `gate_en[0]=1` (gates clock OFF).
**Root cause:** CG_CTRL register bit mapping `{force_on[7:4], gate_en[3:0]}` is clear in the register map, but the physical meaning is counterintuitive: `gate_en=1` means "gating enabled" = clock OFF.
**Fix:** Document clearly in interface contract. Consider renaming: `gate_en` → `gate_req` or `clk_disable`.
**Skill gap:** Interface contract template lacks "register bit polarity semantics" field.

## Skill Documentation Gaps (5)

### GAP-LP1: Pulse output must use transition detection
**File to update:** `references/advanced/low-power-guidelines.md` §4
**Addition:** After the PSM code example, add: "Pulse outputs (retain_save, retain_restore, sleep_ack, wake_ack) MUST use transition detection (previous_state != current_state), NOT state comparison (state_q == TARGET). State comparison causes spurious assertion on reset and after every FSM restart."
**Related pattern:** PSM wake_ack, sleep_ack, retain_save, retain_restore (BUG-1)
**Suggested pattern ID:** LP7

### GAP-LP2: Request signals must specify pulse vs level semantics
**File to update:** `references/advanced/low-power-guidelines.md` §9 (DVFS)
**Addition:** "All module request inputs (sleep_req, wake_req, freq_req) MUST specify whether they are pulse (auto-clearing after 1 cycle) or level (software must clear). Recommendation: use pulse for single-shot requests, level for continuous enable."
**Related pattern:** dvfs_freq_req level vs psm_sleep_req pulse inconsistency (BUG-2)

### GAP-LP3: FSM must have abort path on request deassertion
**File to update:** `references/debug/bug-pattern-library.md`
**Addition:** New pattern: "FSM stuck in intermediate state when request deasserts mid-sequence. Every non-terminal FSM state that was entered on a request MUST have an abort path when the request deasserts."
**Related pattern:** DVFS S_CHECK_IDLE stuck (BUG-3)
**Suggested pattern ID:** SM3

### GAP-PH1: SRAM/register-file initialization guidance
**File to update:** `references/advanced/physical-awareness-guidelines.md` §2
**Addition:** "When instantiating SRAM or large register files: (1) Document whether memory needs software initialization before first use. (2) For FPGA: add reset initialization loop with synthesis guard. (3) For ASIC: document that memory starts uninitialized, add valid bits or first-use detection."
**Related pattern:** phys_aware_datapath SRAM 'x' (BUG-4)

### GAP-TB1: Registered output sampling latency
**File to update:** `references/verification/simulation-loop.md`
**Addition:** "When DUT has registered outputs (prdata, result, status): the testbench MUST add 1 extra cycle after the ACCESS phase before sampling. The APB read task template should be: SETUP → ACCESS → WAIT → CAPTURE (4 cycles total for registered PRDATA, vs 3 for combinational)."
**Related pattern:** APB prdata_q latency (BUG-6), GAP-GR3 regression

## Self-Review Checklist Gaps (3)

### CHECK-LP1: Pulse output transition check
**Add to Step 8 checklist (Low-power section):**
- [ ] Pulse outputs (ack, done, save, restore) use transition detection, not state comparison

### CHECK-SM1: FSM abort path check
**Add to Step 8 checklist (FSM section):**
- [ ] Every non-terminal FSM state entered on a request has abort path back to IDLE on request deassertion

### CHECK-PH1: Memory initialization check
**Add to Step 8 checklist (Integration section):**
- [ ] SRAM/register-file initialization strategy documented (software init, reset loop, or valid bits)

## Sub-Agent Quality Assessment

| Agent | Module | Self-Review | Actual Bugs | Assessment |
|-------|--------|-------------|-------------|------------|
| psm-agent | psm | PASS | wake_ack stuck (BUG-1) | Structure correct, functional bug in pulse logic |
| dvfs-agent | dvfs_ctrl | PASS | No abort path (BUG-3), freq_req level (BUG-2) | FSM correct but missing defensive abort |
| clkgate-agent | clk_gate_ctrl | PASS | Mixed driver (BUG-5) | Minor Yosys warning, functionally correct |
| physdatapath-agent | phys_aware_datapath | PASS | SRAM uninitialized (BUG-4) | Structural PH1-PH4 all PASS; functional bug in data init |
| apbregs-agent | apb_regs | PASS | Registered PRDATA latency (BUG-6) | Protocol correct, testbench timing issue |

**Pattern confirmed:** All 5 sub-agents passed self-review but 5/6 modules had at least one real bug. This reinforces the P18 lesson: structural review does not catch functional issues.

## Pattern Coverage Validation

| Pattern | Module | Validated? | Notes |
|---------|--------|------------|-------|
| LP1 (isolation before power-off) | psm | YES | isolation_en asserts in S_ISOLATING, 2 states before power_switch=0 |
| LP2 (retention save/restore handshake) | psm | YES | retain_save before power-off, retain_restore after power-on |
| LP3 (no illegal PSM transitions) | psm | YES | Sequential transitions only, default→S_ON |
| LP4 (gated clock CDC pulse sync) | clk_gate_ctrl | YES | Pulse synchronizer with ASYNC_REG attribute |
| LP5 (DVFS bus idle gate) | dvfs_ctrl | PARTIAL | bus_idle_i checked, but FSM lacks abort path |
| LP6 (wide combinational operand isolation) | dvfs_ctrl | YES | isolate_en_o registered, covers full DVFS window |
| PH1 (registered I/O) | phys_aware_datapath | YES | All outputs from registers, verified by Yosys |
| PH2 (max_fanout attribute) | phys_aware_datapath | YES | Attribute on clk_en_i, isolate_en_i, start_i |
| PH3 (SRAM in same hierarchy) | phys_aware_datapath | YES | 256x32 mem_q in module, verified |
| PH4 (bus grouping) | phys_aware_datapath | YES | 5 port groups with comments, verified |

## Recommended Skill File Changes

| Priority | File | Change | Bug(s) Addressed |
|----------|------|--------|-----------------|
| HIGH | `low-power-guidelines.md` §4 | Add pulse output transition detection rule (LP7) | BUG-1 |
| HIGH | `bug-pattern-library.md` | Add SM3 (FSM abort path) + LP7 (pulse transition) | BUG-1, BUG-3 |
| HIGH | `interface-contract-template.md` | Add "Signal type" field (pulse/level/registered) | BUG-2 |
| MEDIUM | `physical-awareness-guidelines.md` §2 | Add SRAM initialization guidance | BUG-4 |
| MEDIUM | `simulation-loop.md` | Add registered output sampling latency note | BUG-6 |
| MEDIUM | `coding-guidelines.md` | Clarify "output reg driven by assign" pattern | BUG-5 |
| LOW | `interface-contract-template.md` | Add "Register bit polarity" field | BUG-7 |
