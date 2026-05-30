# RTL Self-Review Checklist

Complete checklist extracted from SKILL.md Step 8. Each item must be explicitly checked and marked pass/fail. For each FAIL item, fix before proceeding and state what was changed. For each ✅ item, cite the specific line numbers or signal names that satisfy the check.

**Critical limitation:** This checklist verifies STRUCTURAL correctness only (naming, FSM style, protocol compliance, reset). It does NOT verify FUNCTIONAL correctness. See bug-pattern P18 (CRC pipeline latency) and Crossbar project. Always follow with Step 8b (functional verification) and Step 9 (simulation).

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
- [ ] WVALID holds for entire burst (no mid-burst deassertion) — P12, IHI0022E A3.3.1
- [ ] ARVALID/AWVALID hold until corresponding READY — P11, IHI0022E A3.3.1
- [ ] VALID not dependent on READY (no combinational path) — IHI0022E A3.3.2
- [ ] Write engine does NOT use sequential AW→W→B FSM — P13, use independent AW/W/B controllers
- [ ] AW/W/B channels have independent valid/ready control — `axi-dma-channel-guidelines.md`
- [ ] Data FIFO depth >= max burst length, or burst-ready gate on WVALID — P12
- [ ] WVALID does NOT depend on FIFO empty/full state mid-burst — P12
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
