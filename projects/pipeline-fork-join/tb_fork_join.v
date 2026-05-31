`timescale 1ns / 100ps

module tb_fork_join;

    reg  clk_i;
    reg  rst_ni;
    reg  s_axis_tvalid_i;
    wire s_axis_tready_o;
    reg  [7:0] s_axis_tdata_i;
    reg  s_axis_tlast_i;
    wire m_axis_tvalid_o;
    reg  m_axis_tready_i;
    wire [7:0] m_axis_tdata_o;
    wire m_axis_tlast_o;
    wire pkt_done_o;
    wire [7:0] beat_count_o;

    fork_join_pipeline #(.DATA_WIDTH(8), .PIPELINE_STAGES(2)) dut (
        .clk_i, .rst_ni,
        .s_axis_tvalid_i, .s_axis_tready_o,
        .s_axis_tdata_i, .s_axis_tlast_i,
        .m_axis_tvalid_o, .m_axis_tready_i,
        .m_axis_tdata_o, .m_axis_tlast_o,
        .pkt_done_o, .beat_count_o
    );

    localparam CLK_PERIOD = 20;
    integer error_cnt;
    reg [7:0]  rx_data;
    reg        rx_tlast;
    integer    i;
    reg [7:0]  beat_buf [0:63];
    integer    beat_idx, beat_total;

    always #(CLK_PERIOD/2) clk_i = ~clk_i;

    // Drive stimulus: assert on negedge, wait for acceptance, deassert
    task send_beat;
        input [7:0] data;
        input       is_last;
    begin
        @(negedge clk_i);
        s_axis_tvalid_i = 1'b1;
        s_axis_tdata_i  = data;
        s_axis_tlast_i  = is_last;
        // Wait until tready high means beat was captured on posedge
        while (!s_axis_tready_o) @(negedge clk_i);
        // Deassert immediately on next negedge
        @(negedge clk_i);
        s_axis_tvalid_i = 1'b0;
    end
    endtask

    // Concurrent receiver: monitors m_axis output and buffers beats
    // Runs in background, always ready
    always @(posedge clk_i) begin
        #1;  // Icarus pitfall B3: let NBA settle
        if (m_axis_tvalid_o && m_axis_tready_i) begin
            beat_buf[beat_total]   = m_axis_tdata_o;
            beat_total = beat_total + 1;
        end
    end

    initial begin
        clk_i = 1'b0;
        error_cnt = 0;
        beat_total = 0;
        {s_axis_tvalid_i, s_axis_tdata_i, s_axis_tlast_i, m_axis_tready_i} = 0;

        $display("SIMULATION_START");

        // Reset
        rst_ni = 1'b0;
        repeat (10) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (5) @(posedge clk_i);
        $display("RESET_RELEASED");

        // ──────────────────────────────────────────
        // T1: Single beat packet
        // ──────────────────────────────────────────
        $display("TEST_START T1_single_beat");
        m_axis_tready_i = 1'b1;
        beat_total = 0;
        send_beat(8'd42, 1'b1);
        // Wait for pkt_done
        repeat (30) @(posedge clk_i);
        #1;
        if (pkt_done_o != 1'b1) begin
            $display("TEST_FAIL T1_single_beat: pkt_done_o not asserted");
            error_cnt = error_cnt + 1;
        end else if (beat_count_o != 8'd1) begin
            $display("TEST_FAIL T1_single_beat: beat_count_o=%0d expect 1", beat_count_o);
            error_cnt = error_cnt + 1;
        end else if (beat_total != 1) begin
            $display("TEST_FAIL T1_single_beat: received %0d beats expect 1", beat_total);
            error_cnt = error_cnt + 1;
        end else if (beat_buf[0] != 8'd42) begin
            $display("TEST_FAIL T1_single_beat: data=%0d expect 42", beat_buf[0]);
            error_cnt = error_cnt + 1;
        end else begin
            $display("TEST_PASS T1_single_beat: beat_count=%0d data=%0d", beat_count_o, beat_buf[0]);
        end

        // ──────────────────────────────────────────
        // T2: Multi-beat (3 beats) — data integrity
        // ──────────────────────────────────────────
        $display("TEST_START T2_multibeat");
        m_axis_tready_i = 1'b1;
        beat_total = 0;
        send_beat(8'd10, 1'b0);
        send_beat(8'd20, 1'b0);
        send_beat(8'd30, 1'b1);
        repeat (30) @(posedge clk_i);
        #1;
        if (pkt_done_o != 1'b1) begin
            $display("TEST_FAIL T2_multibeat: pkt_done_o not asserted");
            error_cnt = error_cnt + 1;
        end else if (beat_count_o != 8'd3) begin
            $display("TEST_FAIL T2_multibeat: beat_count_o=%0d expect 3", beat_count_o);
            error_cnt = error_cnt + 1;
        end else if (beat_total != 3) begin
            $display("TEST_FAIL T2_multibeat: received %0d beats expect 3", beat_total);
            error_cnt = error_cnt + 1;
        end else if (beat_buf[0] != 8'd10 || beat_buf[1] != 8'd20 || beat_buf[2] != 8'd30) begin
            $display("TEST_FAIL T2_multibeat: data mismatch [%0d,%0d,%0d] expect [10,20,30]",
                     beat_buf[0], beat_buf[1], beat_buf[2]);
            error_cnt = error_cnt + 1;
        end else begin
            $display("TEST_PASS T2_multibeat: 3 beats OK, beat_count=%0d", beat_count_o);
        end

        // ──────────────────────────────────────────
        // T3: Back-to-back packets
        // ──────────────────────────────────────────
        $display("TEST_START T3_back_to_back");
        m_axis_tready_i = 1'b1;
        beat_total = 0;
        send_beat(8'd1, 1'b1);
        repeat (20) @(posedge clk_i);
        #1;
        if (pkt_done_o != 1'b1) begin
            $display("TEST_FAIL T3_back_to_back: pkt1 done not asserted");
            error_cnt = error_cnt + 1;
        end
        beat_total = 0;
        send_beat(8'd99, 1'b1);
        repeat (20) @(posedge clk_i);
        #1;
        if (beat_count_o != 8'd1) begin
            $display("TEST_FAIL T3_back_to_back: pkt2 beat_count=%0d expect 1", beat_count_o);
            error_cnt = error_cnt + 1;
        end else if (beat_buf[0] != 8'd99) begin
            $display("TEST_FAIL T3_back_to_back: pkt2 data=%0d expect 99", beat_buf[0]);
            error_cnt = error_cnt + 1;
        end else begin
            $display("TEST_PASS T3_back_to_back");
        end

        // ──────────────────────────────────────────
        // T4: Backpressure — stall downstream
        // ──────────────────────────────────────────
        $display("TEST_START T4_backpressure");
        m_axis_tready_i = 1'b0;  // stall downstream
        beat_total = 0;
        send_beat(8'd77, 1'b1);  // accepted into pipeline, but can't exit
        repeat (30) @(posedge clk_i);
        #1;
        if (pkt_done_o == 1'b1) begin
            $display("TEST_FAIL T4_backpressure: pkt_done_o asserted while stalled");
            error_cnt = error_cnt + 1;
        end
        // Release backpressure
        m_axis_tready_i = 1'b1;
        repeat (30) @(posedge clk_i);
        #1;
        if (pkt_done_o != 1'b1) begin
            $display("TEST_FAIL T4_backpressure: pkt_done_o not asserted after release");
            error_cnt = error_cnt + 1;
        end else if (beat_buf[0] != 8'd77 || beat_total != 1) begin
            $display("TEST_FAIL T4_backpressure: data mismatch");
            error_cnt = error_cnt + 1;
        end else begin
            $display("TEST_PASS T4_backpressure");
        end

        // ──────────────────────────────────────────
        // T5: Fork-Join timing — done only after both paths
        // ──────────────────────────────────────────
        $display("TEST_START T5_fork_join_timing");
        m_axis_tready_i = 1'b1;
        beat_total = 0;
        send_beat(8'd55, 1'b1);
        // Check: immediately after send returns, done should still be 0
        // Pipeline needs 2 stages to drain. Check at 1 negedge later.
        @(negedge clk_i);
        #1;
        if (pkt_done_o == 1'b1) begin
            $display("TEST_FAIL T5_fork_join_timing: pkt_done asserted immediately (0-cycle)");
            error_cnt = error_cnt + 1;
        end
        // Wait for pipeline to drain (2 stages + 1 joiner cycle)
        repeat (10) @(posedge clk_i);
        #1;
        if (pkt_done_o != 1'b1) begin
            $display("TEST_FAIL T5_fork_join_timing: pkt_done not asserted after latency");
            error_cnt = error_cnt + 1;
        end else begin
            $display("TEST_PASS T5_fork_join_timing");
        end

        // Report
        if (error_cnt == 0)
            $display("ALL_TESTS_PASS");
        else
            $display("FAIL: %0d test(s) failed", error_cnt);

        $display("SIMULATION_DONE");
        $finish;
    end

endmodule
