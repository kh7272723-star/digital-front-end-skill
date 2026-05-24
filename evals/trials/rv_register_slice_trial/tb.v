`timescale 1ns/1ps

module tb;

    reg        clk_i;
    reg        rst_i;
    reg        valid_i;
    wire       ready_o;
    reg  [7:0] data_i;
    wire       valid_o;
    reg        ready_i;
    wire [7:0] data_o;

    integer cycle_count;
    reg  [7:0] hold_data;
    reg        hold_valid;

    rv_register_slice #(
        .DATA_W(8)
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .valid_i(valid_i),
        .ready_o(ready_o),
        .data_i(data_i),
        .valid_o(valid_o),
        .ready_i(ready_i),
        .data_o(data_o)
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

    initial begin
        cycle_count = 0;
        rst_i = 1'b1;
        valid_i = 1'b0;
        ready_i = 1'b1;
        data_i = 8'h00;

        repeat (2) step();

        // Reset: not valid, ready
        if (valid_o) fail("valid_o should be low after reset");
        if (!ready_o) fail("ready_o should be high after reset");

        rst_i = 1'b0;
        step();

        // Normal transfer: one-cycle latency
        valid_i = 1'b1;
        data_i = 8'hA1;
        step();
        // After one cycle, valid_o and data_o should reflect the input
        if (!valid_o) fail("valid_o should be high after transfer");
        if (data_o !== 8'hA1) fail("data_o mismatch after normal transfer");
        valid_i = 1'b0;
        data_i = 8'h00;
        step();

        // Back-to-back transfers
        valid_i = 1'b1;
        data_i = 8'hB1;
        step();
        if (data_o !== 8'hB1) fail("data_o mismatch on back-to-back 1");
        data_i = 8'hB2;
        step();
        if (data_o !== 8'hB2) fail("data_o mismatch on back-to-back 2");

        // Backpressure: valid_o and data_o must hold stable
        ready_i = 1'b0;
        hold_data = data_o;
        hold_valid = valid_o;
        data_i = 8'hFF;
        step();
        if (data_o !== hold_data) fail("data_o changed during backpressure");
        if (valid_o !== hold_valid) fail("valid_o changed during backpressure");
        step();
        if (data_o !== hold_data) fail("data_o changed during prolonged backpressure");

        // Release backpressure
        ready_i = 1'b1;
        step();
        // Now the new data should flow through
        if (data_o !== 8'hFF) fail("data_o should update after backpressure release");

        // Drain
        valid_i = 1'b0;
        step();
        if (valid_o) fail("valid_o should be low with no valid input");

        // ready_o should be high when empty
        if (!ready_o) fail("ready_o should be high when slice is empty");

        $display("PASS register slice");
        $finish;
    end

endmodule
