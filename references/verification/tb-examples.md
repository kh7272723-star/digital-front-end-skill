
# Verilog testbench example patterns

## Source policy
Use testbench examples that are small, directed, and easy to extend.
Prefer plain Verilog testbench structure unless the user specifically asks for SystemVerilog features.

**Before writing any testbench:** Read `references/verification/icarus-common-pitfalls.md` — 15 documented Icarus-specific pitfalls that have wasted simulation iterations across R5-R8 experiments. Most are 2-line fixes.

---

## 0. Standard Testbench Skeleton (START HERE)

**Source:** Clock generation (safe, no time-0 posedge): Cummings, SNUG 1999 §2 (inertial delay for initial clock edge). Output protocol markers: Accellera UVM 1.2 §4.9 (end-of-test phasing), adapted for plain Verilog. Error accumulation vs $finish-on-first-fail: Mentor/Siemens Verification Academy (regression methodology). Reset sequence: Cummings & Mills, SNUG 2002 "Asynchronous & Synchronous Reset Design Techniques" §4.2.

This skeleton includes safe clock generation, error accumulation, output protocol markers, and timeout watchdog. Copy this template as your starting point, then add your DUT-specific tests.

```verilog
`default_nettype none
`timescale 1ns / 1ps

module tb_<name>;
    //========================================================================
    // Parameters
    //========================================================================
    parameter CLK_PERIOD = 20;   // 50 MHz = 20 ns
    parameter MAX_TIME   = 1_000_000;  // 1 ms timeout

    //========================================================================
    // DUT signals
    //========================================================================
    reg        clk_i;
    reg        rst_ni;
    // ... add your DUT I/O signals here ...

    //========================================================================
    // DUT instantiation
    //========================================================================
    <dut_name> #(
        .PARAM_A(VAL_A),
        .PARAM_B(VAL_B)
    ) u_dut (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),
        // ... ports ...
    );

    //========================================================================
    // Clock generation (safe — no time-0 posedge)
    //========================================================================
    initial begin
        clk_i = 1'b0;
        #(CLK_PERIOD/2);
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    //========================================================================
    // Reset sequence
    //========================================================================
    initial begin
        rst_ni = 1'b0;
        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (4) @(posedge clk_i);
        $display("RESET_RELEASED");
    end

    //========================================================================
    // Error counter and timeout
    //========================================================================
    integer error_cnt;
    initial error_cnt = 0;

    initial begin
        #MAX_TIME;
        $display("FAIL: SIMULATION_TIMEOUT at %0t", $time);
        $finish;
    end

    //========================================================================
    // Main test sequence
    //========================================================================
    initial begin
        $display("SIMULATION_START");
        wait(rst_ni === 1'b1);
        repeat (4) @(posedge clk_i);

        // Test 1: Reset check
        test_reset();
        // Test 2: ...
        // test_xxx();

        // Summary
        if (error_cnt == 0)
            $display("ALL_TESTS_PASS");
        else
            $display("FAIL: %0d errors", error_cnt);
        $display("SIMULATION_DONE");
        $finish;
    end

    //========================================================================
    // APB Bus Functional Model (write/read/check tasks)
    //========================================================================
    // See APB BFM section below — copy those tasks here

    //========================================================================
    // Test tasks — one per test
    //========================================================================
    task test_reset;
    begin : task_body
        $display("TEST_START test_reset");
        @(negedge clk_i);
        rst_ni = 1'b0;
        repeat (4) @(posedge clk_i);
        // Check DUT outputs at reset
        if (tx_o !== 1'b1) begin
            $display("FAIL: tx_o=%b at reset, expected 1", tx_o);
            error_cnt = error_cnt + 1;
        end
        rst_ni = 1'b1;
        repeat (4) @(posedge clk_i);
        $display("TEST_PASS test_reset");
    end
    endtask

    // ... add more test tasks ...
endmodule
`default_nettype wire
```

**Checklist before running simulation:**
- [ ] Clock: `initial begin clk=0; #p/2; forever #p/2 clk=~clk; end` (NOT `reg clk=0; always`)
- [ ] Reset: `RESET_RELEASED` marker after reset deassertion
- [ ] Timeout: wall-clock `#MAX_TIME` (not cycle-based)
- [ ] Errors: accumulated in `error_cnt`, never `$finish` on first failure
- [ ] Protocol: `SIMULATION_START` → `RESET_RELEASED` → `TEST_START/PASS` → `ALL_TESTS_PASS` → `SIMULATION_DONE`
- [ ] Pitfalls scanned: see `icarus-common-pitfalls.md` A1-A5, B1-B5, C1-C2, D1-D2

---

## APB Bus Functional Model

**Source:** ARM IHI 0024C (AMBA APB Protocol) §3.1: APB state machine defines SETUP (PSEL=1, PENABLE=0) and ACCESS (PSEL=1, PENABLE=1) phases. §3.2: write transfer timing — PADDR/PWDATA/PWRITE must be stable from SETUP through ACCESS. §4.1: PSLVERR is combinational from PADDR, valid only during ACCESS. §2.1: signal definitions for PSEL, PENABLE, PADDR, PWRITE, PWDATA, PRDATA, PREADY, PSLVERR.

Copy these tasks into your testbench for standardized APB register access. Handles SETUP→ACCESS phase timing, PSLVERR checking, and combinational output timing.

```verilog
// APB BFM — standard for all APB slave testbenches
reg        apb_psel;
reg        apb_penable;
reg [5:0]  apb_paddr;
reg        apb_pwrite;
reg [31:0] apb_pwdata;
wire [31:0] apb_prdata;
wire       apb_pready;
wire       apb_pslverr;

// Connect to DUT
assign psel_i    = apb_psel;
assign penable_i = apb_penable;
assign paddr_i   = apb_paddr;
assign pwrite_i  = apb_pwrite;
assign pwdata_i  = apb_pwdata;

//========================================================================
// APB Write — standard SETUP→ACCESS sequence
//========================================================================
task apb_write;
    input [5:0]  addr;
    input [31:0] data;
begin
    // SETUP phase
    @(negedge clk_i);
    apb_psel    = 1'b1;
    apb_penable = 1'b0;
    apb_paddr   = addr;
    apb_pwrite  = 1'b1;
    apb_pwdata  = data;
    // ACCESS phase
    @(negedge clk_i);
    apb_penable = 1'b1;
    @(negedge clk_i);
    // Cleanup
    apb_psel    = 1'b0;
    apb_penable = 1'b0;
end
endtask

//========================================================================
// APB Read — returns data read from bus
//========================================================================
reg [31:0] apb_rdata;
task apb_read;
    input [5:0] addr;
begin
    // SETUP phase
    @(negedge clk_i);
    apb_psel    = 1'b1;
    apb_penable = 1'b0;
    apb_paddr   = addr;
    apb_pwrite  = 1'b0;
    // ACCESS phase
    @(negedge clk_i);
    apb_penable = 1'b1;
    @(negedge clk_i);
    // Sample BEFORE deassert — PRDATA is combinational from address
    apb_rdata = prdata_o;
    // Cleanup
    apb_psel    = 1'b0;
    apb_penable = 1'b0;
end
endtask

//========================================================================
// APB Write + Read-back check (golden reference Strategy C)
//========================================================================
task apb_check_reg;
    input [5:0]  addr;
    input [31:0] wr_data;
    input [31:0] expected;  // may differ from wr_data due to read-only bits
begin
    apb_write(addr, wr_data);
    repeat (2) @(posedge clk_i);  // let write settle
    apb_read(addr);
    if (apb_rdata !== expected) begin
        $display("FAIL: reg@%02h readback — got %08h, expected %08h",
                 addr, apb_rdata, expected);
        error_cnt = error_cnt + 1;
    end else begin
        $display("READBACK_PASS @%02h: %08h", addr, apb_rdata);
    end
end
endtask

//========================================================================
// APB PSLVERR check — write to invalid address, expect PSLVERR
//========================================================================
task apb_check_pslverr;
    input [5:0] addr;
begin
    @(negedge clk_i);
    apb_psel    = 1'b1;
    apb_penable = 1'b0;
    apb_paddr   = addr;
    apb_pwrite  = 1'b1;
    apb_pwdata  = 32'h0;
    @(negedge clk_i);
    apb_penable = 1'b1;
    @(negedge clk_i);
    // Check PSLVERR BEFORE deassert — it's combinational from address
    if (pslverr_o !== 1'b1) begin
        $display("FAIL: PSLVERR not asserted for invalid addr %02h", addr);
        error_cnt = error_cnt + 1;
    end else begin
        $display("PSLVERR_PASS @%02h", addr);
    end
    apb_psel    = 1'b0;
    apb_penable = 1'b0;
end
endtask
```

**APB BFM key rules:**
1. Drive on `@(negedge clk_i)` — stable before DUT samples on posedge (pitfall B4)
2. Sample PRDATA/PSLVERR in ACCESS phase BEFORE deasserting PSEL (pitfall B2)
3. Two-cycle SETUP→ACCESS sequence per APB spec
4. `apb_check_reg` includes a 2-cycle settle delay between write and read

---

## AXI-Stream BFM Tasks

**Source:** ARM IHI 0051B (AMBA AXI-Stream Protocol) §2.2: TVALID/TREADY handshake — TVALID must not depend on TREADY; TREADY may depend on TVALID. Payload (TDATA/TKEEP/TLAST) stable while TVALID=1 and TREADY=0. §3.1: TLAST marks last beat of a packet; TKEEP indicates valid byte lanes. Negedge drive: IEEE 1364-2001 §5.5 / Cummings SNUG 2000 §8.2.

```verilog
//========================================================================
// AXI-Stream Send (master → DUT slave port)
// Drives on negedge, holds until handshake
//========================================================================
task axis_send_beat;
    input [DATA_W-1:0] data;
    input              tlast;
    input [KEEP_W-1:0] tkeep;
begin
    @(negedge clk_i);
    s_axis_tdata_i  = data;
    s_axis_tkeep_i  = tkeep;
    s_axis_tlast_i  = tlast;
    s_axis_tvalid_i = 1'b1;
    // Wait for handshake
    @(negedge clk_i);
    while (!s_axis_tready_o) @(negedge clk_i);
    s_axis_tvalid_i = 1'b0;
end
endtask

//========================================================================
// AXI-Stream Receive (DUT master → slave checker)
// Samples on posedge with #1 settling delay
//========================================================================
task axis_recv_beat;
    output [DATA_W-1:0] data;
    output              tlast;
    output [KEEP_W-1:0] tkeep;
begin
    // Wait for handshake
    @(posedge clk_i);
    while (!(m_axis_tvalid_o && m_axis_tready_i)) @(posedge clk_i);
    #1;  // settling delay (pitfall B3)
    data  = m_axis_tdata_o;
    tkeep = m_axis_tkeep_o;
    tlast = m_axis_tlast_o;
end
endtask

//========================================================================
// AXI-Stream packet send (multi-beat, auto TLAST)
//========================================================================
task axis_send_packet;
    input [7:0] n_beats;  // number of beats in this packet
begin
    for (k = 0; k < n_beats; k = k + 1) begin : pkt_loop
        axis_send_beat(test_data[k], (k == n_beats - 1), {KEEP_W{1'b1}});
        if (k == n_beats - 1) disable pkt_loop;  // safe exit (pitfall A2)
    end
end
endtask
```

**AXI-Stream BFM key rules:**
1. Send: drive on negedge, wait for tready handshake
2. Receive: sample on posedge with `#1` settling delay
3. TLAST on last beat of packet; TKEEP = all-1s unless byte-enable needed
4. Never use `break` in loops — use named block + `disable` (pitfall A2)

---

## 1. Basic clock and reset

```verilog
reg clk_i;
reg rst_i;

initial begin
  clk_i = 1'b0;
  forever #5 clk_i = ~clk_i;
end

initial begin
  rst_i = 1'b1;
  repeat (4) @(posedge clk_i);
  rst_i = 1'b0;
end
```

Pattern rule:
- keep clock generation simple
- release reset in a controlled way
- make reset duration explicit

## 2. Directed stimulus block

```verilog
initial begin
  wait(!rst_i);
  @(posedge clk_i);

  din = 8'h11;
  valid = 1'b1;
  ready = 1'b1;
  @(posedge clk_i);

  valid = 1'b0;
  @(posedge clk_i);
end
```

Pattern rule:
- drive one scenario at a time
- keep stimuli readable
- align stimulus changes to the clock

## 3. Simple check block

```verilog
always @(posedge clk_i) begin
  if (!rst_i) begin
    if (valid && ready) begin
      if (dout !== expected)
        $display("Mismatch at %0t", $time);
    end
  end
end
```

Pattern rule:
- put checks close to the expected event
- compare at the cycle when the result should be visible
- report failures with time context

## 4. Task-based stimulus idea

```verilog
task send_byte;
  input [7:0] data;
  begin
    @(posedge clk_i);
    din = data;
    valid = 1'b1;
    @(posedge clk_i);
    valid = 1'b0;
  end
endtask
```

Pattern rule:
- use tasks to reuse common actions
- keep each task focused on one protocol action
- avoid hiding timing in too much abstraction

## 5. Safe clock generation (avoid Icarus time-0 edge artifact)

**Source:** IEEE 1800-2017 Section 4.8 (Race conditions); Cliff Cummings SNUG 2000 "Nonblocking Assignments in Verilog Synthesis."

The naive pattern `reg clk = 0; always #5 clk = ~clk;` causes an X→0 transition at simulation time 0 that Icarus Verilog treats as a posedge. This fires `@(posedge clk)` before any test stimulus is set up.

**Safe pattern (always use this):**

```verilog
// NO: reg clk = 0; always #5 clk = ~clk;   // triggers posedge at time 0
// OK:
initial begin
    clk_i = 1'b0;
    #(CLK_PERIOD/2);     // wait half period before first edge
    forever #(CLK_PERIOD/2) clk_i = ~clk_i;
end
```

This ensures:
- First clock edge arrives at `CLK_PERIOD/2`, not time 0
- The testbench has time to initialize signals before the first sampling edge
- Consistent behavior across Verilator, Icarus, and commercial simulators

For multi-clock testbenches, apply this pattern to EVERY clock:

```verilog
initial begin
    clk_fast_i = 1'b0;
    #(CLK_FAST_PERIOD/2);
    forever #(CLK_FAST_PERIOD/2) clk_fast_i = ~clk_fast_i;
end

initial begin
    clk_slow_i = 1'b0;
    #(CLK_SLOW_PERIOD/2);
    forever #(CLK_SLOW_PERIOD/2) clk_slow_i = ~clk_slow_i;
end
```

## 6. Drive-on-negedge pattern (multi-clock stimulus)

**Source:** IEEE 1800-2017 Section 4.7 (Nondeterminism in scheduling semantics).

When driving DUT inputs that are sampled on posedge, drive stimulus on the NEGEDGE. This eliminates a delta-cycle race where the DUT's `always @(posedge clk)` samples the new stimulus value (driven on the same posedge via blocking assignment) in the same time step.

```verilog
// Drive on negedge: data is stable when DUT samples on next posedge
task send_beat;
    input [31:0] data;
    input        last;
begin
    @(negedge clk_i);
    s_axis_tdata_i  = data;
    s_axis_tlast_i  = last;
    s_axis_tvalid_i = 1'b1;
    @(negedge clk_i);
    s_axis_tvalid_i = 1'b0;
end
endtask
```

Apply this pattern for:
- Multi-clock testbenches (each domain drives on its own negedge)
- Any testbench where DUT samples on the same clock edge that the testbench drives on
- CDC testbenches where clock phase relationships matter

## 7. Settling delay after clock edges in monitors

**Source:** Cliff Cummings, "Correct Methods For Adding Delays To Verilog Behavioral Models," SNUG 1999.

When a monitor or checker samples combinational DUT outputs after `@(posedge clk_i)`, the NBA (nonblocking assignment) region has not yet executed. The sampled value reflects the PREVIOUS cycle's state. Add `#1` (one time unit) after each posedge wait to settle:

```verilog
// Monitor/checker task with settling delay
task expect_data;
    input [31:0] expected;
    input [3:0]  expected_strb;
begin
    // Wait for posedge where valid should be asserted
    @(posedge clk_i);
    #1;  // let NBAs settle — NOW we see current-cycle values

    if (s_axis_tdata_o !== expected) begin
        $display("FAIL: data mismatch at %0t: got %08h, expected %08h",
                 $time, s_axis_tdata_o, expected);
        error_cnt = error_cnt + 1;
    end
end
endtask
```

**Rule:** Every monitor/checker task MUST have `#1` after `@(posedge clk_i)` before sampling combinational outputs. Stimulus tasks (driving inputs) do NOT need settling delays — they drive on negedge per pattern 6.

## 8. Multi-clock testbench template

**Source:** Adapted from skill simulation-loop.md single-clock template; CDC verification best practices from Doulos and Verilab.

```verilog
`default_nettype none
`timescale 1ns / 1ps

module tb_<name>;
    // Clocks
    reg clk_fast_i;
    reg clk_slow_i;
    reg rst_ni;          // active-low async reset

    // Clock parameters
    parameter FAST_PERIOD = 2.5;   // 400 MHz: 2.5 ns
    parameter SLOW_PERIOD = 10.0;  // 100 MHz: 10 ns
    parameter MAX_CYCLES   = 10000;

    // DUT interfaces (fast domain, slow domain, ...)

    // DUT instantiation
    <name> u_dut (
        .clk_fast_i(clk_fast_i),
        .clk_slow_i(clk_slow_i),
        .rst_ni(rst_ni),
        // ... ports
    );

    //========================================================================
    // Clock generation (safe pattern — no time-0 posedge)
    //========================================================================
    initial begin
        clk_fast_i = 1'b0;
        #(FAST_PERIOD/2);
        forever #(FAST_PERIOD/2) clk_fast_i = ~clk_fast_i;
    end

    initial begin
        clk_slow_i = 1'b0;
        #(SLOW_PERIOD/2);
        forever #(SLOW_PERIOD/2) clk_slow_i = ~clk_slow_i;
    end

    //========================================================================
    // Cycle counters per domain (for hang detection and debug)
    //========================================================================
    integer cycle_fast;
    integer cycle_slow;

    always @(posedge clk_fast_i) cycle_fast <= cycle_fast + 1;
    always @(posedge clk_slow_i) cycle_slow <= cycle_slow + 1;

    //========================================================================
    // Timeout watchdog — uses wall-clock time, not cycles
    //========================================================================
    initial begin
        #1_000_000;  // 1 ms
        $display("FAIL: SIMULATION_TIMEOUT at %0t (fast=%0d slow=%0d cycles)",
                 $time, cycle_fast, cycle_slow);
        $finish;
    end

    //========================================================================
    // Scoreboard (reassembles cross-domain data for integrity checking)
    //========================================================================
    reg [DATA_W-1:0] expected_queue [0:255];
    integer          q_wr_ptr;
    integer          q_rd_ptr;

    // Fast-domain monitor: enqueue expected data on each ADC sample
    always @(negedge clk_fast_i) begin   // negedge — safe for sampling
        if (adc_valid_o) begin
            expected_queue[q_wr_ptr] = assemble_expected(...);
            q_wr_ptr = q_wr_ptr + 1;
        end
    end

    // Slow-domain checker: dequeue on each output beat
    wire output_fire = m_axis_tvalid_o && m_axis_tready_i;

    always @(posedge clk_slow_i) begin
        #1;  // settling delay
        if (output_fire && !rst_ni_synced) begin
            if (m_axis_tdata_o !== expected_queue[q_rd_ptr]) begin
                $display("FAIL: data integrity at %0t", $time);
                error_cnt = error_cnt + 1;
            end
            q_rd_ptr = q_rd_ptr + 1;
        end
    end

    //========================================================================
    // Reset sequence
    //========================================================================
    initial begin
        rst_ni = 1'b0;
        repeat (10) @(posedge clk_slow_i);  // hold reset
        rst_ni = 1'b1;
        // Wait for CDC synchronization latency (~3-8 slow cycles)
        repeat (20) @(posedge clk_slow_i);
        $display("RESET_RELEASED");
    end

    //========================================================================
    // Main test sequence
    //========================================================================
    initial begin
        error_cnt = 0;
        q_wr_ptr  = 0;
        q_rd_ptr  = 0;

        // Wait for reset release
        wait (rst_ni === 1'b1);
        repeat (20) @(posedge clk_slow_i);  // CDC sync delay

        // Test 1: Normal transfer
        $display("TEST_START test_1_normal");
        // ... drive on negedge ...
        // ... check on posedge with #1 ...
        $display("TEST_PASS test_1");

        // ... more tests ...

        // Summary
        if (error_cnt == 0)
            $display("ALL_TESTS_PASS");
        else
            $display("FAIL: %0d errors", error_cnt);
        $display("SIMULATION_DONE");
        $finish;
    end

endmodule
`default_nettype wire
```

### Multi-clock TB checklist

- [ ] Every clock uses `initial begin clk=0; #period/2; forever #period/2 clk=~clk; end` (no `reg clk=0; always`)
- [ ] Stimulus tasks drive on negedge of the DUT's sampling clock
- [ ] Monitor tasks sample after `@(posedge clk); #1;`
- [ ] CDC latency is accounted for in scoreboard timing and test expectations
- [ ] Timeout is based on wall-clock time, not a single domain's cycle count
- [ ] Scoreboard handles CDC synchronization delay (use FIFOs or delayed comparison)
- [ ] Driver/monitor tasks do NOT mix signals from different clock domains

## 9. Golden reference testbench patterns

These patterns implement the golden reference methodology from `golden-reference-guide.md`. Use them to add functional checking to any testbench.

### 9a. Known I/O pair checker (computation modules)

```verilog
// Golden I/O: check known input->output pairs
// Use for CRC, ECC, ALU, encoder/decoder
// Expected values from authoritative source (IEEE 802.3, ISA spec, etc.)
task check_golden;
    input [IN_W-1:0]  test_in;
    input [OUT_W-1:0] expected;
    input [255:0]     name;
    reg [OUT_W-1:0]   actual;
begin
    din_i = test_in;
    valid_i = 1'b1;
    @(posedge clk_i); #1;
    valid_i = 1'b0;
    // Wait for module-specific latency
    repeat (LATENCY) begin @(posedge clk_i); #1; end
    actual = dout_o;
    if (actual !== expected) begin
        $display("GOLDEN_FAIL %0s: in=%08h got=%08h exp=%08h",
                 name, test_in, actual, expected);
        fail_cnt = fail_cnt + 1;
    end else begin
        $display("GOLDEN_PASS %0s", name);
    end
end
endtask
```

### 9b. Write-readback scoreboard (register modules)

```verilog
// Write a value to a register, read it back, compare
// Use for APB/AXI-Lite register blocks
//
// PITFALL: Bus read data (PRDATA, RDATA) is often combinational from
// the current address. If the bus idle task clears the address after
// the read, PRDATA changes to the value at address 0x0.
// FIX: Sample PRDATA BEFORE calling idle_bus(), or check register
// output pins directly (reg0_o, reg1_o).
task check_reg_readback;
    input [ADDR_W-1:0] addr;
    input [DATA_W-1:0] wr_data;
    input [STRB_W-1:0] wr_strb;
    reg [DATA_W-1:0] expected;
begin
    bus_write(addr, wr_data, wr_strb);
    bus_read(addr);
    // Expected: wr_data masked by strb, OR'd with reset default for unmasked bits
    expected = (wr_data & strb_to_mask(wr_strb)) |
               (RESET_DEFAULT & ~strb_to_mask(wr_strb));
    if (rdata_o !== expected) begin
        $display("READBACK_FAIL @%08h: got=%08h exp=%08h",
                 addr, rdata_o, expected);
        fail_cnt = fail_cnt + 1;
    end else begin
        $display("READBACK_PASS @%08h", addr);
    end
end
endtask
```

### 9c. Data integrity scoreboard (data movement modules)

```verilog
// Scoreboard: enqueue expected on input, dequeue and compare on output
// Use for DMA, FIFO, width converter, stream buffer
reg [DATA_W-1:0] sb_queue [0:255];
integer sb_wr, sb_rd;

initial begin sb_wr = 0; sb_rd = 0; end

// Input monitor: enqueue on input handshake
always @(posedge clk_i) begin
    if (rst_i) begin
        sb_wr <= 0;
    end else if (in_valid && in_ready) begin
        sb_queue[sb_wr] <= in_data;
        sb_wr <= sb_wr + 1;
    end
end

// Output checker: dequeue and compare on output handshake
always @(posedge clk_i) begin
    #1;
    if (!rst_i && out_valid && out_ready) begin
        if (out_data !== sb_queue[sb_rd]) begin
            $display("INTEGRITY_FAIL beat %0d: got=%08h exp=%08h",
                     sb_rd, out_data, sb_queue[sb_rd]);
            fail_cnt = fail_cnt + 1;
        end
        sb_rd = sb_rd + 1;
    end
end
```

### 9d. Invariant checker (stateful modules)

```verilog
// Continuous invariant checks — run every cycle after reset
// Use for arbiters, credit counters, FSMs
//
// PITFALL: For registered outputs (e.g., valid_o), do NOT check
// relationships with combinational inputs every cycle — registered
// outputs hold while inputs change, causing false violations.
// Check "no grant without request" only at grant time.
//
// PITFALL: Use pre-edge sampling to avoid race conditions with
// DUT combinational logic settling.

// Pre-edge capture (non-blocking, same posedge as DUT)
reg ready_o_pre;
reg [N-1:0] valid_i_pre;
always @(posedge clk_i) begin
    ready_o_pre <= ready_o;
    valid_i_pre <= valid_i;
end

// Invariant checks (after #1 settle)
always @(posedge clk_i) begin
    #1;
    if (!rst_i) begin
        // INV1: grant must be one-hot or zero
        if (grant_o !== 0 && !$onehot(grant_o)) begin
            $display("INVARIANT_FAIL at %0t: grant=%b not one-hot",
                     $time, grant_o);
            fail_cnt = fail_cnt + 1;
        end
        // INV2: no grant without request (check ONLY at grant time)
        if (ready_o_pre !== 0) begin
            if (!valid_i_pre[grant_o]) begin
                $display("INVARIANT_FAIL at %0t: grant without request", $time);
                fail_cnt = fail_cnt + 1;
            end
        end
        // INV3: counter must not exceed maximum
        if (credit_q > MAX_CREDIT) begin
            $display("INVARIANT_FAIL at %0t: credit overflow %0d",
                     $time, credit_q);
            fail_cnt = fail_cnt + 1;
        end
    end
end
```

## What to capture from testbench examples
- reset sequencing
- transaction timing
- boundary cases
- scoreboard or compare logic
- how to make failing behavior easy to inspect
- **Safe clock generation: use `initial #p forever #p clk=~clk`, never `reg clk=0; always`**
- **Drive-on-negedge for stimulus in multi-clock testbenches**
- **#1 settling delay in all monitor/checker tasks**
- **CDC latency tolerance in cross-domain scoreboards**
- **Golden reference checks: known I/O pairs, readback scoreboard, data integrity, invariants**
