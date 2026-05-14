`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;
    reg cmd_valid_i;
    wire cmd_ready_o;
    reg [1:0] cmd_id_i;
    reg [7:0] cmd_arlen_i;
    reg m_rvalid_i;
    wire m_rready_o;
    reg [1:0] m_rid_i;
    reg m_rlast_i;
    reg [1:0] m_rresp_i;
    wire done_valid_o;
    reg done_ready_i;
    wire [1:0] done_id_o;
    wire done_error_o;
    wire [3:0] active_o;

    integer cycle_count;

    axi_read_id_scoreboard dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .cmd_valid_i(cmd_valid_i),
        .cmd_ready_o(cmd_ready_o),
        .cmd_id_i(cmd_id_i),
        .cmd_arlen_i(cmd_arlen_i),
        .m_rvalid_i(m_rvalid_i),
        .m_rready_o(m_rready_o),
        .m_rid_i(m_rid_i),
        .m_rlast_i(m_rlast_i),
        .m_rresp_i(m_rresp_i),
        .done_valid_o(done_valid_o),
        .done_ready_i(done_ready_i),
        .done_id_o(done_id_o),
        .done_error_o(done_error_o),
        .active_o(active_o)
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
            cmd_id_i = 2'd0;
            cmd_arlen_i = 8'd0;
            m_rvalid_i = 1'b0;
            m_rid_i = 2'd0;
            m_rlast_i = 1'b0;
            m_rresp_i = 2'b00;
            done_ready_i = 1'b0;
        end
    endtask

    task accept_cmd;
        input [1:0] id;
        input [7:0] arlen;
        begin
            cmd_id_i = id;
            cmd_arlen_i = arlen;
            cmd_valid_i = 1'b1;
            #1;
            if (cmd_ready_o !== 1'b1) begin
                fail("expected command ready");
            end
            step();
            cmd_valid_i = 1'b0;
            cmd_arlen_i = 8'd0;
        end
    endtask

    task send_r;
        input [1:0] id;
        input rlast;
        input [1:0] rresp;
        begin
            m_rid_i = id;
            m_rlast_i = rlast;
            m_rresp_i = rresp;
            m_rvalid_i = 1'b1;
            #1;
            if (m_rready_o !== 1'b1) begin
                fail("expected R ready for active ID");
            end
            step();
            m_rvalid_i = 1'b0;
            m_rlast_i = 1'b0;
            m_rresp_i = 2'b00;
        end
    endtask

    task expect_done;
        input [1:0] id;
        input error;
        begin
            if (done_valid_o !== 1'b1) begin
                fail("expected done valid");
            end
            if (done_id_o !== id) begin
                fail("unexpected done ID");
            end
            if (done_error_o !== error) begin
                fail("unexpected done error");
            end
        end
    endtask

    task consume_done;
        begin
            done_ready_i = 1'b1;
            step();
            done_ready_i = 1'b0;
            if (done_valid_o !== 1'b0) begin
                fail("done should clear after acceptance");
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
        if (active_o !== 4'b0000 || done_valid_o !== 1'b0) begin
            fail("bad reset release state");
        end

        accept_cmd(2'd0, 8'd1);
        accept_cmd(2'd1, 8'd0);
        if (active_o[0] !== 1'b1 || active_o[1] !== 1'b1) begin
            fail("ID0 and ID1 should both be active");
        end

        cmd_id_i = 2'd0;
        cmd_arlen_i = 8'd0;
        cmd_valid_i = 1'b1;
        #1;
        if (cmd_ready_o !== 1'b0) begin
            fail("same active ID should not accept second command");
        end
        step();
        cmd_valid_i = 1'b0;

        m_rid_i = 2'd3;
        m_rlast_i = 1'b1;
        m_rvalid_i = 1'b1;
        #1;
        if (m_rready_o !== 1'b0) begin
            fail("inactive ID response should not be accepted");
        end
        step();
        m_rvalid_i = 1'b0;

        send_r(2'd1, 1'b1, 2'b00);
        expect_done(2'd1, 1'b0);
        consume_done();

        send_r(2'd0, 1'b0, 2'b00);
        if (done_valid_o !== 1'b0) begin
            fail("ID0 should not complete before final beat");
        end
        send_r(2'd0, 1'b1, 2'b00);
        expect_done(2'd0, 1'b0);
        consume_done();

        accept_cmd(2'd2, 8'd1);
        send_r(2'd2, 1'b1, 2'b00);
        if (done_valid_o !== 1'b0) begin
            fail("early RLAST must not complete ID2");
        end
        send_r(2'd2, 1'b1, 2'b00);
        expect_done(2'd2, 1'b1);
        consume_done();

        accept_cmd(2'd3, 8'd0);
        send_r(2'd3, 1'b1, 2'b10);
        expect_done(2'd3, 1'b1);
        consume_done();

        if (active_o !== 4'b0000) begin
            fail("all IDs should be inactive at end");
        end

        $display("PASS axi read id scoreboard");
        $finish;
    end
endmodule
