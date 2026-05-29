# Development Log: Fuzzy-Spec Packet Processor

## Purpose

Test the digital-front-end-skill's ability to handle a deliberately vague specification. The
spec does not specify CRC polynomial/width, header format, packet length, channel mapping,
error handling, throughput requirements, or packet delimiting. The goal is to discover gaps
in the skill, not to deliver perfect RTL.

---

## Step 1: Parse the Request

**Skill workflow step**: Summarize the requested block, list open questions, classify as
leaf module.

**What happened**: The spec was underspecified on 7 dimensions. The skill's workflow says
"ask before writing code" but provides no structured method for extracting requirements
from a vague spec. Key assumptions had to be made:
- CRC-32 / IEEE 802.3 (polynomial 0x04C11DB7) — chosen from skill reference patterns
- Header = first beat, bits [1:0] = channel — arbitrary choice
- Packet min 2 beats (8 bytes), max 256 beats — arbitrary choice
- 4 output channels, AXI-Stream — from requirement
- Store-and-forward architecture — from requirement

**Gap 1: No requirement extraction framework.** The skill says "If anything critical is
missing, ask before writing code" but does not provide a checklist or template for what
constitutes "critical." A vague spec needs systematic gap identification. The skill should
have a "vague-spec-to-contract" template.

---

## Step 2: Build the Timing Contract

**Skill workflow step**: Produce timing contract using timing-contract-template.md.

**What happened**: The timing contract was written with clock domain, reset style, handshake
rules, latency, stall, and flush behavior. The contract template was adequate for AXI-Stream
protocols.

**No gap found**: The timing contract template worked well for this use case.

---

## Step 3: Freeze the Contract / Identify State Elements / Write Cycle Trace

**Skill workflow step**: Port list, state elements, cycle trace.

**What happened**: Standard state elements were identified: 5-state FSM, FIFO, CRC pipeline,
channel register, counters. Cycle trace described the store-and-forward pipeline.

**No gap found**: These steps worked as expected for this module.

---

## Step 4: Choose a Pattern / Generate RTL

**Skill workflow step**: Pick pattern from references, generate RTL.

**What happened**: The packet_processor was written as a single module with:
- Two-process FSM (5 states: IDLE, RECV, CHK, DRAIN, DROP)
- AXI-Stream input/output with 4-channel demux
- FWFT FIFO for packet buffering
- CRC-32 pipeline from skill references

**Design decisions**:
- `s_axis_tready_o` computed from state and FIFO count (NOT from valid_i) — correct
- FSM outputs are single-bit enables — follows skill rule
- Datapath registers updated outside FSM — follows skill rule
- CRC pipeline instance from `references/patterns/crc-examples.md` — **had bug**

---

## Step 5: Simulation — Compile and Run

### Attempt 1: Compile only

Compilation succeeded with `iverilog -g2012`. No syntax errors.

### Attempt 2: First simulation run

**Failure**: Test 1 (basic forward ch0) timeout — DUT stuck in ST_IDLE.

**Root cause 1 (CRC bug)**: The `crc_parallel.v` module from the skill reference had a
standard-conformance bug in the serial CRC feedback computation.

The original code:
```verilog
crc_next = {crc_next[CRC_W-2:0], 1'b0}
         ^ ({CRC_W{data_processed[DATA_W-1-bit_idx]}} & POLYNOMIAL);
if (crc_next[CRC_W-1])
    crc_next = crc_next ^ POLYNOMIAL;
```

This XORs the data bit into the LSB, then conditionally XORs the polynomial based on
`crc_next[CRC_W-1]` (which equals the shifted `crc[CRC_W-2]`, i.e., the second MSB of
the old CRC). The correct serial CRC feedback is:

```verilog
if (crc_next[CRC_W-1] ^ data_bit)
    crc_next = (crc_next << 1) ^ POLYNOMIAL;
else
    crc_next = crc_next << 1;
```

The feedback decision should be `old_MSB XOR data_bit`, not `old_second_MSB`. The bug
caused the DUT to compute CRC incorrectly, enter ST_DROP instead of ST_DRAIN, and never
produce output.

**Gap 2: CRC reference pattern has a feedback bug.** The CRC-32 implementation in
`references/patterns/crc-examples.md` does not implement the standard serial CRC feedback.
This is a correctness issue with the skill reference material — any module using this
CRC core would produce wrong results.

### Attempt 3: Debug CRC — added @(*) sensitivity fix

**Failure persisted**: Debug showed the FSM combo block was not triggering when
`s_axis_tvalid_i` changed. The FSM used `accept_input` (a wire from continuous
assignment `assign accept_input = s_axis_tvalid_i && s_axis_tready_o`) in its case
conditions. Icarus Verilog's `@(*)` sensitivity analysis did not properly track this
intermediate wire back to its leaf signals.

**Fix**: Replaced `accept_input` with `s_axis_tvalid_i && s_axis_tready_o` directly in
the FSM combinational block.

**Gap 3: @(*) sensitivity with intermediate wires.** Icarus Verilog does not reliably
trigger `@(*)` when a wire from a continuous assignment changes. The FSM block references
`accept_input` but Icarus doesn't infer sensitivity to the leaf signals driving it. The
skill assumes standard Verilog `@(*)` behavior but this is simulator-dependent.

### Attempt 4: CRC fixed — Tests 1-6 pass

**CRC fix confirmed**: After fixing the feedback formula, `crc_match=1` and state
transitions correctly through CHK -> DRAIN -> IDLE.

Tests 1-6 passed. Tests 7-9 had remaining issues.

### Test 7 (all_channels): Counter comparison

**Failure**: `ch_pkt_cnt_o_X = 1` was expected but counters were cumulative from tests 1-6
(ch0=2, ch1=2, ch2=3, ch3=2).

**Fix**: Changed test to record pre-test counters and verify delta of 1 per channel.

**Gap 4: No guidance on cumulative state in test design.** The skill verification
guidance does not address test sequencing — counters accumulate across tests but the
test expects absolute values. A reusable test template with "record-verify" pattern
would catch this.

### Test 9 (isolation): Beat 1 data mismatch

**Failure**: Beat 1 of the payload (expected 0x04030201) showed 0x00000000.

**Root cause**: `m_axis_tready_i_r[0] <= 1'b1` was asserted BEFORE `expect_pkt_buf(0)`.
This was the same anti-pattern as the original test 1 timeout. The ready signal was
pre-set when `expect_pkt_buf` entered, causing race conditions between the DUT's FWFT
FIFO advance and the testbench's data sampling.

**Fix**: Changed to `m_axis_tready_i_r[0] <= 1'b0` before `expect_pkt_buf(0)`, letting
`expect_pkt_buf` control ready pulsing.

**Gap 5: Testbench signal settling.** The testbench's `expect_pkt_buf` originally
sampled `m_axis_tdata_o` immediately after `@(posedge clk_i)` returned, before
combinational outputs settled after NBA updates. Adding `#1` after `@(posedge clk_i)`
was needed to see settled values.

---

## Final Simulation Result

```
RESET_RELEASED
TEST_START 0: CRC self-test
TEST_PASS 0: CRC OK (cbf43926)
TEST_START 1: forward ch0
TEST_PASS 1: ch0 OK
TEST_START 2: forward ch1
TEST_PASS 2: ch1 OK
TEST_START 3: forward ch2
TEST_PASS 3: ch2 OK
TEST_START 4: forward ch3
TEST_PASS 4: ch3 OK
TEST_START 5: bad CRC
TEST_PASS 5: bad CRC OK (cnt=1)
TEST_START 6: backpressure
TEST_PASS 6: backpressure OK
TEST_START 7: all channels
TEST_PASS 7: all channels OK
TEST_START 8: back-to-back
TEST_PASS 8: back-to-back OK
TEST_START 9: isolation
TEST_PASS 9: isolation OK
ALL_TESTS_PASS
SIMULATION_DONE
```

All 10 tests pass (1 CRC self-test + 9 design tests).

---

## Summary: Top 5 Skill Gaps

### Gap 1: CRC reference pattern has standard-conformance bug (CRITICAL)

**File**: `references/patterns/crc-examples.md` → `rtl/crc_parallel.v`

The serial CRC-32 feedback formula is wrong. The code XORs the data bit into the LSB,
then conditionally XORs the polynomial based on `crc_next[CRC_W-1]` (which equals the
old `crc[CRC_W-2]` — the SECOND MSB). The correct formula uses `old_MSB XOR data_bit`
as the feedback decision. This affects any design using the CRC reference.

**Impact**: High. Any skill user copying the CRC pattern gets incorrect results. The
CRC self-test would catch this only if the testbench uses a different (correct) CRC
implementation — if the testbench copies the same bug, the mismatch is hidden.

### Gap 2: Icarus @(*) sensitivity with intermediate wires (SIMULATOR BOUNDARY)

The FSM combinational block used `accept_input` (a wire from continuous assignment).
Icarus Verilog's `@(*)` analysis did not properly trigger when `s_axis_tvalid_i`
(the leaf signal driving `accept_input`) changed. The skill assumes standard Verilog
behavior but this is simulator-dependent.

**Impact**: Medium. The skill's self-review step (Step 8) does not include an Icarus
compatibility check. A `@(*)` usage guideline referencing only direct signals (not
through intermediate wires) would prevent this.

**Fix**: Reference `s_axis_tvalid_i && s_axis_tready_o` directly in `@(*)` blocks
instead of through a named wire.

### Gap 3: No testbench signal settling guidance (VERIFICATION GAP)

The skill Step 9 (Generate verification) provides testbench structure but no guidance
on `#1` settling delays after `@(posedge clk_i)`. Sampling combinational signals
immediately after `@(posedge clk_i)` returns sees stale values (before NBA updates).
The testbench's `expect_pkt_buf` needed `#1` after each posedge wait.

**Impact**: Medium-High. Without settling delays, testbenches have race conditions
that produce false failures or false passes. The testbench template should include
`#1` after clock edge waits.

**Fix**: All `@(posedge clk_i)` in monitor tasks should be followed by `#1` for
combinational settling.

### Gap 4: Ready assertion before send_pkt_buf anti-pattern (VERIFICATION GAP)

The original testbench asserted output ready BEFORE sending the packet. With the DUT's
store-and-forward architecture, the DUT enters ST_DRAIN after receiving TLAST, and if
ready is already asserted, it can drain the entire packet before `expect_pkt_buf`
starts monitoring. The test must keep ready deasserted during send and only assert it
inside the monitor task.

**Impact**: Medium. This is a common testbench anti-pattern that the skill's
verification guidance should document. The skill's RTL self-review checklist (Step 8)
has extensive AXI rules but no equivalent testbench timing checklist.

### Gap 5: No vague-spec-to-contract template (METHODOLOGY GAP)

The skill's Step 1 ("Parse the request") says "ask before writing code" but provides
no structured framework for extracting a contract from a deliberately vague spec.
For this fuzzy-spec exercise, 7 dimensions of underspecification were identified
(CRC, header format, packet length, channel mapping, error handling, throughput,
packet delimiting). A template with explicit "required/optional/assumed" fields would
help ensure all assumptions are documented.

**Impact**: Low-Medium. For experienced engineers this is obvious. For skill users,
the lack of structure may lead to missed assumptions that cause integration failures.

---

## Files Modified

| File | Change |
|------|--------|
| `rtl/crc_parallel.v` | Fixed serial CRC feedback formula |
| `rtl/packet_processor.v` | Reference `s_axis_tvalid_i` directly in FSM @(*) block |
| `tb/tb_packet_processor.v` | Added #1 settling delays; removed premature ready assertions; fixed cumulative counter check |

## Files Created

| File | Purpose |
|------|---------|
| `dump.vcd` | VCD waveform dump from simulation |
| `sim.vvp` | Compiled simulation binary |
| `DEVELOPMENT_LOG.md` | This file |
