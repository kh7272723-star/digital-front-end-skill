`default_nettype none
`timescale 1ns / 1ps

// Testbench for ADC Capture Top (multi-clock CDC system).
//
// Generates two independent clocks:
//   adc_clk: 400MHz (period 2.5ns)
//   sys_clk: 100MHz (period 10ns)
//
// Test methodology:
//   - Generate ADC samples with known incrementing pattern
//   - Push through the CDC system
//   - Collect AXI-Stream beats and reassemble into words
//   - Compare input block data against output word data
//   - Apply backpressure and verify data integrity
//
// What simulation CAN verify: data integrity, FIFO full/empty,
//   AXI-Stream protocol, backpressure, reset.
// What simulation CANNOT verify: metastability, CDC timing,
//   ASYNC_REG placement, MTBF.

module tb_top;
    // -----------------------------------------------------------
    // Clock generation
    // -----------------------------------------------------------
    reg adc_clk;
    reg sys_clk;

    // adc_clk: 400MHz -> 2.5ns period.
    // Use initial+forever to avoid time-0 X→posedge artifact in some simulators.
    initial begin
        adc_clk = 0;
        #1.25;
        forever #1.25 adc_clk = ~adc_clk;
    end

    // sys_clk: 100MHz -> 10ns period
    initial begin
        sys_clk = 0;
        #5;
        forever #5 sys_clk = ~sys_clk;
    end

    // -----------------------------------------------------------
    // Reset
    // -----------------------------------------------------------
    reg rst_ni = 0;

    // -----------------------------------------------------------
    // Test control
    // -----------------------------------------------------------
    integer cycle_adc;
    integer cycle_sys;
    integer test_cnt;
    integer pass_cnt;
    integer fail_cnt;
    reg     sim_done;

    // ADC sample generation
    reg        adc_valid;
    reg [11:0] adc_data;

    // DUT connections
    wire       m_axis_tvalid;
    reg        m_axis_tready;
    wire [31:0] m_axis_tdata;
    wire        m_axis_tlast;

    // Scoreboard (existing)
    integer collected_beats;
    integer collected_words;
    reg [191:0] collected_word_data [0:127];
    integer word_idx;

    // Golden reference scoreboard (Strategy D: data integrity)
    reg [191:0] sb_expected [0:511];
    integer sb_wr_ptr;
    integer sb_rd_ptr;
    integer sb_errors;
    integer sb_checked;
    reg [191:0] sb_assembled;
    integer sb_beat_cnt;

    // -----------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------
    adc_capture_top dut (
        .rst_ni            (rst_ni),
        .adc_clk_i         (adc_clk),
        .adc_valid_i       (adc_valid),
        .adc_data_i        (adc_data),
        .sys_clk_i         (sys_clk),
        .m_axis_tvalid_o   (m_axis_tvalid),
        .m_axis_tready_i   (m_axis_tready),
        .m_axis_tdata_o    (m_axis_tdata),
        .m_axis_tlast_o    (m_axis_tlast)
    );

    // -----------------------------------------------------------
    // Clock domain cycle counters
    // -----------------------------------------------------------
    always @(posedge adc_clk) begin
        cycle_adc <= cycle_adc + 1;
    end

    always @(posedge sys_clk) begin
        cycle_sys <= cycle_sys + 1;
    end

    // -----------------------------------------------------------
    // Timeout watchdog (10ms)
    // -----------------------------------------------------------
    initial begin
        #10_000_000;
        if (!sim_done) begin
            $display("FAIL: simulation timeout at %0t", $time);
            $display("SIMULATION_DONE");
        end
        $finish;
    end

    // -----------------------------------------------------------
    // VCD dump
    // -----------------------------------------------------------
    initial begin
        $dumpfile("sim.vcd");
        $dumpvars(0, tb_top);
    end

    // -----------------------------------------------------------
    // Helper tasks
    // -----------------------------------------------------------

    // Reset sequence
    task reset;
        begin
            rst_ni = 1'b0;
            adc_valid = 1'b0;
            m_axis_tready = 1'b1;
            adc_data = 12'd0;

            // Hold reset for 20 adc_clk + 20 sys_clk cycles
            repeat (20) @(posedge adc_clk);
            repeat (20) @(posedge sys_clk);

            rst_ni = 1'b1;

            // Wait for reset synchronizers to release
            repeat (5) @(posedge adc_clk);
            repeat (5) @(posedge sys_clk);

            $display("RESET_RELEASED");
        end
    endtask

    // Check and report (avoid 'condition' which is a reserved word)
    task check;
        input integer   test_id;
        input           cond;
        input [255:0]   msg;
        begin
            if (cond) begin
                $display("TEST_PASS test_%0d", test_id);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("TEST_FAIL test_%0d: %0s", test_id, msg);
                fail_cnt = fail_cnt + 1;
            end
            test_cnt = test_cnt + 1;
        end
    endtask

    // Send N ADC samples.
    // Drives data on the falling edge of adc_clk so values are
    // stable when the DUT samples on the next rising edge.
    task send_adc_samples;
        input integer   count;
        input [11:0]    base_value;
        input           valid_every_cycle;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                @(negedge adc_clk);
                adc_data = base_value + i;
                if (valid_every_cycle || (i % 4 != 0))
                    adc_valid = 1'b1;
                else
                    adc_valid = 1'b0;
            end
            @(negedge adc_clk);
            adc_valid = 1'b0;
        end
    endtask

    // Compute expected word for N incrementing samples.
    // The packer uses a shift register: {pack_buf_q[179:0], new_data}
    // so the FIRST sample (base) ends up at the HIGHEST bit position,
    // and the LAST sample (base+count-1) ends up at bits [11:0].
    function [191:0] expected_word;
        input [11:0] base;
        input [4:0]  count;
        integer sw;
        reg [191:0] w;
        begin
            w = 192'd0;
            // Packer reverses order: first sample goes to highest bit slot
            for (sw = 0; sw < count; sw = sw + 1)
                w = w | (192'(base + count - 1 - sw) << (sw * 12));
            expected_word = w;
        end
    endfunction

    // -----------------------------------------------------------
    // Scoreboard: collect AXI-Stream output beats into words
    // -----------------------------------------------------------
    always @(posedge sys_clk) begin
        if (!rst_ni) begin
            collected_beats <= 0;
            collected_words <= 0;
            word_idx <= 0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            collected_beats <= collected_beats + 1;

            if (word_idx == 0) begin
                collected_word_data[collected_words] <= {160'd0, m_axis_tdata};
            end else begin
                collected_word_data[collected_words] <=
                    collected_word_data[collected_words] |
                    ({192'd0, m_axis_tdata} << (word_idx * 32));
            end

            if (m_axis_tlast) begin
                word_idx <= 0;
                collected_words <= collected_words + 1;
            end else begin
                word_idx <= word_idx + 1;
            end
        end
    end

    // -----------------------------------------------------------
    // Golden reference: input monitor (adc_clk domain)
    // Captures what ACTUALLY enters the FIFO, not what the packer outputs
    // -----------------------------------------------------------
    always @(posedge adc_clk) begin
        if (!rst_ni) begin
            sb_wr_ptr <= 0;
        end else if (dut.u_fifo.wr_do) begin
            sb_expected[sb_wr_ptr] <= dut.u_fifo.wdata_i;
            sb_wr_ptr <= sb_wr_ptr + 1;
        end
    end

    // -----------------------------------------------------------
    // Golden reference: output checker (sys_clk domain)
    // Reassembles 6 AXI-Stream beats into 192-bit word, compares
    // -----------------------------------------------------------
    always @(posedge sys_clk) begin
        if (!rst_ni) begin
            sb_rd_ptr   <= 0;
            sb_beat_cnt <= 0;
            sb_assembled <= 192'd0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            sb_assembled <= sb_assembled | ({192'd0, m_axis_tdata} << (sb_beat_cnt * 32));
            sb_beat_cnt <= sb_beat_cnt + 1;
            if (m_axis_tlast) begin
                if (sb_rd_ptr < sb_wr_ptr) begin
                    if (sb_assembled !== sb_expected[sb_rd_ptr]) begin
                        $display("GOLDEN_FAIL word %0d: data mismatch", sb_rd_ptr);
                        $display("  actual   = %h", sb_assembled);
                        $display("  expected = %h", sb_expected[sb_rd_ptr]);
                        sb_errors = sb_errors + 1;
                    end
                    sb_checked = sb_checked + 1;
                end
                sb_rd_ptr <= sb_rd_ptr + 1;
                sb_beat_cnt <= 0;
                sb_assembled <= 192'd0;
            end
        end
    end

    // -----------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------
    initial begin
        // Initialize
        cycle_adc = 0;
        cycle_sys = 0;
        test_cnt  = 0;
        pass_cnt  = 0;
        fail_cnt  = 0;
        sim_done  = 1'b0;
        collected_beats = 0;
        collected_words = 0;
        word_idx = 0;
        sb_wr_ptr = 0;
        sb_rd_ptr = 0;
        sb_errors = 0;
        sb_checked = 0;
        sb_beat_cnt = 0;
        sb_assembled = 192'd0;

        reset;

        // -------------------------------------------------------
        // Test 1: Basic capture - 32 ADC samples -> 2 blocks -> 12 beats
        // -------------------------------------------------------
        $display("TEST_START test_1_basic_capture");
        begin : t1
            integer w_before;

            w_before = collected_words;

            // Send 32 ADC samples (2 blocks of 16, incrementing from 0)
            send_adc_samples(32, 12'd0, 1'b1);

            // Wait for CDC crossing + serialization
            repeat (500) @(posedge sys_clk);

            // Check we got at least 1 word
            check(1, collected_words > w_before,
                "No words received after basic capture");

            // Check first word data integrity (if available)
            if (collected_words > w_before) begin
                reg [191:0] exp;
                // Samples 0..15 -> base=0, 16 samples
                exp = expected_word(12'd0, 5'd16);
                // Debug: show actual vs expected on mismatch
                if (collected_word_data[w_before] !== exp) begin
                    $display("  DEBUG test_1: word[%0d] mismatch", w_before);
                    $display("    actual[191:0]   = %h", collected_word_data[w_before]);
                    $display("    expected[191:0] = %h", exp);
                    $display("    actual[63:0]    = %h", collected_word_data[w_before][63:0]);
                    $display("    expected[63:0]  = %h", exp[63:0]);
                    $display("    actual[127:64]  = %h", collected_word_data[w_before][127:64]);
                    $display("    expected[127:64]= %h", exp[127:64]);
                    $display("    actual[191:128] = %h", collected_word_data[w_before][191:128]);
                    $display("    expected[191:128]=%h", exp[191:128]);
                end
                check(1, collected_word_data[w_before] == exp,
                    "First word data mismatch");
            end
        end

        // -------------------------------------------------------
        // Test 2: Backpressure (TREADY gated during capture)
        // -------------------------------------------------------
        $display("TEST_START test_2_backpressure");
        begin : t2
            integer w_before;

            w_before = collected_words;

            // Send ADC samples while TREADY is low (backpressure)
            m_axis_tready = 1'b0;

            fork
                begin : stim
                    send_adc_samples(32, 12'd100, 1'b1);
                end
                begin : bp
                    repeat (200) @(posedge sys_clk);
                    m_axis_tready = 1'b1;
                end
            join

            // Wait for drain
            repeat (1000) @(posedge sys_clk);

            check(2, collected_words > w_before,
                "No output after backpressure test");
        end

        // -------------------------------------------------------
        // Test 3: FIFO stress (256 samples = 16 blocks, depth-8 FIFO)
        // -------------------------------------------------------
        $display("TEST_START test_3_fifo_stress");
        begin : t3
            integer w_before;

            w_before = collected_words;
            m_axis_tready = 1'b1;

            send_adc_samples(256, 12'd50, 1'b1);

            repeat (2000) @(posedge sys_clk);

            check(3, collected_words > w_before + 8,
                "Insufficient words after FIFO stress");
        end

        // -------------------------------------------------------
        // Test 4: Non-consecutive valid (random gaps)
        // -------------------------------------------------------
        $display("TEST_START test_4_random_gaps");
        begin : t4
            integer w_before;

            w_before = collected_words;
            m_axis_tready = 1'b1;

            // Send with 75% valid duty cycle
            send_adc_samples(48, 12'd200, 1'b0);

            repeat (2000) @(posedge sys_clk);

            check(4, collected_words > w_before,
                "No output after random gaps test");
        end

        // -------------------------------------------------------
        // Test 5: Reset recovery
        // -------------------------------------------------------
        $display("TEST_START test_5_reset_recovery");
        begin : t5
            integer w_after;

            // Assert reset
            rst_ni = 1'b0;
            adc_valid = 1'b0;
            repeat (10) @(posedge adc_clk);
            repeat (10) @(posedge sys_clk);

            // Check reset state
            repeat (5) @(posedge sys_clk);

            // Release reset
            rst_ni = 1'b1;
            repeat (10) @(posedge adc_clk);
            repeat (10) @(posedge sys_clk);

            // Send data after reset
            send_adc_samples(32, 12'd0, 1'b1);
            repeat (1000) @(posedge sys_clk);

            w_after = collected_words;

            check(5, w_after > 0,
                "No output after reset recovery");
        end

        // -------------------------------------------------------
        // Test 6: Golden reference — known pattern through CDC
        // -------------------------------------------------------
        $display("TEST_START test_6_golden_integrity");
        begin : t6
            integer w_before;
            integer sb_before;

            w_before = collected_words;
            sb_before = sb_checked;

            // Reset scoreboard pointers for clean test
            sb_errors = 0;

            // Drive 32 known ADC samples (2 blocks)
            send_adc_samples(32, 12'hA00, 1'b1);

            // Wait for CDC crossing + serialization + drain
            repeat (2000) @(posedge sys_clk);

            if (sb_errors == 0 && sb_checked > sb_before)
                $display("GOLDEN_PASS test_6: %0d words checked, 0 errors", sb_checked - sb_before);
            else
                $display("GOLDEN_FAIL test_6: %0d words checked, %0d errors", sb_checked - sb_before, sb_errors);

            check(6, sb_errors == 0 && sb_checked > sb_before,
                "Data integrity failed through CDC");
        end

        // -------------------------------------------------------
        // Summary
        // -------------------------------------------------------
        if (fail_cnt == 0)
            $display("ALL_TESTS_PASS");
        else
            $display("FAIL: %0d of %0d tests failed", fail_cnt, test_cnt);

        sim_done = 1'b1;
        $display("SIMULATION_DONE");
        $finish;
    end

endmodule

`default_nettype wire
