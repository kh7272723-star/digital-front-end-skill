`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;
    reg valid_i;
    wire ready_o;
    reg [31:0] data_i;
    reg [3:0] keep_i;
    reg last_i;
    wire valid_o;
    reg ready_i;
    wire [127:0] data_o;
    wire [15:0] keep_o;
    wire last_o;

    integer cycle_count;

    stream_width_converter dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .valid_i(valid_i),
        .ready_o(ready_o),
        .data_i(data_i),
        .keep_i(keep_i),
        .last_i(last_i),
        .valid_o(valid_o),
        .ready_i(ready_i),
        .data_o(data_o),
        .keep_o(keep_o),
        .last_o(last_o)
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

    task send_lane;
        input [31:0] data;
        input [3:0] keep;
        input last;
        begin
            #1;
            if (!ready_o) begin
                fail("converter should be ready for directed input");
            end
            valid_i = 1'b1;
            data_i = data;
            keep_i = keep;
            last_i = last;
            step();
            valid_i = 1'b0;
            last_i = 1'b0;
        end
    endtask

    task expect_output;
        input [127:0] expected_data;
        input [15:0] expected_keep;
        input expected_last;
        begin
            #1;
            if (!valid_o) begin
                fail("expected output valid");
            end
            if (data_o !== expected_data) begin
                fail("unexpected packed data");
            end
            if (keep_o !== expected_keep) begin
                fail("unexpected packed keep");
            end
            if (last_o !== expected_last) begin
                fail("unexpected last flag");
            end
        end
    endtask

    initial begin
        cycle_count = 0;
        rst_i = 1'b1;
        valid_i = 1'b0;
        data_i = 32'h0;
        keep_i = 4'h0;
        last_i = 1'b0;
        ready_i = 1'b1;

        repeat (2) step();
        rst_i = 1'b0;
        step();

        send_lane(32'h1111_1111, 4'hf, 1'b0);
        send_lane(32'h2222_2222, 4'hf, 1'b0);
        send_lane(32'h3333_3333, 4'hf, 1'b0);
        send_lane(32'h4444_4444, 4'hf, 1'b1);
        expect_output(128'h4444_4444_3333_3333_2222_2222_1111_1111, 16'hffff, 1'b1);

        ready_i = 1'b0;
        step();
        expect_output(128'h4444_4444_3333_3333_2222_2222_1111_1111, 16'hffff, 1'b1);

        ready_i = 1'b1;
        step();
        if (valid_o) begin
            fail("output should clear after downstream accept");
        end

        send_lane(32'haaaa_0001, 4'hf, 1'b0);
        ready_i = 1'b0;
        send_lane(32'hbbbb_0002, 4'h3, 1'b1);
        expect_output(128'h0000_0000_0000_0000_bbbb_0002_aaaa_0001, 16'h003f, 1'b1);
        data_i = 32'hffff_ffff;
        keep_i = 4'h0;
        step();
        expect_output(128'h0000_0000_0000_0000_bbbb_0002_aaaa_0001, 16'h003f, 1'b1);

        ready_i = 1'b1;
        step();

        $display("PASS stream width converter");
        $finish;
    end
endmodule
