# Verilog testbench example patterns

## Source policy
Use testbench examples that are small, directed, and easy to extend.
Prefer plain Verilog testbench structure unless the user specifically asks for SystemVerilog features.

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
