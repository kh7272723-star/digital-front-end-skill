`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;
    reg valid_i;
    wire ready_o;
    reg [7:0] data_i;
    wire valid_o;
    reg ready_i;
    wire [7:0] data_o;
    reg ack_i;
    reg nak_i;
    wire full_o;
    wire in_flight_o;

    integer cycle_count;

    retry_buffer dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .valid_i(valid_i),
        .ready_o(ready_o),
        .data_i(data_i),
        .valid_o(valid_o),
        .ready_i(ready_i),
        .data_o(data_o),
        .ack_i(ack_i),
        .nak_i(nak_i),
        .full_o(full_o),
        .in_flight_o(in_flight_o)
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

    task send_byte;
        input [7:0] value;
        begin
            #1;
            if (!ready_o) begin
                fail("retry buffer not ready for directed input");
            end
            valid_i = 1'b1;
            data_i = value;
            step();
            valid_i = 1'b0;
        end
    endtask

    task expect_and_accept;
        input [7:0] expected;
        begin
            #1;
            if (!valid_o) begin
                fail("expected valid output");
            end
            if (data_o !== expected) begin
                fail("unexpected retry buffer output data");
            end
            ready_i = 1'b1;
            step();
            ready_i = 1'b0;
        end
    endtask

    task issue_ack;
        begin
            ack_i = 1'b1;
            step();
            ack_i = 1'b0;
        end
    endtask

    initial begin
        cycle_count = 0;
        rst_i = 1'b1;
        valid_i = 1'b0;
        data_i = 8'h00;
        ready_i = 1'b0;
        ack_i = 1'b0;
        nak_i = 1'b0;

        repeat (2) step();
        rst_i = 1'b0;
        step();

        send_byte(8'ha1);
        send_byte(8'ha2);
        send_byte(8'ha3);
        if (!in_flight_o) begin
            fail("expected in-flight data");
        end

        expect_and_accept(8'ha1);
        expect_and_accept(8'ha2);

        nak_i = 1'b1;
        step();
        nak_i = 1'b0;

        expect_and_accept(8'ha1);
        expect_and_accept(8'ha2);
        expect_and_accept(8'ha3);

        issue_ack();
        issue_ack();
        issue_ack();
        if (in_flight_o) begin
            fail("in-flight flag should clear after all acknowledgements");
        end

        send_byte(8'hb0);
        send_byte(8'hb1);
        send_byte(8'hb2);
        send_byte(8'hb3);
        #1;
        if (!full_o || ready_o) begin
            fail("full state should block new input");
        end

        valid_i = 1'b1;
        data_i = 8'hff;
        step();
        valid_i = 1'b0;
        expect_and_accept(8'hb0);
        issue_ack();
        if (!ready_o) begin
            fail("one acknowledgement should open one slot");
        end

        $display("PASS retry buffer");
        $finish;
    end
endmodule
