`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;

    reg cmd_valid_i;
    wire cmd_ready_o;
    reg [7:0] cmd_awlen_i;

    wire m_awvalid_o;
    reg m_awready_i;
    wire [7:0] m_awlen_o;

    reg wdata_valid_i;
    wire wdata_ready_o;
    wire m_wvalid_o;
    reg m_wready_i;
    wire m_wlast_o;

    reg m_bvalid_i;
    wire m_bready_o;
    reg [1:0] m_bresp_i;

    wire done_valid_o;
    reg done_ready_i;
    wire error_o;
    wire busy_o;
    wire [8:0] beats_rem_o;

    integer cycle_count;

    axi_write_burst_tracker dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .cmd_valid_i(cmd_valid_i),
        .cmd_ready_o(cmd_ready_o),
        .cmd_awlen_i(cmd_awlen_i),
        .m_awvalid_o(m_awvalid_o),
        .m_awready_i(m_awready_i),
        .m_awlen_o(m_awlen_o),
        .wdata_valid_i(wdata_valid_i),
        .wdata_ready_o(wdata_ready_o),
        .m_wvalid_o(m_wvalid_o),
        .m_wready_i(m_wready_i),
        .m_wlast_o(m_wlast_o),
        .m_bvalid_i(m_bvalid_i),
        .m_bready_o(m_bready_o),
        .m_bresp_i(m_bresp_i),
        .done_valid_o(done_valid_o),
        .done_ready_i(done_ready_i),
        .error_o(error_o),
        .busy_o(busy_o),
        .beats_rem_o(beats_rem_o)
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
            cmd_valid_i = 1'b0;
            cmd_awlen_i = 8'd0;
            m_awready_i = 1'b0;
            wdata_valid_i = 1'b0;
            m_wready_i = 1'b0;
            m_bvalid_i = 1'b0;
            m_bresp_i = 2'b00;
            done_ready_i = 1'b0;
        end
    endtask

    task start_cmd;
        input [7:0] awlen;
        begin
            cmd_awlen_i = awlen;
            cmd_valid_i = 1'b1;
            if (cmd_ready_o !== 1'b1) begin
                fail("command should be ready");
            end
            step();
            cmd_valid_i = 1'b0;
            cmd_awlen_i = 8'd0;
            if (busy_o !== 1'b1 || m_awvalid_o !== 1'b1) begin
                fail("command should create AW pending burst");
            end
            if (m_awlen_o !== awlen) begin
                fail("AWLEN not held after command");
            end
        end
    endtask

    task accept_aw;
        begin
            m_awready_i = 1'b1;
            if (m_awvalid_o !== 1'b1) begin
                fail("expected AWVALID before AW accept");
            end
            step();
            m_awready_i = 1'b0;
            if (m_awvalid_o !== 1'b0) begin
                fail("AWVALID should clear after AW accept");
            end
        end
    endtask

    task send_w;
        input expected_last;
        begin
            wdata_valid_i = 1'b1;
            m_wready_i = 1'b1;
            #1;
            if (m_wvalid_o !== 1'b1) begin
                fail("expected WVALID");
            end
            if (wdata_ready_o !== 1'b1) begin
                fail("expected upstream data ready");
            end
            if (m_wlast_o !== expected_last) begin
                fail("unexpected WLAST");
            end
            step();
            wdata_valid_i = 1'b0;
            m_wready_i = 1'b0;
        end
    endtask

    task accept_b;
        input [1:0] bresp;
        input expected_error;
        begin
            m_bresp_i = bresp;
            m_bvalid_i = 1'b1;
            #1;
            if (m_bready_o !== 1'b1) begin
                fail("expected BREADY");
            end
            step();
            m_bvalid_i = 1'b0;
            m_bresp_i = 2'b00;
            if (done_valid_o !== 1'b1) begin
                fail("expected done after B response");
            end
            if (error_o !== expected_error) begin
                fail("unexpected error flag after B response");
            end
        end
    endtask

    task consume_done;
        begin
            done_ready_i = 1'b1;
            step();
            done_ready_i = 1'b0;
            if (done_valid_o !== 1'b0 || cmd_ready_o !== 1'b1) begin
                fail("done should clear and command should become ready");
            end
        end
    endtask

    initial begin
        cycle_count = 0;
        rst_i = 1'b1;
        idle_inputs();
        repeat (2) step();
        rst_i = 1'b0;
        step();
        if (cmd_ready_o !== 1'b1 || busy_o !== 1'b0 || done_valid_o !== 1'b0) begin
            fail("bad reset release state");
        end

        start_cmd(8'd3);
        if (beats_rem_o !== 9'd4) begin
            fail("AWLEN=3 should create 4 beats");
        end

        step();
        if (m_awvalid_o !== 1'b1 || m_awlen_o !== 8'd3) begin
            fail("AW channel did not hold while stalled");
        end
        step();
        if (m_awvalid_o !== 1'b1 || m_awlen_o !== 8'd3) begin
            fail("AW channel changed during second stall");
        end

        wdata_valid_i = 1'b1;
        m_wready_i = 1'b1;
        if (m_wvalid_o !== 1'b0 || wdata_ready_o !== 1'b0) begin
            fail("W channel should not issue before AW acceptance in this slice");
        end
        wdata_valid_i = 1'b0;
        m_wready_i = 1'b0;

        accept_aw();
        send_w(1'b0);
        if (beats_rem_o !== 9'd3) begin
            fail("beat count after first W beat wrong");
        end

        wdata_valid_i = 1'b1;
        m_wready_i = 1'b0;
        #1;
        if (m_wvalid_o !== 1'b1 || wdata_ready_o !== 1'b0 || m_wlast_o !== 1'b0) begin
            fail("W backpressure behavior wrong");
        end
        step();
        if (beats_rem_o !== 9'd3) begin
            fail("beat count changed while WREADY low");
        end
        m_wready_i = 1'b1;
        #1;
        if (m_wlast_o !== 1'b0) begin
            fail("second W beat should not be last");
        end
        step();
        wdata_valid_i = 1'b0;
        m_wready_i = 1'b0;

        send_w(1'b0);
        send_w(1'b1);
        if (beats_rem_o !== 9'd0) begin
            fail("all W beats should be consumed");
        end
        if (done_valid_o !== 1'b0) begin
            fail("last W beat must not complete burst before B response");
        end
        if (m_bready_o !== 1'b1) begin
            fail("BREADY should assert after all W beats");
        end

        step();
        if (done_valid_o !== 1'b0) begin
            fail("B delay should hold completion low");
        end

        accept_b(2'b00, 1'b0);
        step();
        if (done_valid_o !== 1'b1 || error_o !== 1'b0) begin
            fail("done should hold while done_ready_i is low");
        end
        consume_done();

        start_cmd(8'd0);
        accept_aw();
        send_w(1'b1);
        accept_b(2'b10, 1'b1);
        consume_done();

        $display("PASS axi write tracker");
        $finish;
    end
endmodule
