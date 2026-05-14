`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;
    reg wait_i;
    reg hsel_i;
    reg hready_i;
    reg [1:0] htrans_i;
    reg hwrite_i;
    reg [2:0] hsize_i;
    reg [3:0] haddr_i;
    reg [31:0] hwdata_i;
    wire hready_o;
    wire hresp_o;
    wire [31:0] hrdata_o;
    wire [31:0] reg0_o;
    wire [31:0] reg1_o;

    integer cycle_count;

    ahb_lite_regs dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wait_i(wait_i),
        .hsel_i(hsel_i),
        .hready_i(hready_i),
        .htrans_i(htrans_i),
        .hwrite_i(hwrite_i),
        .hsize_i(hsize_i),
        .haddr_i(haddr_i),
        .hwdata_i(hwdata_i),
        .hready_o(hready_o),
        .hresp_o(hresp_o),
        .hrdata_o(hrdata_o),
        .reg0_o(reg0_o),
        .reg1_o(reg1_o)
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

    task idle_bus;
        begin
            wait_i = 1'b0;
            hsel_i = 1'b0;
            hready_i = 1'b1;
            htrans_i = 2'b00;
            hwrite_i = 1'b0;
            hsize_i = 3'b010;
            haddr_i = 4'h0;
            hwdata_i = 32'h0000_0000;
        end
    endtask

    task ahb_write;
        input [3:0] addr;
        input [31:0] data;
        input [2:0] size;
        input insert_wait;
        input expect_error;
        begin
            wait_i = insert_wait;
            hsel_i = 1'b1;
            hready_i = 1'b1;
            htrans_i = 2'b10;
            hwrite_i = 1'b1;
            hsize_i = size;
            haddr_i = addr;
            step();

            hsel_i = 1'b0;
            htrans_i = 2'b00;
            hwrite_i = 1'b0;
            hwdata_i = data;

            if (insert_wait) begin
                #1;
                if (hready_o !== 1'b0) begin
                    fail("hready_o should be low during inserted wait state");
                end
                step();
            end

            #1;
            if (hready_o !== 1'b1) begin
                fail("hready_o should be high for data completion");
            end
            if (hresp_o !== expect_error) begin
                fail("unexpected hresp_o on write");
            end
            step();
            idle_bus();
        end
    endtask

    task ahb_read;
        input [3:0] addr;
        input [31:0] expected_data;
        input expect_error;
        input insert_wait;
        begin
            wait_i = insert_wait;
            hsel_i = 1'b1;
            hready_i = 1'b1;
            htrans_i = 2'b10;
            hwrite_i = 1'b0;
            hsize_i = 3'b010;
            haddr_i = addr;
            step();

            hsel_i = 1'b0;
            htrans_i = 2'b00;

            if (insert_wait) begin
                #1;
                if (hready_o !== 1'b0) begin
                    fail("hready_o should be low during read wait state");
                end
                if (hrdata_o !== expected_data) begin
                    fail("read data changed during wait state");
                end
                step();
            end

            #1;
            if (hready_o !== 1'b1) begin
                fail("hready_o should be high for read completion");
            end
            if (hrdata_o !== expected_data) begin
                fail("unexpected hrdata_o");
            end
            if (hresp_o !== expect_error) begin
                fail("unexpected hresp_o on read");
            end
            step();
            idle_bus();
        end
    endtask

    initial begin
        cycle_count = 0;
        rst_i = 1'b1;
        idle_bus();
        repeat (2) step();
        rst_i = 1'b0;
        step();
        if (hready_o !== 1'b1 || reg0_o !== 32'h0000_0000 || reg1_o !== 32'h0000_0000) begin
            fail("bad reset release state");
        end

        hsel_i = 1'b1;
        hready_i = 1'b1;
        htrans_i = 2'b10;
        hwrite_i = 1'b1;
        hsize_i = 3'b010;
        haddr_i = 4'h0;
        wait_i = 1'b0;
        step();

        haddr_i = 4'h4;
        hsel_i = 1'b1;
        htrans_i = 2'b10;
        hwrite_i = 1'b1;
        hwdata_i = 32'haaaa_0001;
        step();
        if (reg0_o !== 32'haaaa_0001 || reg1_o !== 32'h0000_0000) begin
            fail("write used current address instead of previous address phase");
        end
        idle_bus();

        ahb_write(4'h4, 32'hbbbb_0002, 3'b010, 1'b1, 1'b0);
        if (reg1_o !== 32'hbbbb_0002) begin
            fail("waited write to reg1 failed");
        end

        ahb_read(4'h0, 32'haaaa_0001, 1'b0, 1'b1);
        ahb_read(4'h4, 32'hbbbb_0002, 1'b0, 1'b0);

        ahb_write(4'hc, 32'hffff_ffff, 3'b010, 1'b0, 1'b1);
        if (reg0_o !== 32'haaaa_0001 || reg1_o !== 32'hbbbb_0002) begin
            fail("invalid address write changed state");
        end
        ahb_read(4'hc, 32'h0000_0000, 1'b1, 1'b0);

        ahb_write(4'h0, 32'hcccc_0003, 3'b001, 1'b0, 1'b1);
        if (reg0_o !== 32'haaaa_0001) begin
            fail("unsupported size write changed state");
        end

        $display("PASS ahb lite regs");
        $finish;
    end
endmodule
