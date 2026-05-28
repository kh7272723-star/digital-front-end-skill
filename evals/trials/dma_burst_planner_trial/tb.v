`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;
    reg desc_valid_i;
    wire desc_ready_o;
    reg [31:0] desc_src_addr_i;
    reg [31:0] desc_dst_addr_i;
    reg [15:0] desc_byte_count_i;
    wire rd_cmd_valid_o;
    reg rd_cmd_ready_i;
    wire [31:0] rd_cmd_addr_o;
    wire [7:0] rd_cmd_len_o;
    wire wr_cmd_valid_o;
    reg wr_cmd_ready_i;
    wire [31:0] wr_cmd_addr_o;
    wire [7:0] wr_cmd_len_o;
    wire done_valid_o;
    reg done_ready_i;
    wire error_o;
    wire [15:0] expected_b_count_o;
    wire busy_o;

    integer cycle_count;

    dma_burst_planner dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .desc_valid_i(desc_valid_i),
        .desc_ready_o(desc_ready_o),
        .desc_src_addr_i(desc_src_addr_i),
        .desc_dst_addr_i(desc_dst_addr_i),
        .desc_byte_count_i(desc_byte_count_i),
        .rd_cmd_valid_o(rd_cmd_valid_o),
        .rd_cmd_ready_i(rd_cmd_ready_i),
        .rd_cmd_addr_o(rd_cmd_addr_o),
        .rd_cmd_len_o(rd_cmd_len_o),
        .wr_cmd_valid_o(wr_cmd_valid_o),
        .wr_cmd_ready_i(wr_cmd_ready_i),
        .wr_cmd_addr_o(wr_cmd_addr_o),
        .wr_cmd_len_o(wr_cmd_len_o),
        .done_valid_o(done_valid_o),
        .done_ready_i(done_ready_i),
        .error_o(error_o),
        .expected_b_count_o(expected_b_count_o),
        .busy_o(busy_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    task fail;
        input [512*8-1:0] msg;
        begin
            $display("FAIL cycle %0d: %0s", cycle_count, msg);
            $finish;
        end
    endtask

    task step;
        begin
            @(posedge clk_i);
            #1;
            cycle_count = cycle_count + 1;
        end
    endtask

    task idle_inputs;
        begin
            desc_valid_i = 1'b0;
            desc_src_addr_i = 32'h0000_0000;
            desc_dst_addr_i = 32'h0000_0000;
            desc_byte_count_i = 16'd0;
            rd_cmd_ready_i = 1'b0;
            wr_cmd_ready_i = 1'b0;
            done_ready_i = 1'b0;
        end
    endtask

    task start_desc;
        input [31:0] src;
        input [31:0] dst;
        input [15:0] bytes;
        begin
            desc_src_addr_i = src;
            desc_dst_addr_i = dst;
            desc_byte_count_i = bytes;
            desc_valid_i = 1'b1;
            #1;
            if (desc_ready_o !== 1'b1) begin
                fail("descriptor should be ready");
            end
            step();
            desc_valid_i = 1'b0;
        end
    endtask

    task expect_cmd;
        input [31:0] rd_addr;
        input [31:0] wr_addr;
        input [7:0] len;
        begin
            if (rd_cmd_valid_o !== 1'b1 || wr_cmd_valid_o !== 1'b1) begin
                fail("expected paired read/write commands");
            end
            if (rd_cmd_addr_o !== rd_addr || wr_cmd_addr_o !== wr_addr) begin
                fail("unexpected command address");
            end
            if (rd_cmd_len_o !== len || wr_cmd_len_o !== len) begin
                fail("unexpected command length");
            end
        end
    endtask

    task accept_cmd_pair;
        begin
            rd_cmd_ready_i = 1'b1;
            wr_cmd_ready_i = 1'b1;
            step();
            rd_cmd_ready_i = 1'b0;
            wr_cmd_ready_i = 1'b0;
        end
    endtask

    task consume_done;
        input expected_error;
        input [15:0] expected_b;
        begin
            if (done_valid_o !== 1'b1) begin
                fail("expected done");
            end
            if (error_o !== expected_error) begin
                fail("unexpected done error");
            end
            if (expected_b_count_o !== expected_b) begin
                fail("unexpected expected B response count");
            end
            done_ready_i = 1'b1;
            step();
            done_ready_i = 1'b0;
        end
    endtask

    initial begin
        cycle_count = 0;
        rst_i = 1'b1;
        idle_inputs();
        repeat (2) step();
        rst_i = 1'b0;
        step();
        if (desc_ready_o !== 1'b1 || busy_o !== 1'b0 || done_valid_o !== 1'b0) begin
            fail("bad reset release state");
        end

        start_desc(32'h0000_1000, 32'h0000_2000, 16'd40);
        expect_cmd(32'h0000_1000, 32'h0000_2000, 8'd3);

        rd_cmd_ready_i = 1'b0;
        wr_cmd_ready_i = 1'b1;
        step();
        expect_cmd(32'h0000_1000, 32'h0000_2000, 8'd3);
        if (expected_b_count_o !== 16'd0) begin
            fail("command count changed when only one side ready");
        end
        rd_cmd_ready_i = 1'b1;
        wr_cmd_ready_i = 1'b1;
        step();
        rd_cmd_ready_i = 1'b0;
        wr_cmd_ready_i = 1'b0;

        expect_cmd(32'h0000_1010, 32'h0000_2010, 8'd3);
        accept_cmd_pair();
        expect_cmd(32'h0000_1020, 32'h0000_2020, 8'd1);
        accept_cmd_pair();
        consume_done(1'b0, 16'd3);

        start_desc(32'h0000_1000, 32'h0000_2000, 16'd0);
        consume_done(1'b1, 16'd0);

        start_desc(32'h0000_1002, 32'h0000_2000, 16'd16);
        consume_done(1'b1, 16'd0);

        // ========================================================
        // Golden Reference: Strategy C — Write-Readback Scoreboard
        // Adapted for handshake-based module (no bus registers)
        // "Write" = drive descriptor, "Readback" = observe outputs
        // ========================================================
        $display("");
        $display("=== Golden Reference: Strategy C Readback Checks ===");

        run_readback_checks();

        $display("");
        $display("=== Readback Summary: PASS=%0d FAIL=%0d ===", readback_pass, readback_fail);
        if (readback_fail == 0)
            $display("ALL_READBACK_CHECKS PASSED");
        else
            $display("ALL_READBACK_CHECKS FAILED");

        $display("");
        $display("PASS dma burst planner");
        $finish;
    end

    // --------------------------------------------------------
    // Golden reference counters
    // --------------------------------------------------------
    integer readback_pass;
    integer readback_fail;

    initial begin
        readback_pass = 0;
        readback_fail = 0;
    end

    // --------------------------------------------------------
    // Readback check helper: compare single value
    // --------------------------------------------------------
    task readback_cmp;
        input [512*8-1:0] test_name;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual !== expected) begin
                $display("READBACK_FAIL %0s: got 0x%08h, expected 0x%08h", test_name, actual, expected);
                readback_fail = readback_fail + 1;
            end else begin
                $display("READBACK_PASS %0s: 0x%08h", test_name, actual);
                readback_pass = readback_pass + 1;
            end
        end
    endtask

    // --------------------------------------------------------
    // Readback check helper: compare 8-bit value
    // --------------------------------------------------------
    task readback_cmp8;
        input [512*8-1:0] test_name;
        input [7:0] actual;
        input [7:0] expected;
        begin
            if (actual !== expected) begin
                $display("READBACK_FAIL %0s: got 0x%02h, expected 0x%02h", test_name, actual, expected);
                readback_fail = readback_fail + 1;
            end else begin
                $display("READBACK_PASS %0s: 0x%02h", test_name, actual);
                readback_pass = readback_pass + 1;
            end
        end
    endtask

    // --------------------------------------------------------
    // Readback check helper: compare 1-bit value
    // --------------------------------------------------------
    task readback_cmp1;
        input [512*8-1:0] test_name;
        input actual;
        input expected;
        begin
            if (actual !== expected) begin
                $display("READBACK_FAIL %0s: got %0b, expected %0b", test_name, actual, expected);
                readback_fail = readback_fail + 1;
            end else begin
                $display("READBACK_PASS %0s: %0b", test_name, actual);
                readback_pass = readback_pass + 1;
            end
        end
    endtask

    // --------------------------------------------------------
    // Run a single-descriptor transfer and check all outputs
    // against independently computed expected values.
    //
    // Expected burst plan (computed from spec, NOT from RTL):
    //   beats = byte_count >> 2
    //   Each burst: min(beats_remaining, 4) beats
    //   len = burst_beats - 1
    //   addr increments by burst_beats * 4 between bursts
    // --------------------------------------------------------
    task run_single_desc_check;
        input [512*8-1:0] test_name;
        input [31:0] src;
        input [31:0] dst;
        input [15:0] bytes;
        input expect_error;
        begin
            integer beats_total;
            integer beats_left;
            integer burst_idx;
            integer exp_burst_beats;
            reg [31:0] exp_rd_addr;
            reg [31:0] exp_wr_addr;
            reg [7:0] exp_len;
            integer exp_b_count;

            $display("--- %0s: src=0x%08h dst=0x%08h bytes=%0d ---",
                     test_name, src, dst, bytes);

            beats_total = bytes >> 2;
            beats_left = beats_total;
            burst_idx = 0;
            exp_rd_addr = src;
            exp_wr_addr = dst;
            exp_b_count = 0;

            // Launch descriptor
            start_desc(src, dst, bytes);

            if (expect_error) begin
                // Should see done with error, no commands
                if (done_valid_o !== 1'b1) begin
                    $display("READBACK_FAIL %0s: expected done_valid on error", test_name);
                    readback_fail = readback_fail + 1;
                end else begin
                    readback_cmp1({test_name, " done_error"}, error_o, 1'b1);
                    readback_cmp({test_name, " expected_b_count"}, {16'h0, expected_b_count_o}, 32'd0);
                end
                done_ready_i = 1'b1;
                step();
                done_ready_i = 1'b0;
            end else begin
                // Expect multiple bursts
                while (beats_left > 0) begin
                    if (beats_left > 4)
                        exp_burst_beats = 4;
                    else
                        exp_burst_beats = beats_left;

                    exp_len = exp_burst_beats[7:0] - 8'd1;

                    // Check rd_cmd
                    readback_cmp({test_name, " burst", 8'd48+burst_idx[7:0], " rd_addr"},
                                 rd_cmd_addr_o, exp_rd_addr);
                    readback_cmp8({test_name, " burst", 8'd48+burst_idx[7:0], " rd_len"},
                                  rd_cmd_len_o, exp_len);

                    // Check wr_cmd
                    readback_cmp({test_name, " burst", 8'd48+burst_idx[7:0], " wr_addr"},
                                 wr_cmd_addr_o, exp_wr_addr);
                    readback_cmp8({test_name, " burst", 8'd48+burst_idx[7:0], " wr_len"},
                                  wr_cmd_len_o, exp_len);

                    // Check valid signals
                    readback_cmp1({test_name, " burst", 8'd48+burst_idx[7:0], " rd_valid"},
                                  rd_cmd_valid_o, 1'b1);
                    readback_cmp1({test_name, " burst", 8'd48+burst_idx[7:0], " wr_valid"},
                                  wr_cmd_valid_o, 1'b1);

                    // Check busy during operation
                    readback_cmp1({test_name, " burst", 8'd48+burst_idx[7:0], " busy"},
                                  busy_o, 1'b1);

                    // Check expected_b_count increments
                    readback_cmp({test_name, " burst", 8'd48+burst_idx[7:0], " b_count"},
                                 {16'h0, expected_b_count_o}, exp_b_count[31:0]);

                    // Accept the command pair
                    accept_cmd_pair();

                    exp_b_count = exp_b_count + 1;
                    exp_rd_addr = exp_rd_addr + (exp_burst_beats << 2);
                    exp_wr_addr = exp_wr_addr + (exp_burst_beats << 2);
                    beats_left = beats_left - exp_burst_beats;
                    burst_idx = burst_idx + 1;
                end

                // Consume done
                consume_done(1'b0, exp_b_count[15:0]);

                // After done accepted, check not-busy
                readback_cmp1({test_name, " post_done busy"}, busy_o, 1'b0);
                readback_cmp1({test_name, " post_done done_valid"}, done_valid_o, 1'b0);
            end
        end
    endtask

    // --------------------------------------------------------
    // Master readback test runner
    // --------------------------------------------------------
    task run_readback_checks;
        begin
            integer i;
            reg [31:0] walk_addr;

            // Ensure idle state before starting
            idle_inputs();
            step();

            // === Test 1: Single-beat transfer (4 bytes) ===
            run_single_desc_check("single_beat_4B",
                32'h0000_1000, 32'h0000_2000, 16'd4, 0);

            // === Test 2: Two-beat transfer (8 bytes) ===
            run_single_desc_check("two_beat_8B",
                32'h0000_1000, 32'h0000_2000, 16'd8, 0);

            // === Test 3: Exactly MAX_BURST (16 bytes = 4 beats) ===
            run_single_desc_check("max_burst_16B",
                32'h0000_1000, 32'h0000_2000, 16'd16, 0);

            // === Test 4: Just over MAX_BURST (20 bytes = 5 beats = 4+1) ===
            run_single_desc_check("over_burst_20B",
                32'h0000_1000, 32'h0000_2000, 16'd20, 0);

            // === Test 5: Boundary — 0xDEADBEEF pattern in addresses ===
            run_single_desc_check("deadbeef_addr",
                32'hDEAD_BEE0, 32'hCAFE_BAB0, 16'd8, 0);

            // === Test 6: Walking-ones in source address ===
            walk_addr = 32'h0000_0004;
            for (i = 0; i < 8; i = i + 1) begin
                run_single_desc_check("walk_src",
                    walk_addr, 32'h0000_8000, 16'd4, 0);
                walk_addr = walk_addr << 1;
            end

            // === Test 7: Walking-ones in dest address ===
            walk_addr = 32'h0000_0004;
            for (i = 0; i < 8; i = i + 1) begin
                run_single_desc_check("walk_dst",
                    32'h0000_8000, walk_addr, 16'd4, 0);
                walk_addr = walk_addr << 1;
            end

            // === Test 8: Boundary values on byte_count ===
            // 0 bytes → error (already tested in main TB, but let's verify readback)
            run_single_desc_check("zero_bytes",
                32'h0000_1000, 32'h0000_2000, 16'd0, 1);

            // === Test 9: Misaligned src address → error ===
            run_single_desc_check("misalign_src",
                32'h0000_1001, 32'h0000_2000, 16'd16, 1);

            // === Test 10: Misaligned dst address → error ===
            run_single_desc_check("misalign_dst",
                32'h0000_1000, 32'h0000_2001, 16'd16, 1);

            // === Test 11: Misaligned byte count → error ===
            run_single_desc_check("misalign_bytes",
                32'h0000_1000, 32'h0000_2000, 16'd5, 1);

            // === Test 12: Large multi-burst (64 bytes = 16 beats = 4+4+4+4) ===
            run_single_desc_check("large_64B",
                32'h0001_0000, 32'h0002_0000, 16'd64, 0);

            // === Test 13: Odd multi-burst (28 bytes = 7 beats = 4+3) ===
            run_single_desc_check("odd_28B",
                32'h0000_1000, 32'h0000_2000, 16'd28, 0);

            // === Test 14: Post-reset idle state readback ===
            $display("--- post_reset_idle ---");
            rst_i = 1'b1;
            idle_inputs();
            repeat (3) step();
            rst_i = 1'b0;
            step();
            #1;
            readback_cmp1("post_reset desc_ready", desc_ready_o, 1'b1);
            readback_cmp1("post_reset busy", busy_o, 1'b0);
            readback_cmp1("post_reset done_valid", done_valid_o, 1'b0);
            readback_cmp1("post_reset error", error_o, 1'b0);
            readback_cmp("post_reset expected_b_count", {16'h0, expected_b_count_o}, 32'd0);
            readback_cmp1("post_reset rd_cmd_valid", rd_cmd_valid_o, 1'b0);
            readback_cmp1("post_reset wr_cmd_valid", wr_cmd_valid_o, 1'b0);
        end
    endtask

endmodule
