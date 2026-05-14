`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;
    reg consume_i;
    reg return_valid_i;
    reg [2:0] return_count_i;
    wire credit_available_o;
    wire [2:0] credit_count_o;
    wire underflow_o;
    wire overflow_o;

    integer cycle_count;

    credit_counter #(
        .COUNT_W(3),
        .MAX_CREDITS(4)
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .consume_i(consume_i),
        .return_valid_i(return_valid_i),
        .return_count_i(return_count_i),
        .credit_available_o(credit_available_o),
        .credit_count_o(credit_count_o),
        .underflow_o(underflow_o),
        .overflow_o(overflow_o)
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

    task expect_count;
        input [2:0] expected;
        begin
            if (credit_count_o !== expected) begin
                fail("unexpected credit count");
            end
        end
    endtask

    initial begin
        cycle_count = 0;
        rst_i = 1'b1;
        consume_i = 1'b0;
        return_valid_i = 1'b0;
        return_count_i = 3'd0;

        repeat (2) step();
        expect_count(3'd4);
        if (!credit_available_o) begin
            fail("credit should be available after reset");
        end

        rst_i = 1'b0;
        step();
        expect_count(3'd4);

        consume_i = 1'b1;
        return_valid_i = 1'b0;
        step();
        expect_count(3'd3);
        step();
        expect_count(3'd2);
        step();
        expect_count(3'd1);
        step();
        expect_count(3'd0);
        if (credit_available_o) begin
            fail("credit_available_o should be low at zero");
        end

        step();
        expect_count(3'd0);
        if (!underflow_o) begin
            fail("underflow was not captured");
        end

        consume_i = 1'b0;
        return_valid_i = 1'b1;
        return_count_i = 3'd2;
        step();
        expect_count(3'd2);

        consume_i = 1'b1;
        return_valid_i = 1'b1;
        return_count_i = 3'd1;
        step();
        expect_count(3'd2);

        consume_i = 1'b0;
        return_count_i = 3'd4;
        step();
        expect_count(3'd4);
        if (!overflow_o) begin
            fail("overflow was not captured");
        end

        $display("PASS credit counter");
        $finish;
    end
endmodule
