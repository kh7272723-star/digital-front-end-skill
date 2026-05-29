`default_nettype none
`timescale 1ns / 1ps

module tb_pipeline_reg;
    parameter DATA_W = 32;

    reg              clk_i;
    reg              rst_i;
    reg              s_valid_i;
    wire             s_ready_o;
    reg  [DATA_W-1:0] s_data_i;
    wire             m_valid_o;
    reg              m_ready_i;
    wire [DATA_W-1:0] m_data_o;

    // DUT instantiation
    pipeline_reg #(.DATA_W(DATA_W)) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .s_valid_i(s_valid_i),
        .s_ready_o(s_ready_o),
        .s_data_i(s_data_i),
        .m_valid_o(m_valid_o),
        .m_ready_i(m_ready_i),
        .m_data_o(m_data_o)
    );

    // Clock generation
    initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i;
    end

    // VCD dump
    initial begin
        $dumpfile("sim.vcd");
        $dumpvars(0, tb_pipeline_reg);
    end

    // Timeout watchdog
    initial begin
        #10000;
        $display("FAIL: simulation timeout");
        $finish;
    end

    // Test infrastructure
    integer test_cnt;
    integer fail_cnt;
    integer cycle_cnt;

    initial begin
        cycle_cnt = 0;
        test_cnt  = 0;
        fail_cnt  = 0;
    end

    always @(posedge clk_i) cycle_cnt <= cycle_cnt + 1;

    // Reset task
    task reset;
        begin
            rst_i     = 1;
            s_valid_i = 0;
            s_data_i  = 0;
            m_ready_i = 0;
            repeat (4) @(posedge clk_i);
            rst_i = 0;
            repeat (2) @(posedge clk_i);
            $display("RESET_RELEASED");
        end
    endtask

    // Check task
    task check;
        input integer id;
        input cond;
        input [255:0] fail_msg;
        begin
            test_cnt = test_cnt + 1;
            if (cond)
                $display("TEST_PASS test_%0d", id);
            else begin
                $display("TEST_FAIL test_%0d: %0s", id, fail_msg);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // Monitor for H1 violation: payload changes while valid=1, ready=0
    reg [DATA_W-1:0] prev_data;
    reg              prev_valid;
    reg              prev_ready;
    integer          stall_violation_count;

    initial stall_violation_count = 0;

    always @(posedge clk_i) begin
        if (!rst_i && prev_valid && !prev_ready) begin
            // Output was stalled (valid=1, ready=0 on previous cycle)
            // Check if data changed on this cycle
            if (m_valid_o && m_data_o !== prev_data) begin
                $display("H1_VIOLATION: payload changed during stall at cycle %0d: was=%h now=%h",
                         cycle_cnt, prev_data, m_data_o);
                stall_violation_count = stall_violation_count + 1;
            end
        end
        prev_valid <= m_valid_o;
        prev_ready <= m_ready_i;
        prev_data  <= m_data_o;
    end

    // Golden reference: latency checker (Strategy F)
    parameter EXPECTED_LATENCY = 1;
    reg lat_check_active;
    integer lat_input_cycle;
    integer golden_pass_cnt;
    integer golden_fail_cnt;

    initial begin
        lat_check_active = 0;
        lat_input_cycle = 0;
        golden_pass_cnt = 0;
        golden_fail_cnt = 0;
    end

    // Latency checker: single block, check first then capture
    always @(posedge clk_i) begin
        #1;
        if (!rst_i && m_valid_o && m_ready_i && lat_check_active) begin
            if ((cycle_cnt - lat_input_cycle) == EXPECTED_LATENCY) begin
                $display("GOLDEN_PASS latency: %0d cycles", cycle_cnt - lat_input_cycle);
                golden_pass_cnt = golden_pass_cnt + 1;
            end else begin
                $display("GOLDEN_FAIL latency: got %0d cycles, expected %0d",
                         cycle_cnt - lat_input_cycle, EXPECTED_LATENCY);
                golden_fail_cnt = golden_fail_cnt + 1;
            end
            lat_check_active = 0;
        end
        if (!rst_i && s_valid_i && s_ready_o) begin
            lat_input_cycle = cycle_cnt;
            lat_check_active = 1;
        end
    end

    // Main test sequence
    initial begin
        reset;

        // Test 1: Basic pass-through (no stall)
        $display("TEST_START test_1_basic");
        s_valid_i = 1;
        s_data_i  = 32'hDEAD_BEEF;
        m_ready_i = 1;
        @(posedge clk_i);
        @(posedge clk_i);
        #1;
        check(1, m_valid_o && m_data_o === 32'hDEAD_BEEF, "basic pass-through failed");
        s_valid_i = 0;
        @(posedge clk_i);

        // Test 2: H1 test — send data, then stall downstream, then send NEW data
        // If H1 bug exists: m_data_o will change while m_valid_o=1, m_ready_i=0
        $display("TEST_START test_2_h1_stall");
        stall_violation_count = 0;
        lat_check_active = 0;  // Reset golden checker between tests

        // Step 1: Send first data item
        s_valid_i = 1;
        s_data_i  = 32'hAAAA_0001;
        m_ready_i = 1;
        @(posedge clk_i);
        @(posedge clk_i);
        #1;
        // Now m_valid_o should be 1, m_data_o = 0xAAAA0001

        // Step 2: Stall downstream (m_ready_i = 0)
        m_ready_i = 0;
        s_valid_i = 0;
        @(posedge clk_i);
        #1;
        // m_valid_o should still be 1, m_data_o should be stable

        // Step 3: Send NEW data while stalled (upstream has new data)
        s_valid_i = 1;
        s_data_i  = 32'hBBBB_0002;
        @(posedge clk_i);
        #1;
        // H1 BUG: m_data_o changes to 0xBBBB0002 while m_valid_o=1, m_ready_i=0
        // CORRECT: m_data_o stays at 0xAAAA0001

        check(2, (stall_violation_count == 0),
              "H1 violation detected");

        // Step 4: Release stall, verify correct data comes out
        m_ready_i = 1;
        s_valid_i = 0;
        @(posedge clk_i);
        @(posedge clk_i);

        // Test 3: Verify data integrity after stall resolution
        $display("TEST_START test_3_post_stall_integrity");
        // After stall release, the original data (0xAAAA0001) should be consumed
        // Then the new data (0xBBBB0002) should appear
        // With the H1 bug, 0xAAAA0001 was lost
        check(3, stall_violation_count == 0,
              "data integrity violated during stall");

        // Summary
        if (fail_cnt == 0)
            $display("ALL_TESTS_PASS");
        else
            $display("FAIL: %0d of %0d tests failed", fail_cnt, test_cnt);

        // Golden reference summary
        if (golden_fail_cnt == 0 && golden_pass_cnt > 0)
            $display("ALL_GOLDEN_PASS (%0d checks)", golden_pass_cnt);
        else
            $display("GOLDEN_SUMMARY: %0d pass, %0d fail", golden_pass_cnt, golden_fail_cnt);

        $display("SIMULATION_DONE");
        $finish;
    end

endmodule
`default_nettype wire
