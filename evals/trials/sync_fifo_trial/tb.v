`timescale 1ns/1ps

module tb;

    reg        clk_i;
    reg        rst_i;
    reg        wr_en_i;
    reg  [7:0] wdata_i;
    reg        rd_en_i;
    wire [7:0] rdata_o;
    wire       full_o;
    wire       empty_o;
    wire       overflow_o;
    wire       underflow_o;

    integer cycle_count;

    sync_fifo #(
        .DATA_W(8),
        .DEPTH(4)
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wr_en_i(wr_en_i),
        .wdata_i(wdata_i),
        .rd_en_i(rd_en_i),
        .rdata_o(rdata_o),
        .full_o(full_o),
        .empty_o(empty_o),
        .overflow_o(overflow_o),
        .underflow_o(underflow_o)
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

    task expect_data;
        input [7:0] expected;
        begin
            if (rdata_o !== expected) begin
                fail("unexpected rdata_o");
            end
        end
    endtask

    initial begin
        cycle_count = 0;
        rst_i = 1'b1;
        wr_en_i = 1'b0;
        wdata_i = 8'h00;
        rd_en_i = 1'b0;

        repeat (2) step();

        if (!empty_o) fail("should be empty after reset");
        if (full_o) fail("should not be full after reset");

        rst_i = 1'b0;
        step();

        // Normal write 4 items
        wr_en_i = 1'b1;
        wdata_i = 8'hA1; step();
        wdata_i = 8'hA2; step();
        wdata_i = 8'hA3; step();
        wdata_i = 8'hA4; step();
        wr_en_i = 1'b0;

        if (!full_o) fail("should be full after 4 writes");

        // Overflow attempt: write when full (should be rejected)
        wr_en_i = 1'b1;
        wdata_i = 8'hFF;
        step();
        wr_en_i = 1'b0;

        // Normal read 4 items
        rd_en_i = 1'b1;
        step();
        expect_data(8'hA1);
        step();
        expect_data(8'hA2);
        step();
        expect_data(8'hA3);
        step();
        expect_data(8'hA4);
        rd_en_i = 1'b0;

        if (!empty_o) fail("should be empty after 4 reads");

        // Underflow attempt: read when empty (should be rejected)
        rd_en_i = 1'b1;
        step();
        rd_en_i = 1'b0;

        // Simultaneous write+read: count should stay stable
        wr_en_i = 1'b1;
        rd_en_i = 1'b0;
        wdata_i = 8'hB1; step();
        wdata_i = 8'hB2; step();
        wr_en_i = 1'b0;

        // Now simultaneous write+read (2 items in FIFO)
        wr_en_i = 1'b1;
        rd_en_i = 1'b1;
        wdata_i = 8'hC1;
        step();
        expect_data(8'hB1);
        wdata_i = 8'hC2;
        step();
        expect_data(8'hB2);
        wr_en_i = 1'b0;
        rd_en_i = 1'b0;

        step();

        if (!overflow_o) fail("overflow should have been captured");
        if (!underflow_o) fail("underflow should have been captured");

        $display("PASS sync fifo");
        $finish;
    end

endmodule
