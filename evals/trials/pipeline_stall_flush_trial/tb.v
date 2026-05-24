`timescale 1ns/1ps

module tb;

    reg        clk_i;
    reg        rst_i;
    reg        flush_i;
    reg        stall_i;
    reg        valid_i;
    reg  [7:0] data_i;
    wire       valid_o;
    wire [7:0] data_o;

    integer cycle_count;

    rv_pipeline_stage #(
        .DATA_W(8)
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .flush_i(flush_i),
        .stall_i(stall_i),
        .valid_i(valid_i),
        .data_i(data_i),
        .valid_o(valid_o),
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
        flush_i = 1'b0;
        stall_i = 1'b0;
        valid_i = 1'b0;
        data_i = 8'h00;

        repeat (2) step();

        if (valid_o) fail("valid_o should be low after reset");

        rst_i = 1'b0;
        step();

        // Normal transfer
        valid_i = 1'b1;
        data_i = 8'hA1;
        step();
        if (!valid_o) fail("valid_o should be high after normal transfer");
        if (data_o !== 8'hA1) fail("data_o mismatch on normal transfer");

        // Back-to-back transfer
        data_i = 8'hA2;
        step();
        if (data_o !== 8'hA2) fail("data_o mismatch on back-to-back");

        // Stall: valid/data should hold stable
        stall_i = 1'b1;
        data_i = 8'hFF;
        valid_i = 1'b1;
        step();
        if (data_o !== 8'hA2) fail("data_o changed during stall");
        if (!valid_o) fail("valid_o changed during stall");
        step();
        if (data_o !== 8'hA2) fail("data_o changed during prolonged stall");

        // Release stall
        stall_i = 1'b0;
        step();
        if (data_o !== 8'hFF) fail("data_o should update after stall release");

        // Flush: valid_o should clear
        valid_i = 1'b1;
        data_i = 8'hB1;
        step();
        if (!valid_o) fail("valid_o should be high before flush");
        flush_i = 1'b1;
        step();
        if (valid_o) fail("valid_o should be low after flush");
        flush_i = 1'b0;

        // Flush during stall: flush wins
        // First load valid data into the stage
        valid_i = 1'b1;
        data_i = 8'hC1;
        stall_i = 1'b0;
        step();
        if (!valid_o) fail("valid_o should be high before flush-during-stall");
        // Now stall + flush simultaneously
        stall_i = 1'b1;
        flush_i = 1'b1;
        step();
        if (valid_o) fail("valid_o should be low after flush wins over stall");
        flush_i = 1'b0;
        stall_i = 1'b0;

        // Drain: no more valid input
        valid_i = 1'b0;
        step();
        if (valid_o) fail("valid_o should be low with no valid input");

        $display("PASS pipeline stage");
        $finish;
    end

endmodule
