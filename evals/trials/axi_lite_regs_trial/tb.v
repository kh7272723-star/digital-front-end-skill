`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;

    reg awvalid_i;
    wire awready_o;
    reg [3:0] awaddr_i;

    reg wvalid_i;
    wire wready_o;
    reg [31:0] wdata_i;
    reg [3:0] wstrb_i;

    wire bvalid_o;
    reg bready_i;
    wire [1:0] bresp_o;

    reg arvalid_i;
    wire arready_o;
    reg [3:0] araddr_i;

    wire rvalid_o;
    reg rready_i;
    wire [31:0] rdata_o;
    wire [1:0] rresp_o;

    wire [31:0] reg0_o;
    wire [31:0] reg1_o;

    integer cycle_count;

    axi_lite_regs dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .awvalid_i(awvalid_i),
        .awready_o(awready_o),
        .awaddr_i(awaddr_i),
        .wvalid_i(wvalid_i),
        .wready_o(wready_o),
        .wdata_i(wdata_i),
        .wstrb_i(wstrb_i),
        .bvalid_o(bvalid_o),
        .bready_i(bready_i),
        .bresp_o(bresp_o),
        .arvalid_i(arvalid_i),
        .arready_o(arready_o),
        .araddr_i(araddr_i),
        .rvalid_o(rvalid_o),
        .rready_i(rready_i),
        .rdata_o(rdata_o),
        .rresp_o(rresp_o),
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

    task expect_b;
        input [1:0] expected_resp;
        begin
            if (bvalid_o !== 1'b1) begin
                fail("expected bvalid_o");
            end
            if (bresp_o !== expected_resp) begin
                fail("unexpected bresp_o");
            end
        end
    endtask

    task consume_b;
        input [1:0] expected_resp;
        begin
            expect_b(expected_resp);
            bready_i = 1'b1;
            step();
            bready_i = 1'b0;
            if (bvalid_o !== 1'b0) begin
                fail("bvalid_o should clear after response acceptance");
            end
        end
    endtask

    task read_reg;
        input [3:0] addr;
        input [31:0] expected_data;
        input [1:0] expected_resp;
        begin
            araddr_i = addr;
            arvalid_i = 1'b1;
            rready_i = 1'b0;
            if (arready_o !== 1'b1) begin
                fail("expected arready_o before read address");
            end
            step();
            arvalid_i = 1'b0;
            if (rvalid_o !== 1'b1) begin
                fail("expected rvalid_o after read address");
            end
            if (rdata_o !== expected_data) begin
                fail("unexpected rdata_o");
            end
            if (rresp_o !== expected_resp) begin
                fail("unexpected rresp_o");
            end

            step();
            if (rvalid_o !== 1'b1 || rdata_o !== expected_data || rresp_o !== expected_resp) begin
                fail("read response changed while rready_i low");
            end

            rready_i = 1'b1;
            step();
            rready_i = 1'b0;
            if (rvalid_o !== 1'b0) begin
                fail("rvalid_o should clear after read response acceptance");
            end
        end
    endtask

    initial begin
        cycle_count = 0;
        rst_i = 1'b1;
        awvalid_i = 1'b0;
        awaddr_i = 4'h0;
        wvalid_i = 1'b0;
        wdata_i = 32'h0000_0000;
        wstrb_i = 4'b0000;
        bready_i = 1'b0;
        arvalid_i = 1'b0;
        araddr_i = 4'h0;
        rready_i = 1'b0;

        repeat (2) step();
        rst_i = 1'b0;
        step();
        if (bvalid_o !== 1'b0 || rvalid_o !== 1'b0) begin
            fail("responses should be low after reset");
        end
        if (reg0_o !== 32'h0000_0000 || reg1_o !== 32'h0000_0000) begin
            fail("registers should reset to zero");
        end

        awaddr_i = 4'h0;
        awvalid_i = 1'b1;
        if (awready_o !== 1'b1) begin
            fail("expected awready_o for address-first write");
        end
        step();
        awvalid_i = 1'b0;
        if (bvalid_o !== 1'b0) begin
            fail("write response should wait for write data");
        end

        wdata_i = 32'h1122_3344;
        wstrb_i = 4'b1111;
        wvalid_i = 1'b1;
        if (wready_o !== 1'b1) begin
            fail("expected wready_o after stored address");
        end
        step();
        wvalid_i = 1'b0;
        expect_b(2'b00);
        if (reg0_o !== 32'h1122_3344) begin
            fail("reg0 write failed");
        end

        step();
        if (bvalid_o !== 1'b1 || bresp_o !== 2'b00) begin
            fail("write response changed while bready_i low");
        end
        consume_b(2'b00);
        read_reg(4'h0, 32'h1122_3344, 2'b00);

        wdata_i = 32'h5566_7788;
        wstrb_i = 4'b1111;
        wvalid_i = 1'b1;
        if (wready_o !== 1'b1) begin
            fail("expected wready_o for data-first write");
        end
        step();
        wvalid_i = 1'b0;
        if (bvalid_o !== 1'b0) begin
            fail("write response should wait for write address");
        end

        awaddr_i = 4'h4;
        awvalid_i = 1'b1;
        if (awready_o !== 1'b1) begin
            fail("expected awready_o after stored write data");
        end
        step();
        awvalid_i = 1'b0;
        expect_b(2'b00);
        if (reg1_o !== 32'h5566_7788) begin
            fail("reg1 write failed");
        end
        consume_b(2'b00);

        awaddr_i = 4'h0;
        awvalid_i = 1'b1;
        wdata_i = 32'h0000_aa00;
        wstrb_i = 4'b0010;
        wvalid_i = 1'b1;
        step();
        awvalid_i = 1'b0;
        wvalid_i = 1'b0;
        expect_b(2'b00);
        if (reg0_o !== 32'h1122_aa44) begin
            fail("byte strobe update failed");
        end
        consume_b(2'b00);
        read_reg(4'h0, 32'h1122_aa44, 2'b00);

        awaddr_i = 4'hc;
        awvalid_i = 1'b1;
        wdata_i = 32'hffff_ffff;
        wstrb_i = 4'b1111;
        wvalid_i = 1'b1;
        step();
        awvalid_i = 1'b0;
        wvalid_i = 1'b0;
        expect_b(2'b10);
        if (reg0_o !== 32'h1122_aa44 || reg1_o !== 32'h5566_7788) begin
            fail("invalid write should not update registers");
        end
        consume_b(2'b10);

        read_reg(4'hc, 32'h0000_0000, 2'b10);

        $display("PASS axi lite regs");
        $finish;
    end
endmodule
