`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;

    reg cmd_valid_i;
    wire cmd_ready_o;
    reg [7:0] cmd_arlen_i;

    wire m_arvalid_o;
    reg m_arready_i;
    wire [7:0] m_arlen_o;

    reg rdata_ready_i;
    reg m_rvalid_i;
    wire m_rready_o;
    reg m_rlast_i;
    reg [1:0] m_rresp_i;

    wire done_valid_o;
    reg done_ready_i;
    wire error_o;
    wire busy_o;
    wire [8:0] beats_rem_o;

    integer cycle_count;

    axi_read_burst_tracker dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .cmd_valid_i(cmd_valid_i),
        .cmd_ready_o(cmd_ready_o),
        .cmd_arlen_i(cmd_arlen_i),
        .m_arvalid_o(m_arvalid_o),
        .m_arready_i(m_arready_i),
        .m_arlen_o(m_arlen_o),
        .rdata_ready_i(rdata_ready_i),
        .m_rvalid_i(m_rvalid_i),
        .m_rready_o(m_rready_o),
        .m_rlast_i(m_rlast_i),
        .m_rresp_i(m_rresp_i),
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
            cmd_arlen_i = 8'd0;
            m_arready_i = 1'b0;
            rdata_ready_i = 1'b0;
            m_rvalid_i = 1'b0;
            m_rlast_i = 1'b0;
            m_rresp_i = 2'b00;
            done_ready_i = 1'b0;
        end
    endtask

    task start_cmd;
        input [7:0] arlen;
        begin
            cmd_arlen_i = arlen;
            cmd_valid_i = 1'b1;
            if (cmd_ready_o !== 1'b1) begin
                fail("command should be ready");
            end
            step();
            cmd_valid_i = 1'b0;
            cmd_arlen_i = 8'd0;
            if (busy_o !== 1'b1 || m_arvalid_o !== 1'b1) begin
                fail("command should create AR pending burst");
            end
            if (m_arlen_o !== arlen) begin
                fail("ARLEN not held after command");
            end
        end
    endtask

    task accept_ar;
        begin
            m_arready_i = 1'b1;
            if (m_arvalid_o !== 1'b1) begin
                fail("expected ARVALID before AR accept");
            end
            step();
            m_arready_i = 1'b0;
            if (m_arvalid_o !== 1'b0) begin
                fail("ARVALID should clear after AR accept");
            end
        end
    endtask

    task send_r;
        input rlast;
        input [1:0] rresp;
        begin
            m_rvalid_i = 1'b1;
            m_rlast_i = rlast;
            m_rresp_i = rresp;
            rdata_ready_i = 1'b1;
            #1;
            if (m_rready_o !== 1'b1) begin
                fail("expected RREADY");
            end
            step();
            m_rvalid_i = 1'b0;
            m_rlast_i = 1'b0;
            m_rresp_i = 2'b00;
            rdata_ready_i = 1'b0;
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
            fail("ARLEN=3 should create 4 beats");
        end

        step();
        if (m_arvalid_o !== 1'b1 || m_arlen_o !== 8'd3) begin
            fail("AR channel did not hold while stalled");
        end
        step();
        if (m_arvalid_o !== 1'b1 || m_arlen_o !== 8'd3) begin
            fail("AR channel changed during second stall");
        end

        m_rvalid_i = 1'b1;
        rdata_ready_i = 1'b1;
        if (m_rready_o !== 1'b0) begin
            fail("R channel should not accept before AR acceptance");
        end
        m_rvalid_i = 1'b0;
        rdata_ready_i = 1'b0;

        accept_ar();
        send_r(1'b0, 2'b00);
        if (beats_rem_o !== 9'd3) begin
            fail("beat count after first R beat wrong");
        end

        m_rvalid_i = 1'b1;
        m_rlast_i = 1'b0;
        m_rresp_i = 2'b00;
        rdata_ready_i = 1'b0;
        #1;
        if (m_rready_o !== 1'b0) begin
            fail("RREADY should be low when local sink is not ready");
        end
        step();
        if (beats_rem_o !== 9'd3) begin
            fail("beat count changed while RREADY low");
        end
        m_rvalid_i = 1'b0;
        m_rlast_i = 1'b0;
        m_rresp_i = 2'b00;

        send_r(1'b0, 2'b00);
        send_r(1'b0, 2'b00);
        if (done_valid_o !== 1'b0) begin
            fail("middle R beat must not complete burst");
        end
        send_r(1'b1, 2'b00);
        if (done_valid_o !== 1'b1 || error_o !== 1'b0) begin
            fail("expected clean completion after final R beat");
        end
        step();
        if (done_valid_o !== 1'b1 || error_o !== 1'b0) begin
            fail("done should hold while done_ready_i is low");
        end
        consume_done();

        start_cmd(8'd0);
        accept_ar();
        send_r(1'b1, 2'b10);
        if (done_valid_o !== 1'b1 || error_o !== 1'b1) begin
            fail("RRESP error should produce error completion");
        end
        consume_done();

        start_cmd(8'd1);
        accept_ar();
        send_r(1'b1, 2'b00);
        if (done_valid_o !== 1'b0) begin
            fail("early RLAST should not complete before expected beat count");
        end
        if (beats_rem_o !== 9'd1) begin
            fail("early RLAST should still decrement one expected beat");
        end
        send_r(1'b1, 2'b00);
        if (done_valid_o !== 1'b1 || error_o !== 1'b1) begin
            fail("RLAST mismatch should be reported at completion");
        end
        consume_done();

        $display("PASS axi read tracker");
        $finish;
    end
endmodule
