`default_nettype none
`timescale 1ns / 1ps

//============================================================================
// tb_axis_to_apb — Testbench for AXI-Stream to APB Write Bridge
//
// Tests: T1 (reset), T2 (single beat), T3 (multi-beat),
//        T4 (TVALID deassert mid-transaction), T5 (PSLVERR), T6 (address)
//============================================================================

module tb_axis_to_apb;

    //========================================================================
    // Parameters
    //========================================================================
    parameter CLK_PERIOD = 20;          // 50 MHz
    parameter MAX_TIME   = 1_000_000;   // 1 ms watchdog

    //========================================================================
    // DUT signals
    //========================================================================
    reg         clk_i;
    reg         rst_ni;
    reg         s_axis_tvalid_i;
    reg  [31:0] s_axis_tdata_i;
    reg         s_axis_tlast_i;
    wire        s_axis_tready_o;
    wire        apb_psel_o;
    wire        apb_penable_o;
    wire [15:0] apb_paddr_o;
    wire        apb_pwrite_o;
    wire [31:0] apb_pwdata_o;
    wire [31:0] apb_prdata_i;
    wire        apb_pready_i;
    wire        apb_pslverr_i;
    wire        busy_o;
    wire        error_o;

    //========================================================================
    // DUT instantiation
    //========================================================================
    axis_to_apb #(
        .APB_BASE_ADDR(16'h1000),
        .ADDR_INCR   (1)
    ) u_dut (
        .clk_i         (clk_i),
        .rst_ni        (rst_ni),
        .s_axis_tvalid_i(s_axis_tvalid_i),
        .s_axis_tdata_i (s_axis_tdata_i),
        .s_axis_tlast_i (s_axis_tlast_i),
        .s_axis_tready_o(s_axis_tready_o),
        .apb_psel_o    (apb_psel_o),
        .apb_penable_o (apb_penable_o),
        .apb_paddr_o   (apb_paddr_o),
        .apb_pwrite_o  (apb_pwrite_o),
        .apb_pwdata_o  (apb_pwdata_o),
        .apb_prdata_i  (apb_prdata_i),
        .apb_pready_i  (apb_pready_i),
        .apb_pslverr_i (apb_pslverr_i),
        .busy_o        (busy_o),
        .error_o       (error_o)
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
    // Cycle counter (for hang detection)
    //========================================================================
    integer cycle_cnt;
    always @(posedge clk_i) begin
        cycle_cnt <= cycle_cnt + 1;
    end

    //========================================================================
    // Timeout watchdog
    //========================================================================
    initial begin
        #MAX_TIME;
        $display("FAIL: SIMULATION_TIMEOUT at %0t (cycle %0d)", $time, cycle_cnt);
        $finish;
    end

    //========================================================================
    // VCD dump
    //========================================================================
    initial begin
        $dumpfile("sim.vcd");
        $dumpvars(0, tb_axis_to_apb);
    end

    //========================================================================
    // APB slave model
    //========================================================================
    reg force_pslverr;

    assign apb_pready_i  = 1'b1;

    // PSLVERR: forced by test register during ACCESS
    assign apb_pslverr_i = (apb_psel_o && apb_penable_o && apb_pwrite_o && force_pslverr) ? 1'b1 : 1'b0;

    // Write capture log (only captures non-error writes)
    reg [31:0] wr_data_log [0:255];
    reg [15:0] wr_addr_log [0:255];
    integer    wr_count;
    integer    i;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            wr_data_log[i] = 32'd0;
            wr_addr_log[i] = 16'd0;
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_count <= 0;
        end else begin
            // Only count successful writes (per B1: inline condition)
            if (apb_psel_o && apb_penable_o && apb_pwrite_o && apb_pready_i && !apb_pslverr_i) begin
                wr_data_log[wr_count] <= apb_pwdata_o;
                wr_addr_log[wr_count] <= apb_paddr_o;
                wr_count <= wr_count + 1;
                $display("APB_WRITE: cnt=%0d addr=%04h data=%08h",
                         wr_count, apb_paddr_o, apb_pwdata_o);
            end
        end
    end

    //========================================================================
    // Error infrastructure
    //========================================================================
    integer error_cnt;
    integer test_cnt;
    reg [255:0] msg_buf;

    task check;
        input integer   test_id;
        input           condition;
        input [255:0]   fail_msg;
        begin
            test_cnt = test_cnt + 1;
            if (condition) begin
                $display("TEST_PASS test_%0d", test_id);
            end else begin
                $display("TEST_FAIL test_%0d: %0s", test_id, fail_msg);
                error_cnt = error_cnt + 1;
            end
        end
    endtask

    //========================================================================
    // Drive stimulus on negedge (per B4 fix: NBA race avoidance)
    //========================================================================
    task axis_send;
        input [31:0] data;
        begin
            @(negedge clk_i);
            s_axis_tvalid_i = 1'b1;
            s_axis_tdata_i  = data;
            @(posedge clk_i);       // handshake fires (TREADY=1 in IDLE)
            @(negedge clk_i);
            s_axis_tvalid_i = 1'b0;
            s_axis_tdata_i  = 32'd0;
        end
    endtask

    //========================================================================
    // Wait for busy to go low (transaction complete)
    //========================================================================
    task wait_for_write;
        begin
            @(posedge clk_i);
            while (busy_o) @(posedge clk_i);
            #1;  // settle per B3
        end
    endtask

    //========================================================================
    // Reset between tests (clears DUT state + write count)
    //========================================================================
    task reset_dut;
        begin
            rst_ni = 1'b0;
            s_axis_tvalid_i = 1'b0;
            s_axis_tdata_i  = 32'd0;
            s_axis_tlast_i  = 1'b0;
            force_pslverr   = 1'b0;
            repeat (8) @(posedge clk_i);
            rst_ni = 1'b1;
            repeat (4) @(posedge clk_i);
            wr_count = 0;
            $display("RESET_RELEASED");
        end
    endtask

    //========================================================================
    // Test T1: Reset behavior
    //========================================================================
    task test_t1;
    begin
        $display("TEST_START test_T1_reset");
        #1;

        check(1, s_axis_tready_o === 1'b1,  "TREADY not 1 after reset");
        check(1, apb_psel_o === 1'b0,       "PSEL not 0 after reset");
        check(1, apb_penable_o === 1'b0,    "PENABLE not 0 after reset");
        check(1, busy_o === 1'b0,           "busy not 0 after reset");
        check(1, error_o === 1'b0,          "error not 0 after reset");
        check(1, apb_paddr_o === 16'h1000,  "paddr not BASE_ADDR");
    end
    endtask

    //========================================================================
    // Test T2: Single beat write
    //========================================================================
    task test_t2;
    begin
        $display("TEST_START test_T2_single_beat");
        axis_send(32'hA5A5A5A5);
        wait_for_write();

        check(2, wr_count == 1, "Write not captured");
        if (wr_count > 0) begin
            check(2, wr_data_log[0] === 32'hA5A5A5A5, "Data mismatch");
            check(2, wr_addr_log[0] === 16'h1000,     "Addr mismatch");
        end
    end
    endtask

    //========================================================================
    // Test T3: Multi-beat (3 beats)
    //========================================================================
    task test_t3;
    begin
        integer j;
        reg [31:0] exp_data [0:2];
        reg [15:0] exp_addr [0:2];
        $display("TEST_START test_T3_multi_beat");

        exp_data[0] = 32'h11111111; exp_addr[0] = 16'h1000;
        exp_data[1] = 32'h22222222; exp_addr[1] = 16'h1004;
        exp_data[2] = 32'h33333333; exp_addr[2] = 16'h1008;

        for (j = 0; j < 3; j = j + 1) begin
            axis_send(exp_data[j]);
            wait_for_write();

            check(3, wr_count == j+1, "Write count mismatch");
            if (wr_count > j) begin
                check(3, wr_data_log[j] === exp_data[j], "Data mismatch");
                check(3, wr_addr_log[j] === exp_addr[j], "Addr mismatch");
            end
        end
    end
    endtask

    //========================================================================
    // Test T4: TVALID deassert mid-transaction
    //========================================================================
    task test_t4;
    begin
        $display("TEST_START test_T4_tvalid_deassert");

        // Beat 1: drive manually, TVALID only active for 1 cycle
        @(negedge clk_i);
        s_axis_tvalid_i = 1'b1;
        s_axis_tdata_i  = 32'hDEADBEEF;
        @(posedge clk_i);       // handshake
        @(negedge clk_i);       // deassert immediately
        s_axis_tvalid_i = 1'b0;
        s_axis_tdata_i  = 32'd0;

        wait_for_write();
        check(4, wr_count >= 1, "Beat 1 not written");
        if (wr_count >= 1) begin
            check(4, wr_data_log[0] === 32'hDEADBEEF, "Beat1 data mismatch");
            check(4, wr_addr_log[0] === 16'h1000,     "Beat1 addr");
        end

        // Beat 2: normal send (DUT should be in IDLE)
        axis_send(32'hCAFEBABE);
        wait_for_write();
        check(4, wr_count >= 2, "Beat 2 not written");
        if (wr_count >= 2) begin
            check(4, wr_data_log[1] === 32'hCAFEBABE, "Beat2 data mismatch");
            check(4, wr_addr_log[1] === 16'h1004,     "Beat2 addr incr");
        end
    end
    endtask

    //========================================================================
    // Test T5: PSLVERR handling
    //========================================================================
    task test_t5;
    begin
        integer prev_count;
        $display("TEST_START test_T5_pslverr");

        // -- Error beat 1: verify write is SUPPRESSED --
        force_pslverr = 1'b1;
        prev_count = wr_count;
        axis_send(32'hBEEFBEEF);
        wait_for_write();

        // Write count should NOT have increased (PSLVERR → no capture)
        check(5, wr_count == prev_count, "Write captured despite PSLVERR");

        // -- Error beat 2: check error_o pulse --
        // error_o is a registered 1-cycle pulse. error_q is updated on the
        // posedge where state transitions ACCESS->IDLE and stays for 1 cycle.
        // Use manual cycle counting instead of wait_for_write (which adds an
        // extra cycle due to while(busy) checking before NBA).
        force_pslverr = 1'b1;
        axis_send(32'hBAD0BAD0);
        // After axis_send: DUT in SETUP
        @(posedge clk_i);  // SETUP -> ACCESS
        @(posedge clk_i);  // ACCESS -> IDLE, error_q <= PSLVERR
        #1;
        check(5, error_o === 1'b1, "error_o not high after PSLVERR");
        // Wait for error_q to clear (default error_d = 0 in IDLE)
        @(posedge clk_i);  // error_q <= 0

        // -- Clean beat: error_o should go back to 0 --
        force_pslverr = 1'b0;
        axis_send(32'h12345678);
        wait_for_write();
        #1;
        check(5, error_o === 1'b0, "error_o still high after clean xact");
    end
    endtask

    //========================================================================
    // Test T6: Address increment (3 beats, check sequence)
    //========================================================================
    task test_t6;
    begin
        integer j;
        reg [31:0] exp_data [0:2];
        reg [15:0] exp_addr [0:2];
        $display("TEST_START test_T6_addr_incr");

        exp_data[0] = 32'hAAAAAAAA; exp_addr[0] = 16'h1000;
        exp_data[1] = 32'hBBBBBBBB; exp_addr[1] = 16'h1004;
        exp_data[2] = 32'hCCCCCCCC; exp_addr[2] = 16'h1008;

        for (j = 0; j < 3; j = j + 1) begin
            axis_send(exp_data[j]);
            wait_for_write();

            check(6, wr_count == j+1, "Write count mismatch");
            if (wr_count > j) begin
                check(6, wr_data_log[j] === exp_data[j], "Data mismatch");
                check(6, wr_addr_log[j] === exp_addr[j], "Addr mismatch");
            end
        end
    end
    endtask

    //========================================================================
    // Main test sequence
    //========================================================================
    initial begin
        cycle_cnt       = 0;
        test_cnt        = 0;
        error_cnt       = 0;
        wr_count        = 0;
        s_axis_tvalid_i = 1'b0;
        s_axis_tdata_i  = 32'd0;
        s_axis_tlast_i  = 1'b0;
        force_pslverr   = 1'b0;

        $display("SIMULATION_START");

        // Reset and T1
        reset_dut();
        test_t1();

        // Reset between tests to clear address and write log
        reset_dut();  test_t2();
        reset_dut();  test_t3();
        reset_dut();  test_t4();
        reset_dut();  test_t5();
        reset_dut();  test_t6();

        // Summary
        if (error_cnt == 0)
            $display("ALL_TESTS_PASS");
        else
            $display("FAIL: %0d of %0d tests failed", error_cnt, test_cnt);
        $display("SIMULATION_DONE");
        $finish;
    end

endmodule

`default_nettype wire
