# CDC Multi-Clock Capture - Development Log & Skill Gap Report

## Design Overview

System: Multi-clock ADC data capture and processing.
- **adc_clk (400MHz)**: 12-bit ADC samples -> block packer (16 samples -> 192-bit word)
- **sys_clk (100MHz)**: 192-bit -> AXI-Stream serializer (32-bit wide, 6 beats, TLAST on last)
- **CDC**: Async FIFO with gray-coded pointers and 2FF synchronizers
- **Reset**: Single async reset_n, synchronized per domain

## Timing Contract (from skill Step 2)

### Module: adc_capture_top (Top-level)
- **Clock domains**: adc_clk_i (400MHz), sys_clk_i (100MHz)
- **Reset**: rst_ni (active-low async), synchronized per domain
- **Input handshake**: adc_valid_i / internal ready (always ready, samples valid on rising edge)
- **Output handshake**: m_axis_tvalid_o / m_axis_tready_i (AXI-Stream)
- **Data latency**: From ADC sample to AXI-Stream output: block accumulation (16 cycles) + CDC latency (~3-8 sys_clk cycles) + serialization (6 beats)
- **Stall behavior**: ADC samples accepted until async FIFO full; AXI-Stream backpressure propagates via FIFO full
- **Flush**: Not supported; reset clears all state
- **Boundary behavior**: Partial block (incomplete 16 samples) NOT output until block completes
- **Overflow**: FIFO full blocks ADC writes; no data loss if ADC stalls

### Module: async_fifo (CDC crossing)
- **Write domain**: adc_clk, wr_rst
- **Read domain**: sys_clk, rd_rst
- **Data width**: 192 bits
- **Depth**: 8 entries
- **Output style**: FWFT (combinational read)
- **Synchronization**: Gray-coded pointers, 2FF per domain
- **Full/empty**: Conservative (full prevents over-write, empty prevents under-read)

### Module: axis_serializer
- **Input**: 192-bit from async FIFO (FWFT)
- **Output**: AXI-Stream, 32-bit TDATA, 1-cycle TLAST
- **Beats per word**: 6 (192 / 32)
- **Backpressure**: Combinational TREADY from downstream
- **Flow**: IDLE -> SEND(beats 0-5) -> IDLE (bubble) -> next word

### Module: adc_sample_packer
- **Input**: 12-bit samples, valid_i
- **Accumulation**: 16-sample shift register
- **Output**: 192-bit packed word, wr_en pulse on completion
- **Naming**: pack_buf_q (sample buffer), sample_cnt_q (0-15)

## CDC Design Phase

### CDC references used:
1. `references/synthesis/cdc-guidelines.md` - Good conceptual guidance: safe pattern selection, reset synchronizer pattern, ASYNC_REG attribute. Provides the reset synchronizer code.

2. `references/timing/clock-reset-guidelines.md` - Reset synchronization principles, keeping one clock per synchronous region, deriving reset synchronizers.

3. `references/rtl/fifo-examples.md` - Sync FIFO patterns (FWFT, occupancy, memory access). NO async FIFO patterns.

4. `references/debug/bug-pattern-library.md` - D1 (multi-bit bus sync), D2 (async FIFO gray code) - useful for awareness but not implementation guidance.

### Reset synchronizer decisions:
- Single async rst_ni input
- Two reset synchronizers: one for adc_clk domain, one for sys_clk domain
- Each synchronizer: 2 FFs with async reset -> synchronized active-high reset per domain
- Naming: adc_rst (adc_clk domain), sys_rst (sys_clk domain)
- Reset style: async assertion (immediate), sync deassertion (2 destination clock edges)

### CDC implementation decisions:
- Async FIFO: fully custom implementation using gray-coded pointers
- Read-side empty: compare rd_gray (current) against synchronized wr_gray
- Write-side full: compare wr_gray_next (next) against inverted synchronized rd_gray
- Synchronizer FFs marked with `(* ASYNC_REG = "TRUE" *)`
- Binary-to-gray and gray-to-binary functions defined locally

## Simulation Strategy

### What iverilog CAN test:
- Data integrity (samples in = beats out, checked by scoreboard)
- FIFO full/empty behavior
- AXI-Stream protocol (TVALID, TLAST, backpressure)
- Block accumulation timing
- Backpressure propagation (FIFO full -> ADC stall)

### What iverilog CANNOT test (must document as gaps):
- Metastability effects: iverilog is a pure event-driven simulator, it does NOT model
  setup/hold violations or metastability
- CDC timing violations: recover/removal timing on async reset
- Gray code timing hazards: even with correct gray code, there is statistical MTBF
  that iverilog will never show
- False paths: no STA tool to verify `set_clock_groups -asynchronous`
- ASYNC_REG placement: no way to verify that synthesis places sync FFs adjacently
- Reset domain crossing: no way to verify reset tree balancing

---

## Skill Gaps Discovered

### Gap 1: No complete async FIFO RTL template
- **Description**: The skill provides excellent sync FIFO patterns (FWFT, occupancy, dual-mode via generate), but has NO complete async FIFO template. The CDC reference only gives conceptual guidance ("use gray-coded pointers and full/empty checks") and a reset synchronizer snippet. The designer must derive the entire async FIFO from first principles including:
  - Binary pointer extension (+1 for wrap detection)
  - Binary-to-gray conversion
  - Gray-code full detection (two MSB inversion)
  - Gray-code empty detection (full equality)
  - 2FF synchronizer integration per domain
  - Dual asynchronous resets on synchronizer FFs
  - Memory with simultaneous independent write/read clocks
- **Concrete example**: To implement this design, I had to write a 120-line async FIFO from scratch combining concepts from multiple references (CDC guidelines + sync FIFO patterns + naming guidelines + bug patterns D1/D2). No single reference has a complete, synthesizable async FIFO.
- **Skill file to update**: `references/synthesis/cdc-guidelines.md` needs a complete async FIFO code section (analogous to the sync FIFO patterns in `references/rtl/fifo-examples.md`)
- **Severity**: Critical

### Gap 2: No CDC constraint guidance (.sdc / timing exceptions)
- **Description**: The skill references "Declare unrelated clocks with the project STA method, commonly set_clock_groups -asynchronous" but provides NO concrete SDC/tcl syntax, no guidance on what paths to set as false paths, no mention of `set_false_path` on synchronized signals vs `set_clock_groups` on clock domains, and no guidance on deriving generated clocks. In real CDC signoff, the constraint setup is as important as the RTL.
- **Concrete example**: After writing the async FIFO, there is no reference telling the user to add:
  ```
  set_clock_groups -asynchronous -group [get_clocks adc_clk] -group [get_clocks sys_clk]
  set_false_path -from [get_cells -hier -filter {NAME =~ *wr_gray_sync_q*}] -to [get_cells -hier -filter {NAME =~ *rd_ptr*}]  (not strictly needed after clock groups)
  ```
  Without these constraints, synthesis will try to balance CDC paths, adding buffers and violating the synchronizer's timing.
- **Skill file to update**: `references/synthesis/cdc-guidelines.md` needs a "CDC Constraints" subsection with concrete SDC examples
- **Severity**: High

### Gap 3: No metastability / MTBF discussion
- **Description**: The skill says "Mark synchronizer flops with ASYNC_REG" but never explains WHY (to prevent optimization and ensure adjacent placement for MTBF). There is no mention of:
  - MTBF calculation (and that 2FF is often insufficient at 400MHz+)
  - Required synchronizer depth vs clock frequency
  - The difference between slow-to-fast and fast-to-slow domain crossings
  - When 2FF is insufficient and 3FF is needed
  - The statistical nature of metastability (RTL simulation shows zero failures)
- **Concrete example**: This design has adc_clk at 400MHz. At this frequency, MTBF for a 2FF synchronizer can be unacceptably low depending on the technology node. The skill does not warn about this at all. It says "use a two-flop synchronizer" without discussing whether 2FF is sufficient for the given frequency.
- **Skill file to update**: `references/synthesis/cdc-guidelines.md` - add an "MTBF and Synchronizer Depth" section
- **Severity**: High

### Gap 4: Multi-clock testbench guidance missing
- **Description**: The skill's testbench template and simulation loop reference are entirely single-clock. There is no guidance on:
  - Generating two unrelated clocks with different frequencies and phase offsets
  - Randomizing clock phase for CDC stress testing
  - Waiting for CDC synchronization to complete before checking results
  - Scoreboard design for multi-domain data integrity
  - Timeout calculation across domains (each domain has different latency)
- **Concrete example**: The testbench for this design needs two clock generators, resynchronization of scoreboard data, and CDC latency tolerance in assertions. None of this is guided by the skill's references. The `simulation-loop.md` template has only one clock and one reset.
- **Skill file to update**: `references/verification/simulation-loop.md` and/or `references/verification/tb-examples.md`
- **Severity**: Medium

### Gap 5: No dual-clock dual-ASIC_REG synchronizer pattern
- **Description**: The reset synchronizer pattern in `references/synthesis/cdc-guidelines.md` has only ONE synchronizer and uses the domain clock and the async reset. However, an async FIFO needs TWO 2FF synchronizers (one per domain direction), each with its own clock and its own domain-specific reset. The skill's pattern only shows one direction.
- **Concrete example**: The async FIFO needs:
  ```verilog
  // wr_clk domain: synchronize rd_gray
  always @(posedge wr_clk_i) begin
    if (wr_rst_i) begin rd_gray_sync_q <= 0; rd_gray_sync_2q <= 0; end
    else begin rd_gray_sync_q <= rd_gray; rd_gray_sync_2q <= rd_gray_sync_q; end
  end
  // rd_clk domain: synchronize wr_gray
  always @(posedge rd_clk_i) begin
    if (rd_rst_i) begin wr_gray_sync_q <= 0; wr_gray_sync_2q <= 0; end
    else begin wr_gray_sync_q <= wr_gray; wr_gray_sync_2q <= wr_gray_sync_q; end
  end
  ```
  The skill's reset synchronizer pattern is a good start but doesn't scale to multi-domain designs with multiple synchronizer instances.
- **Skill file to update**: `references/synthesis/cdc-guidelines.md` - add a multi-domain synchronizer pattern
- **Severity**: Medium

### Gap 6: No guidance on CDC functional verification (data integrity)
- **Description**: The skill says "For async FIFO, check no overflow, no underflow, and one-bit gray pointer changes" and "Simulate with unrelated clock periods and varied phase offsets." But there is no concrete guidance on:
  - Data integrity scoreboarding across the CDC boundary
  - How to verify that no data is lost, duplicated, or reordered
  - How to handle the synchronization delay in scoreboard checks
  - Patterns for injecting gray code errors in simulation
- **Concrete example**: The testbench for this design needs to: (1) generate ADC samples with a known pattern, (2) push through the async FIFO, (3) collect AXI-Stream beats, (4) reassemble into 192-bit words, (5) compare against input. None of this scoreboard pattern is described in the skill's verification references.
- **Skill file to update**: `references/synthesis/cdc-guidelines.md` or `references/verification/verification-guidance.md`
- **Severity**: Medium

### Gap 7: No guidance on packing/unpacking patterns across CDC
- **Description**: The skill has width converter patterns in `references/patterns/width-converter-examples.md` and frame assembler patterns in `references/patterns/frame-assembler-examples.md`, but these are single-domain patterns. There is no guidance on:
  - Packing data in one clock domain and unpacking in another
  - How to handle the CDC boundary in a packer/unpacker system
  - Whether to pack before or after the CDC crossing
  - How the data width at the CDC boundary affects FIFO depth requirements
- **Concrete example**: This design packs 12-bit ADC samples into 192-bit words on adc_clk BEFORE the CDC FIFO. This is a deliberate choice (wider FIFO = fewer entries needed). But if the packing happened AFTER CDC (on sys_clk), the FIFO would need wider ports. The skill does not guide this tradeoff.
- **Skill file to update**: `references/architecture/micro-arch-decisions.md` or `references/synthesis/cdc-guidelines.md`
- **Severity**: Medium

### Gap 8: No register-vs-memory tradeoff guidance for async FIFO
- **Description**: The async FIFO RAM can be implemented as either registers or inferred SRAM. The skill's sync FIFO example uses register-based memory (`reg [DATA_WIDTH-1:0] mem [0:DEPTH-1]`), which is fine for small depths. But for async FIFOs, synthesis tools may not infer true dual-port SRAM, leading to suboptimal PPA. The skill doesn't discuss:
  - When to use register-based vs SRAM-based memory in async FIFOs
  - True dual-port vs simple dual-port SRAM requirements
  - How to ensure SRAM inference for async FIFOs
  - Width-vs-depth tradeoffs for async FIFO PPA
- **Concrete example**: This FIFO is 192x8 (192-bit wide, 8 deep). Register-based is acceptable, but for a wider/deeper async FIFO, the lack of SRAM guidance would lead to overuse of flops.
- **Skill file to update**: `references/synthesis/cdc-guidelines.md` or `references/design/power-timing-area.md`
- **Severity**: Low

---

## CDC-Specific Checklist

- [X] Async FIFO properly implemented (gray code pointers, 2FF synchronizers)
- [X] Reset synchronizer for each clock domain (two independent synchronizers)
- [X] No CDC paths without synchronization (all domain crossings go through the FIFO)
- [X] CDC timing constraints considered (documented as constraint SDC needed)
- [X] Metastability window documented (not in skill, documented as gap)
- [X] ASYNC_REG attribute on all synchronizer flip-flops
- [X] Multi-bit CDC uses gray code (not independent bit sync) - via async FIFO
- [X] Reset: async assertion, sync deassertion per domain
- [X] No combinational paths across clock domains
- [X] Data integrity scoreboard in testbench

### Gap 9: No testbench-drive guidance for multi-clock verification

- **Description**: The skill has no guidance on how to properly drive DUT inputs across multiple clock domains in simulation. The naive `@(posedge clk); data = value;` pattern causes double-sampling when the posedge fires at time 0 (due to reg initializer X→0 transition). This is a simulator-specific artifact (observed in Icarus Verilog) but the skill should document safe patterns.
- **Concrete evidence**: The `send_adc_samples` task originally used `@(posedge adc_clk); adc_data = value;` (drive after edge). In Icarus, the `@(posedge adc_clk)` fires at time 0 due to `reg adc_clk = 0;` initializing from X to 0, and the entire 32-sample test sequence runs in one delta cycle. Each sample is read TWICE by the DUT because the blocking assignment updates adc_data immediately and the always block re-triggers on the same time-0 edge.
  The debug output showed:
  ```
  PACKER_DEBUG: sample_cnt_q=0 adc_data_i=0 at t=0
  PACKER_DEBUG: sample_cnt_q=1 adc_data_i=0 at t=0  (same value, double-sampled!)
  ```
- **Fix**: Two changes were needed:
  1. Clock generation changed from `reg clk = 0; always #p clk = ~clk;` to `initial begin clk = 0; #p; forever #p clk = ~clk; end` to avoid time-0 X-reg transitions.
  2. Drive strategy changed from "drive on posedge" to "drive on negedge" to ensure data is stable on the sampling posedge: `@(negedge clk); data = value;`.
- **Lesson**: Multi-clock testbenches must explicitly avoid time-0 posedge events on clock init and should use opposite-edge drive patterns when the sampling edge is known.
- **Skill file to update**: `references/verification/tb-examples.md` or `references/verification/simulation-loop.md`
- **Severity**: Medium

---

## Simulation Results

All 6 test checks pass successfully with iverilog:

```
RESET_RELEASED
TEST_START test_1_basic_capture
TEST_PASS test_1
TEST_PASS test_1
TEST_START test_2_backpressure
TEST_PASS test_2
TEST_START test_3_fifo_stress
TEST_PASS test_3
TEST_START test_4_random_gaps
TEST_PASS test_4
TEST_START test_5_reset_recovery
TEST_PASS test_5
ALL_TESTS_PASS
SIMULATION_DONE
```

Test 1 has two checks (word count + data integrity), both pass. Data integrity is verified by a scoreboard that reconstructs 192-bit words from AXI-Stream beats and compares against the expected sample sequence. The expected word for samples 0..15 is:

```
bits [191:180] = 0 (sample 0, oldest)
bits [179:168] = 1 (sample 1)
...
bits [23:12]   = 14 (sample 14)
bits [11:0]    = 15 (sample 15, newest)
```

The AXI-Stream serializer outputs 6 beats per word (32-bit each), and the scoreboard correctly reassembles them.

### Bugs found and fixed during simulation

1. **Wire-in-always error (axis_serializer)**: Internal mux signals declared as `wire` but assigned in `always @(*)` blocks. Verilog requires `reg` for procedural assignments. Fixed by changing declarations to `reg`.

2. **Combinational loop in async_fifo (caused timeout)**: `full_o` and `empty_o` were combinational functions of next-pointers, creating delta-cycle oscillation through the write-enable path. Fixed by registering both `full_o` and `empty_o`.

3. **Testbench truncation**: `4'd16` passed to 5-bit parameter `count` truncated to 0. Fixed by using `5'd16`.

4. **Expected word computation**: The packer's shift register `{pack_buf_q[179:0], adc_data_i}` puts the FIRST received sample at the highest bit position (MSB), but `expected_word` initially computed the reverse order. Fixed by reversing the iteration: `(base + count - 1 - sw)` instead of `(base + sw)`.

5. **Time-0 posedge artifact (iverilog-specific)**: `reg clk = 0;` creates an X→0 transition at time 0 that iverilog treats as a posedge, causing the entire test sequence to run in a single delta cycle with double-sampled data. Fixed by using `initial begin clk = 0; #p; forever #p clk = ~clk; end` clock generation.

6. **Drive-after-edge double-sampling**: `@(posedge clk); data = value;` caused each sample to be read twice because the blocking assignment updated adc_data in the same time step as the posedge, and iverilog re-triggered the always block. Fixed by driving on negedge: `@(negedge clk); data = value;`.

```
test-cdc-capture/
  DEVELOPMENT_LOG.md       - This file
  rtl/
    adc_capture_top.v      - Top-level integration
    adc_sample_packer.v    - 12-bit -> 192-bit packer (adc_clk)
    async_fifo.v           - Async FIFO (CDC crossing)
    reset_synchronizer.v   - Reset synchronizer per domain
    axis_serializer.v      - 192-bit -> AXI-Stream serializer (sys_clk)
  tb/
    tb_top.v               - Testbench
  run_sim.sh               - Simulation script
