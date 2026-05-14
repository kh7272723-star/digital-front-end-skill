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

        $display("PASS dma burst planner");
        $finish;
    end
endmodule
