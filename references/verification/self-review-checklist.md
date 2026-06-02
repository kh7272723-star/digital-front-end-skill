# RTL Self-Review Checklist

Complete checklist extracted from SKILL.md Step 8. Each item must be explicitly checked and marked pass/fail. For each FAIL item, fix before proceeding and state what was changed. For each ✅ item, cite the specific line numbers or signal names that satisfy the check.

**Critical limitation:** This checklist verifies STRUCTURAL correctness only (naming, FSM style, protocol compliance, reset). It does NOT verify FUNCTIONAL correctness. See bug-pattern P18 (CRC pipeline latency) and Crossbar project. Always follow with Step 8b (functional verification) and Step 9 (simulation).

## Signal Type Cross-Check (P1 Contract ↔ RTL)

For every output classified in the timing contract as **pulse / level / registered**, verify the RTL produces that behavior:

- [ ] **Pulse outputs:** Does each pulse output deassert after exactly 1 cycle? Uses transition detection (`prev != state_q`), not state comparison (`state_q == TARGET`)? — bug-pattern LP7, BUG-1
- [ ] **Level outputs:** Does each level output sustain until a clear condition (W1C, next-packet-start, FSM exit)? Can the testbench safely poll it at any time? — timing-contract-template.md
- [ ] **Registered outputs:** Is each registered output driven from a flip-flop (not combinational `assign` or `always @(*)` from `state_q`)? Does the timing contract document the +1 cycle latency? — P18, F2, PH1

**If mismatch found:** The contract or the RTL is wrong — fix one of them before simulation. A signal classified as "level" in the contract but implemented as a 1-cycle pulse will pass structural review, appear correct in waveform, but silently fail when the testbench samples it at the wrong cycle.

## Handshake

- [ ] VALID holds until READY (no premature deassertion) — H1, H8
- [ ] VALID not gated by non-protocol conditions (outstanding count, FIFO status, flow control) — H8
- [ ] Payload stable while VALID high — H1
- [ ] No combinational ready loop across modules — H2

## Data Path

- [ ] All error capture points traced to completion output — DP5, `integration-invariants.md`
- [ ] Bit-slicing avoided when value can equal 2^n (use if/else) — DP4
- [ ] WSTRB correctly computed for unaligned addresses — `axi-dma-channel-guidelines.md`
- [ ] Data-path FIFOs use FWFT (combinational) output, NOT registered output — F1, `fifo-examples.md`

## NBA Ordering Hazards (mandatory for L1/L2)

All `<=` assignments in the same `always @(posedge clk)` block are evaluated with OLD values and take effect simultaneously next cycle. If signal B depends on signal A's NEW value, they CANNOT be in the same `<=` block.

- [ ] **AXI beat-dependent outputs (WLAST, RLAST):** Are they driven by `assign` (combinational), not `<=` (registered)?  
  *Wrong:* `axi_w_last_o <= (w_beat_q == w_burst_len_q);` — beat counter advances via `<=` in same block, so `w_beat_q` used is the old value. Slave sees last=0 on the final beat.  
  *Right:* `assign axi_w_last_o = w_active_q && (w_beat_q == w_burst_len_q);`

- [ ] **AXI data from FIFO:** Does `axi_w_data_o` come from a combinational path (`assign` or pipe register loaded ONE CYCLE EARLIER), not from `<= fifo_rdata` in the same block that advances `fifo_rd_ptr`?  
  *Wrong:* `axi_w_data_o <= fifo_rdata; fifo_rd_ptr_q <= fifo_rd_ptr_q + 1;` — data uses old `rd_ptr`, advances next cycle → data always 1 beat stale.  
  *Right:* Load `w_data_pipe_q <= fifo_mem[rd_ptr_q + 1]` on handshake; `assign axi_w_data_o = w_data_pipe_q;`

- [ ] **FIFO read pointer vs data consumption:** Does `fifo_rd_en` advance `rd_ptr` in the SAME cycle as data is consumed from `fifo_rdata`? If `rd_ptr` advances via `<=` and data is registered via `<=` in the same block, the registered data uses the OLD `rd_ptr`. Fix: either make data combinational, or pre-fetch from `mem[rd_ptr + 1]`.

- [ ] **Address/offset advance timing:** Does the address counter advance on `*_rd_en` (read issue) or on data arrival? If it advances on data arrival but the read enable is combinational from the counter, the same address is read twice. Advance on read-issue, not data-arrival.

- [ ] **WVALID gate:** Is `w_beat_q` advancing gated by `axi_w_valid_o && axi_w_ready_i` (not just `axi_w_ready_i`)? On the first W cycle, `w_valid_o` is still 0 (NBA not yet taken effect). If beat advances on `w_ready_i` alone, beat 0 is skipped.

- [ ] **Last data beat arrival:** Does `fifo_wr_en` depend on `nvm_rd_en_o` (or equivalent read-enable)? If the read-enable deasserts when byte-count reaches 0, the last beat's data arriving 1 cycle later is gated off. Use `fifo_wr_en = nvm_rvalid_i` (unconditional on data-valid).

## Naming

- [ ] All ports use `*_i`/`*_o` suffixes
- [ ] All registered state uses `*_q` suffix
- [ ] Combinational signals do NOT use `*_q` suffix
- [ ] FIFO ops use `wr_do`/`rd_do` naming

## RTL Correctness

- [ ] Every reg/wire has exactly one driving source — E1
- [ ] No `output reg` port driven by `assign` — E1b, `correctness-rules.md`
- [ ] Every combinational block assigns defaults before conditional branches — E2
- [ ] No implicit truncation — explicit part-selects on width mismatches — E3
- [ ] `<=` in sequential blocks, `=` in combinational blocks, never mixed — E4
- [ ] All combinational blocks use `always @(*)` — E5
- [ ] All registers have explicit reset (or documented justification) — E6
- [ ] No combinational feedback loops — E7
- [ ] Every `.v` file starts with `` `default_nettype none `` — E8

## FSM

- [ ] All combinational blocks have default assignments — C3
- [ ] FSM has default case → IDLE — C2
- [ ] Two-process style for >3 states — `fsm-examples.md`
- [ ] No multi-bit datapath `_d` assignments inside the FSM combinational block (`state_d` is exempt) — SM1
- [ ] No second `always @(*)` block computing multi-bit `_d` values gated on state — SM2
- [ ] All multi-bit register updates use synchronous `always @(posedge clk)` gated by single-bit enables from the FSM — `fsm-examples.md`

## Protocol (AXI)

- [ ] Completion on B response, not last W beat — P4
- [ ] WVALID holds until WREADY — P11
- [ ] W channel mode declared: continuous/full-burst-buffered or elastic/per-beat buffered — P12
- [ ] WVALID/WDATA/WSTRB/WLAST stable while `WVALID && !WREADY` — P12, IHI0022 A3.3
- [ ] Continuous mode only: WVALID holds through WLAST and full-burst data is available before start — local policy
- [ ] Elastic mode only: WVALID bubbles are allowed by contract and covered by no-underflow/liveness checks — local policy
- [ ] ARVALID/AWVALID hold until corresponding READY — P11, IHI0022E A3.3.1
- [ ] VALID not dependent on READY (no combinational path) — IHI0022E A3.3.2
- [ ] Write engine does NOT use sequential AW→W→B FSM — P13, use independent AW/W/B controllers
- [ ] AW/W/B channels have independent valid/ready control — `axi-dma-channel-guidelines.md`
- [ ] Data FIFO pop and W beat counter advance only on `WVALID && WREADY` — P12
- [ ] 4KB boundary: `12'h1000`, not `12'h800`
- [ ] WSTRB last beat: handle `last_offset == 0` (all bytes valid)

## APB (if APB interface present)

- [ ] PSEL asserted only in SETUP and ACCESS phases
- [ ] PENABLE asserted only in ACCESS phase
- [ ] PADDR/PWDATA/PWRITE latched in SETUP, held through ACCESS
- [ ] PSLVERR mapped to upstream error response
- [ ] PSEL deasserted between transactions
- [ ] If APB slave uses registered PRDATA: bridge samples one cycle after PREADY=1

## AXI-Stream (if AXI-Stream interface present)

- [ ] TLAST propagated exactly on every beat
- [ ] TKEEP propagated exactly on every beat
- [ ] Payload stable while TVALID=1 and TREADY=0 — H1
- [ ] TVALID not dependent on TREADY — A3.3.2
- [ ] Backpressure propagation documented (combinational or registered)
- [ ] Packet boundary behavior defined (state at TLAST)

## CDC (if multiple clock domains)

- [ ] Multi-bit CDC uses gray code or handshake
- [ ] Synchronizer flip-flops marked with `(* ASYNC_REG = "TRUE" *)` attribute
- [ ] Reset: async assertion, sync deassertion per destination domain
- [ ] No combinational paths across clock domains

## Integration

- [ ] All per-channel errors OR'd into completion tracker — DP5
- [ ] Outstanding counter saturation doesn't block drain — `integration-invariants.md`
- [ ] Reset clears all valid-like outputs — R2
- [ ] All module ports are referenced in the module body (no dead ports)
- [ ] No dead modules (all instantiated modules are used)
- [ ] Completion signal style matches spec: pulse (1-cycle) for done, level (sticky) for status — `timing-contract-template.md`
- [ ] **Configuration path and data path use independent control — P4.** APB/register access must not accidentally consume or corrupt in-flight data. If the data path module has an internal state machine, verify it does not share state with the APB transaction logic.

## Engineering Intuition

Automated via `scripts/rtl_complexity_check.py`.

- [ ] No `always @(*)` block exceeds 50 lines — C1 (RMM §7.3)
- [ ] No if-else nesting exceeds 3 levels — C2 (RMM §7.4)
- [ ] No single module exceeds 300 lines without decomposition — C3 (RMM §7.2)
- [ ] Combinational depth from input to output < 7 gate levels — D1 (Synopsys DC)
- [ ] No wide comparator (>32-bit) on critical path without pipelining — D2 (UG901)
- [ ] No register array > 64 entries without RAM inference — A1 (UG901)
- [ ] No hard-coded constants that should be parameters — A3 (RMM §3.3)

## Low-Power (when power management is in scope)

- [ ] Clock gating uses ICG cell or clock-enable style, not `clk & en` — CL1
- [ ] Isolation enable asserts before power-off, deasserts after power-on — LP1
- [ ] Retention save completes before power-off, restore after power-on — LP2
- [ ] Power state machine has no illegal transitions, uses two-process FSM — LP3
- [ ] Gated clock domain crossings use pulse synchronizers (not level) — LP4
- [ ] DVFS frequency change gated by bus idle — LP5
- [ ] Operand isolation applied to wide (>32-bit) combinational logic — LP6
- [ ] Pulse outputs (ack, done, save, restore) use transition detection, not state comparison — LP7
- [ ] FSM intermediate states have abort path on request deassertion — SM3

## Physical Awareness (for ASIC targets)

- [ ] Module boundaries have registered I/O (no cross-hierarchy combinational paths) — PH1
- [ ] High-fanout nets (>50) have `max_fanout` attribute or register replication — PH2
- [ ] Memory macros in same module hierarchy as primary consumer — PH3
- [ ] Bus signals grouped by channel at partition ports — PH4
