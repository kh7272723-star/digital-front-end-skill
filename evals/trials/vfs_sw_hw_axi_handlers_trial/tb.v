`timescale 1ns/1ps

module tb;
    localparam ADDR_W = 32;
    localparam DATA_W = 32;
    localparam LEN_W = 8;
    localparam ENTRY_COUNT_W = 3;
    localparam BEAT_COUNT_W = 9;

    reg clk_i;
    reg rst_i;

    reg read_cmd_valid_i;
    wire read_cmd_ready_o;
    reg [ADDR_W-1:0] read_cmd_addr_i;
    reg [ENTRY_COUNT_W-1:0] read_cmd_entry_count_i;
    wire read_m_arvalid_o;
    reg read_m_arready_i;
    wire [ADDR_W-1:0] read_m_araddr_o;
    wire [LEN_W-1:0] read_m_arlen_o;
    reg read_m_rvalid_i;
    wire read_m_rready_o;
    reg [DATA_W-1:0] read_m_rdata_i;
    reg read_m_rlast_i;
    reg [1:0] read_m_rresp_i;
    wire read_sqe_valid_o;
    reg read_sqe_ready_i;
    wire [DATA_W-1:0] read_sqe_data_o;
    wire read_sqe_entry_last_o;
    wire read_done_valid_o;
    reg read_done_ready_i;
    wire read_error_o;
    wire read_busy_o;
    wire [BEAT_COUNT_W-1:0] read_beats_rem_o;

    reg write_cmd_valid_i;
    wire write_cmd_ready_o;
    reg [ADDR_W-1:0] write_cmd_addr_i;
    reg [DATA_W-1:0] write_cmd_data_i;
    reg write_cmd_phase_i;
    wire write_m_awvalid_o;
    reg write_m_awready_i;
    wire [ADDR_W-1:0] write_m_awaddr_o;
    wire [LEN_W-1:0] write_m_awlen_o;
    wire write_m_wvalid_o;
    reg write_m_wready_i;
    wire [DATA_W-1:0] write_m_wdata_o;
    wire [(DATA_W/8)-1:0] write_m_wstrb_o;
    wire write_m_wlast_o;
    reg write_m_bvalid_i;
    wire write_m_bready_o;
    reg [1:0] write_m_bresp_i;
    wire write_done_valid_o;
    reg write_done_ready_i;
    wire write_error_o;
    wire write_busy_o;

    integer cycle_count;

    sqe_axi_read_handler #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .LEN_W(LEN_W),
        .ENTRY_COUNT_W(ENTRY_COUNT_W),
        .BEAT_COUNT_W(BEAT_COUNT_W),
        .ENTRY_BEATS(2)
    ) u_read (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .cmd_valid_i(read_cmd_valid_i),
        .cmd_ready_o(read_cmd_ready_o),
        .cmd_addr_i(read_cmd_addr_i),
        .cmd_entry_count_i(read_cmd_entry_count_i),
        .m_arvalid_o(read_m_arvalid_o),
        .m_arready_i(read_m_arready_i),
        .m_araddr_o(read_m_araddr_o),
        .m_arlen_o(read_m_arlen_o),
        .m_rvalid_i(read_m_rvalid_i),
        .m_rready_o(read_m_rready_o),
        .m_rdata_i(read_m_rdata_i),
        .m_rlast_i(read_m_rlast_i),
        .m_rresp_i(read_m_rresp_i),
        .sqe_valid_o(read_sqe_valid_o),
        .sqe_ready_i(read_sqe_ready_i),
        .sqe_data_o(read_sqe_data_o),
        .sqe_entry_last_o(read_sqe_entry_last_o),
        .done_valid_o(read_done_valid_o),
        .done_ready_i(read_done_ready_i),
        .error_o(read_error_o),
        .busy_o(read_busy_o),
        .beats_rem_o(read_beats_rem_o)
    );

    cqe_axi_write_handler #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .LEN_W(LEN_W)
    ) u_write (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .cmd_valid_i(write_cmd_valid_i),
        .cmd_ready_o(write_cmd_ready_o),
        .cmd_addr_i(write_cmd_addr_i),
        .cmd_data_i(write_cmd_data_i),
        .cmd_phase_i(write_cmd_phase_i),
        .m_awvalid_o(write_m_awvalid_o),
        .m_awready_i(write_m_awready_i),
        .m_awaddr_o(write_m_awaddr_o),
        .m_awlen_o(write_m_awlen_o),
        .m_wvalid_o(write_m_wvalid_o),
        .m_wready_i(write_m_wready_i),
        .m_wdata_o(write_m_wdata_o),
        .m_wstrb_o(write_m_wstrb_o),
        .m_wlast_o(write_m_wlast_o),
        .m_bvalid_i(write_m_bvalid_i),
        .m_bready_o(write_m_bready_o),
        .m_bresp_i(write_m_bresp_i),
        .done_valid_o(write_done_valid_o),
        .done_ready_i(write_done_ready_i),
        .error_o(write_error_o),
        .busy_o(write_busy_o)
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
            read_cmd_valid_i = 1'b0;
            read_cmd_addr_i = {ADDR_W{1'b0}};
            read_cmd_entry_count_i = {ENTRY_COUNT_W{1'b0}};
            read_m_arready_i = 1'b0;
            read_m_rvalid_i = 1'b0;
            read_m_rdata_i = {DATA_W{1'b0}};
            read_m_rlast_i = 1'b0;
            read_m_rresp_i = 2'b00;
            read_sqe_ready_i = 1'b0;
            read_done_ready_i = 1'b0;

            write_cmd_valid_i = 1'b0;
            write_cmd_addr_i = {ADDR_W{1'b0}};
            write_cmd_data_i = {DATA_W{1'b0}};
            write_cmd_phase_i = 1'b0;
            write_m_awready_i = 1'b0;
            write_m_wready_i = 1'b0;
            write_m_bvalid_i = 1'b0;
            write_m_bresp_i = 2'b00;
            write_done_ready_i = 1'b0;
        end
    endtask

    task reset_dut;
        begin
            rst_i = 1'b1;
            idle_inputs();
            repeat (2) step();
            rst_i = 1'b0;
            step();

            if (read_cmd_ready_o !== 1'b1 || read_busy_o !== 1'b0 || read_done_valid_o !== 1'b0) begin
                fail("bad read reset release state");
            end
            if (write_cmd_ready_o !== 1'b1 || write_busy_o !== 1'b0 || write_done_valid_o !== 1'b0) begin
                fail("bad write reset release state");
            end
        end
    endtask

    task start_read_cmd;
        input [ADDR_W-1:0] addr;
        input [ENTRY_COUNT_W-1:0] entries;
        input [LEN_W-1:0] expected_arlen;
        begin
            if (read_cmd_ready_o !== 1'b1) begin
                fail("read command should be ready");
            end
            read_cmd_addr_i = addr;
            read_cmd_entry_count_i = entries;
            read_cmd_valid_i = 1'b1;
            step();
            read_cmd_valid_i = 1'b0;
            read_cmd_addr_i = {ADDR_W{1'b0}};
            read_cmd_entry_count_i = {ENTRY_COUNT_W{1'b0}};

            if (read_busy_o !== 1'b1 || read_m_arvalid_o !== 1'b1) begin
                fail("read command should create AR request");
            end
            if (read_m_araddr_o !== addr || read_m_arlen_o !== expected_arlen) begin
                fail("read AR payload mismatch");
            end
        end
    endtask

    task accept_read_ar;
        begin
            read_m_arready_i = 1'b1;
            if (read_m_arvalid_o !== 1'b1) begin
                fail("expected read ARVALID");
            end
            step();
            read_m_arready_i = 1'b0;
            if (read_m_arvalid_o !== 1'b0) begin
                fail("read ARVALID should clear after acceptance");
            end
        end
    endtask

    task send_read_beat;
        input [DATA_W-1:0] data;
        input rlast;
        input [1:0] rresp;
        input expected_entry_last;
        begin
            read_m_rdata_i = data;
            read_m_rlast_i = rlast;
            read_m_rresp_i = rresp;
            read_m_rvalid_i = 1'b1;
            read_sqe_ready_i = 1'b1;
            #1;
            if (read_m_rready_o !== 1'b1 || read_sqe_valid_o !== 1'b1) begin
                fail("expected read R beat acceptance");
            end
            if (read_sqe_data_o !== data) begin
                fail("read data stream mismatch");
            end
            if (read_sqe_entry_last_o !== expected_entry_last) begin
                fail("SQE entry boundary mismatch");
            end
            step();
            read_m_rvalid_i = 1'b0;
            read_sqe_ready_i = 1'b0;
            read_m_rdata_i = {DATA_W{1'b0}};
            read_m_rlast_i = 1'b0;
            read_m_rresp_i = 2'b00;
        end
    endtask

    task consume_read_done;
        begin
            read_done_ready_i = 1'b1;
            step();
            read_done_ready_i = 1'b0;
            if (read_done_valid_o !== 1'b0 || read_cmd_ready_o !== 1'b1) begin
                fail("read done should clear and command should become ready");
            end
        end
    endtask

    task start_write_cmd;
        input [ADDR_W-1:0] addr;
        input [DATA_W-1:0] data;
        input phase;
        begin
            if (write_cmd_ready_o !== 1'b1) begin
                fail("write command should be ready");
            end
            write_cmd_addr_i = addr;
            write_cmd_data_i = data;
            write_cmd_phase_i = phase;
            write_cmd_valid_i = 1'b1;
            step();
            write_cmd_valid_i = 1'b0;
            write_cmd_addr_i = {ADDR_W{1'b0}};
            write_cmd_data_i = {DATA_W{1'b0}};
            write_cmd_phase_i = 1'b0;

            if (write_busy_o !== 1'b1 || write_m_awvalid_o !== 1'b1) begin
                fail("write command should create AW request");
            end
            if (write_m_awaddr_o !== addr || write_m_awlen_o !== 8'd0) begin
                fail("write AW payload mismatch");
            end
        end
    endtask

    task accept_write_aw;
        begin
            write_m_awready_i = 1'b1;
            if (write_m_awvalid_o !== 1'b1) begin
                fail("expected write AWVALID");
            end
            step();
            write_m_awready_i = 1'b0;
            if (write_m_awvalid_o !== 1'b0) begin
                fail("write AWVALID should clear after acceptance");
            end
        end
    endtask

    task accept_write_w;
        input [DATA_W-1:0] expected_data;
        begin
            if (write_m_wvalid_o !== 1'b1 || write_m_wlast_o !== 1'b1) begin
                fail("expected single-beat W payload");
            end
            if (write_m_wdata_o !== expected_data || write_m_wstrb_o !== 4'hf) begin
                fail("write W payload mismatch");
            end
            write_m_wready_i = 1'b1;
            step();
            write_m_wready_i = 1'b0;
            if (write_m_bready_o !== 1'b1) begin
                fail("BREADY should assert after single W beat");
            end
        end
    endtask

    task accept_write_b;
        input [1:0] bresp;
        input expected_error;
        begin
            write_m_bresp_i = bresp;
            write_m_bvalid_i = 1'b1;
            if (write_m_bready_o !== 1'b1) begin
                fail("expected BREADY");
            end
            step();
            write_m_bvalid_i = 1'b0;
            write_m_bresp_i = 2'b00;
            if (write_done_valid_o !== 1'b1 || write_error_o !== expected_error) begin
                fail("unexpected write completion");
            end
        end
    endtask

    task consume_write_done;
        begin
            write_done_ready_i = 1'b1;
            step();
            write_done_ready_i = 1'b0;
            if (write_done_valid_o !== 1'b0 || write_cmd_ready_o !== 1'b1) begin
                fail("write done should clear and command should become ready");
            end
        end
    endtask

    initial begin
        cycle_count = 0;
        reset_dut();

        start_read_cmd(32'h0000_1000, 3'd2, 8'd3);
        if (read_beats_rem_o !== 9'd4) begin
            fail("two SQE entries should create four AXI beats");
        end

        step();
        if (read_m_arvalid_o !== 1'b1 || read_m_araddr_o !== 32'h0000_1000 || read_m_arlen_o !== 8'd3) begin
            fail("read AR payload did not hold while stalled");
        end

        read_m_rvalid_i = 1'b1;
        read_sqe_ready_i = 1'b1;
        if (read_m_rready_o !== 1'b0) begin
            fail("read handler must not accept R before AR acceptance");
        end
        read_m_rvalid_i = 1'b0;
        read_sqe_ready_i = 1'b0;

        accept_read_ar();
        send_read_beat(32'h0000_0001, 1'b0, 2'b00, 1'b0);
        if (read_beats_rem_o !== 9'd3) begin
            fail("read beat count after first beat wrong");
        end

        read_m_rdata_i = 32'h0000_0002;
        read_m_rvalid_i = 1'b1;
        read_sqe_ready_i = 1'b0;
        #1;
        if (read_m_rready_o !== 1'b0 || read_beats_rem_o !== 9'd3) begin
            fail("read backpressure should hold beat count");
        end
        step();
        read_m_rvalid_i = 1'b0;

        send_read_beat(32'h0000_0002, 1'b0, 2'b00, 1'b1);
        send_read_beat(32'h0000_0003, 1'b0, 2'b00, 1'b0);
        if (read_done_valid_o !== 1'b0) begin
            fail("read completion appeared before final expected beat");
        end
        send_read_beat(32'h0000_0004, 1'b1, 2'b00, 1'b1);
        if (read_done_valid_o !== 1'b1 || read_error_o !== 1'b0) begin
            fail("expected clean read completion");
        end
        consume_read_done();

        start_read_cmd(32'h0000_2000, 3'd1, 8'd1);
        accept_read_ar();
        send_read_beat(32'h0000_0011, 1'b0, 2'b10, 1'b0);
        send_read_beat(32'h0000_0012, 1'b1, 2'b00, 1'b1);
        if (read_done_valid_o !== 1'b1 || read_error_o !== 1'b1) begin
            fail("read response error should be captured through final beat");
        end
        consume_read_done();

        start_write_cmd(32'h0000_3000, 32'h1234_5678, 1'b1);
        step();
        if (write_m_awvalid_o !== 1'b1 || write_m_awaddr_o !== 32'h0000_3000) begin
            fail("write AW payload did not hold while stalled");
        end
        if (write_m_wvalid_o !== 1'b0 || write_m_bready_o !== 1'b0) begin
            fail("write W/B channels should wait for AW acceptance in this slice");
        end
        accept_write_aw();

        write_m_wready_i = 1'b0;
        #1;
        if (write_m_wvalid_o !== 1'b1 || write_m_wlast_o !== 1'b1) begin
            fail("write W payload should hold while stalled");
        end
        step();
        if (write_m_bready_o !== 1'b0) begin
            fail("write response must wait until W beat accepted");
        end
        accept_write_w(32'h1234_5679);
        step();
        if (write_done_valid_o !== 1'b0) begin
            fail("write completion must wait for B response");
        end
        accept_write_b(2'b00, 1'b0);
        consume_write_done();

        start_write_cmd(32'h0000_3040, 32'h89ab_cdef, 1'b0);
        accept_write_aw();
        accept_write_w(32'h89ab_cdee);
        accept_write_b(2'b10, 1'b1);
        consume_write_done();

        $display("PASS vfs sw hw axi handlers");
        $finish;
    end
endmodule
