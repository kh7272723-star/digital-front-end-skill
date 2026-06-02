# Golden Reference Methodology

## Purpose

Structural self-review (SKILL.md Step 8) checks naming, FSM style, protocol compliance, and reset behavior. It does NOT verify functional correctness — whether the module produces the right output values for given inputs.

This file defines the golden reference methodology: how to create expected-value checks that catch functional bugs structural review cannot detect.

**Evidence from project history:**
- CRC: 66 checklist items PASS, single-beat output = 0 (should be non-zero)
- Crossbar: routing logic completely broken despite structural PASS
- DMA: transfer never completed despite structural PASS

## When to use golden references

**Always.** Every nontrivial module needs at least one functional test with known expected outputs. The strategy depends on the module type.

## Strategy selection

| Module type | Strategy | Complexity | Template |
|-------------|----------|------------|----------|
| Computation (CRC, ECC, ALU, hash) | A: Known I/O pairs | Low | Template 1 |
| Algorithm with variable input | B: Software reference model | Medium | Template 2 |
| Register block (APB, AXI-Lite) | C: Write-readback scoreboard | Low | Template 3 |
| Data movement (DMA, FIFO, converter) | D: Data integrity scoreboard | Medium | Template 4 |
| Stateful control (arbiter, counter, FSM) | E: Invariant checking | Low | Template 5 |
| Pipeline / latency-sensitive | F: Latency checker | Low | Template 6 |

---

## Strategy A: Known I/O Pair Table

**When to use:** Algorithm is well-defined by a standard, input space is small enough to enumerate key cases.

**How to obtain vectors:**
- CRC: IEEE 802.3 polynomial test vectors, online CRC calculators
- ECC: Hsiao code / SECDED encode/decode tables from textbook
- ALU: ISA spec opcode definitions
- Encoder/decoder: truth table from specification

**Rule:** Expected values must come from the spec or an independent source — NOT from reading the DUT code.

---

## Strategy B: Software Reference Model

**When to use:** Algorithm is too complex for a lookup table but can be expressed as a pure function.

**Key constraint:** The reference function must be independently derived from the spec, NOT copied from the DUT. Copying catches only syntax bugs, not algorithmic bugs.

**Pattern:** Implement the same algorithm as a Verilog `function` (combinational, no state), compare DUT output against function output for the same input.

---

## Strategy C: Write-Readback Scoreboard

**When to use:** Module has a register file or addressable storage accessible via bus (APB, AXI-Lite).

**Method:**
1. Write a known value to a register address
2. Read back from the same address
3. Compare read data against written value (accounting for STRB masking and reset defaults)

**STRB handling:** Expected = `(wr_data & strb_to_mask(strb)) | (reset_default & ~strb_to_mask(strb))`

**Known pitfall — stale combinational output:** Bus read data (`PRDATA`, `RDATA`) is often combinational from the current address. After a read completes, the testbench may call an `idle_bus()` task that clears the address, causing `PRDATA` to change to the value at address 0x0 (or whatever the idle address maps to). If you sample `PRDATA` after `idle_bus()`, you get stale/wrong data.

**Fix:** Sample the register output pins directly (`reg0_o`, `reg1_o`) after write, or capture `PRDATA` BEFORE calling `idle_bus()`. Do not rely on bus output persistence after the transaction ends.

*Validated in apb_regs_trial (2026-05-28): initial implementation checked `prdata_o` after `apb_read` returned, but `idle_bus()` zeroed `paddr_i`, making `prdata_o` reflect reg0 instead of the register just read.*

---

## Strategy D: Data Integrity Scoreboard

**When to use:** Module's purpose is to move data from input to output without corruption (DMA, FIFO, width converter, stream buffer).

**Method:**
1. On input handshake (valid && ready): enqueue the input data into an expected queue
2. On output handshake (valid && ready): dequeue from the expected queue and compare against output data
3. After all transfers: verify queue is empty (no data lost or duplicated)

**Pattern selection:** Use known patterns (0x01, 0x02, ..., 0xFF) or pseudo-random with fixed seed for reproducibility.

**DMA and bus-master extension:** A data scoreboard alone can false-pass a broken DMA. For memory movers and bus masters, the golden checker must also track the transaction shape:

1. Expected command count versus observed `AW/AR` handshakes
2. Expected address sequence, including unaligned first beat and 4KB boundary splits
3. Expected `AWLEN/ARLEN`, `WLAST/RLAST`, and exact beat count
4. Expected `WSTRB` masks on first, middle, and last beats
5. `B`/`R` response capture and error propagation into completion status
6. Completion only after required write responses or read data beats have been observed
7. Independent backpressure on every AXI channel, not a permanently-ready happy path

If the testbench only iterates over captured output beats and never checks how many beats should have appeared, it can pass when the DUT silently emits too few transactions.

---

## Strategy E: Invariant Checking

**When to use:** Module has properties that must hold every cycle, regardless of specific input/output values.

**Common invariants:**
- Arbiter: `grant_o` must be one-hot or zero (`$onehot0(grant_o)`)
- Arbiter: no grant without request (`grant_o & ~req_i == 0`)
- Credit counter: `0 <= credit_q <= MAX_CREDITS`
- FIFO: `count <= DEPTH`
- FSM: `$onehot(state_q)` or `state_q` in legal set

**Method:** Continuous `always @(posedge clk)` block that checks invariants every cycle after reset, reports violations with `$display`.

**Known pitfall — registered output semantics:** A registered output (e.g., `valid_o`) holds its value until the next update, but the combinational input that caused it (e.g., `valid_i[source]`) can change at any time. Checking `valid_o && !valid_i[grant_o]` every cycle produces false violations because `valid_o` stays high after the source deasserts `valid_i`.

**Fix:** Check "no grant without request" only at grant time (when `ready_o` fires), not every cycle. Use pre-edge sampled values to avoid race conditions with the DUT's combinational logic settling:

```verilog
// Pre-edge capture (non-blocking, same posedge)
always @(posedge clk_i) begin
    inv_ready_o_pre <= ready_o;
    inv_valid_i_pre <= valid_i;
end
// Check at grant time only (after #1 settle)
always @(posedge clk_i) begin
    #1;
    if (!rst_i && inv_ready_o_pre != 0) begin
        // Grant issued — check the granted source had an active request
        if (!inv_valid_i_pre[grant_o]) begin
            $display("INVARIANT_FAIL: grant without request");
        end
    end
end
```

*Validated in rr_arbiter_trial (2026-05-28): initial implementation checking every cycle produced 86 false violations due to registered `valid_o` holding while source deasserted `valid_i`.*

---

## Strategy F: Latency Checker

**When to use:** Module's correctness depends on timing/latency (pipeline, register slice, skid buffer).

**Method:**
1. Record the simulation cycle when input is accepted (valid && ready)
2. Record the simulation cycle when output is produced (valid && ready)
3. Assert `output_cycle - input_cycle == EXPECTED_LATENCY`

**Known pitfall — block ordering race:** If input capture and output check are in separate `always` blocks, both fire on the same `posedge clk`. In a single-cycle pipeline, the input capture may overwrite `lat_input_cycle` before the output check reads it, causing the check to see the wrong (current-cycle) input instead of the previous-cycle input.

**Fix:** Use a single `always` block with check-before-capture ordering:

```verilog
always @(posedge clk_i) begin
    #1;
    // CHECK first (uses previous cycle's input)
    if (!rst_i && m_valid_o && m_ready_i && lat_check_active) begin
        if ((cycle_cnt - lat_input_cycle) == EXPECTED_LATENCY)
            $display("GOLDEN_PASS latency: %0d cycles", EXPECTED_LATENCY);
        else
            $display("GOLDEN_FAIL latency: got %0d, expected %0d",
                     cycle_cnt - lat_input_cycle, EXPECTED_LATENCY);
        lat_check_active = 0;
    end
    // CAPTURE second (for next cycle's check)
    if (!rst_i && s_valid_i && s_ready_o) begin
        lat_input_cycle = cycle_cnt;
        lat_check_active = 1;
    end
end
```

*Validated in pipeline_reg (2026-05-28): separate always blocks caused input capture to overwrite `lat_input_cycle` before output check used it. Merging into single block with check-before-capture order fixed the race.*

---

## Testbench integration rules

1. Golden reference checks run AFTER the DUT produces output (not during stimulus)
2. Use `#1` settling delay before sampling DUT outputs (per tb-examples.md pattern 7)
3. Report failures with: test name, input value, expected output, actual output, simulation time
4. Use the simulation output protocol: `TEST_START`, `TEST_PASS`, `TEST_FAIL`, `ALL_TESTS_PASS`
5. Limit per-beat logging; use `$display` only at test boundaries or on failure

## Common mistakes

1. **Copying DUT algorithm as "reference"** — catches only syntax bugs, not algorithmic bugs. The reference must be independently derived from the spec.
2. **Checking only happy path** — golden references must cover boundary inputs (zero, max, single-beat, empty, full).
3. **Not waiting for DUT latency** — checking output before the module has processed the input. Always account for pipeline depth.
4. **Using `===` instead of `!==`** — `===` matches X/Z, which hides real bugs. Use `!==` for mismatch detection.
5. **Forgetting final XOR or complement** — CRC output is typically `crc_q ^ XOR_OUT`, not `crc_q` directly.
6. **Reset default not accounted** — register readback must account for the reset value of fields not written by the test.
7. **Checking registered outputs every cycle** — a registered output holds its value; checking its relationship with combinational inputs every cycle produces false violations. Check at the event boundary (grant time, handshake time), not every cycle.
8. **Separate always blocks for related capture/check** — if input capture and output check fire on the same clock edge, put them in the same `always` block with check-before-capture ordering to avoid race conditions.
