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
    integer readback_pass_count;
    integer readback_fail_count;

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

    task write_reg;
        input [3:0] addr;
        input [31:0] data;
        input [3:0] strb;
        input [1:0] exp_resp;
        begin
            awaddr_i = addr;
            wdata_i = data;
            wstrb_i = strb;
            awvalid_i = 1'b1;
            wvalid_i = 1'b1;
            step();
            awvalid_i = 1'b0;
            wvalid_i = 1'b0;
            expect_b(exp_resp);
            consume_b(exp_resp);
        end
    endtask

    task read_reg_data;
        input [3:0] addr;
        output [31:0] data;
        output [1:0] resp;
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
            data = rdata_o;
            resp = rresp_o;
            // Verify R holds while rready_i is low (AXI-Lite protocol)
            step();
            if (rvalid_o !== 1'b1 || rdata_o !== data || rresp_o !== resp) begin
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

    task readback_check;
        input [3:0] addr;
        input [31:0] wr_data;
        input [3:0] strb;
        input [31:0] current_val;
        input [256*8-1:0] test_name;
        reg [31:0] actual_data;
        reg [1:0] actual_resp;
        reg [31:0] strb_mask;
        reg [31:0] expected_data;
        begin
            strb_mask = {{8{strb[3]}}, {8{strb[2]}}, {8{strb[1]}}, {8{strb[0]}}};
            expected_data = (wr_data & strb_mask) | (current_val & ~strb_mask);
            write_reg(addr, wr_data, strb, 2'b00);
            read_reg_data(addr, actual_data, actual_resp);
            if (actual_data !== expected_data || actual_resp !== 2'b00) begin
                $display("READBACK_FAIL %0s: addr=0x%0h wr=0x%08h strb=0b%04b exp=0x%08h got=0x%08h resp=0b%02b",
                         test_name, addr, wr_data, strb, expected_data, actual_data, actual_resp);
                readback_fail_count = readback_fail_count + 1;
            end else begin
                $display("READBACK_PASS %0s: addr=0x%0h data=0x%08h", test_name, addr, actual_data);
                readback_pass_count = readback_pass_count + 1;
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

        // =========================================================
        // Golden Reference Strategy C: Write-Readback Scoreboard
        // =========================================================
        readback_pass_count = 0;
        readback_fail_count = 0;

        $display("--- Golden Reference: Write-Readback Scoreboard ---");

        // Test 1: Full 32-bit write-readback to reg0
        readback_check(4'h0, 32'hDEADBEEF, 4'b1111, 32'h00000000, "full_wr_reg0");

        // Test 2: Full 32-bit write-readback to reg1
        readback_check(4'h4, 32'hCAFEBABE, 4'b1111, 32'h00000000, "full_wr_reg1");

        // Test 3: Byte-strobe partial write reg0 (strb=1010)
        // Current reg0 = 0xDEADBEEF, wr=0xA5A5A5A5, strb=1010
        // Expected: byte3=0xA5 byte2=0xAD byte1=0xA5 byte0=0xEF = 0xA5ADA5EF
        readback_check(4'h0, 32'hA5A5A5A5, 4'b1010, 32'hDEADBEEF, "strb_1010_reg0");

        // Test 4: Byte-strobe partial write reg1 (strb=0101)
        // Current reg1 = 0xCAFEBABE, wr=0x5A5A5A5A, strb=0101
        // Expected: byte3=0xCA byte2=0x5A byte1=0xBA byte0=0x5A = 0xCA5ABA5A
        readback_check(4'h4, 32'h5A5A5A5A, 4'b0101, 32'hCAFEBABE, "strb_0101_reg1");

        // Test 5: Walking ones on reg0
        begin : walking_ones_blk
            integer wi;
            reg [31:0] wi_data, wi_actual;
            reg [1:0] wi_resp;
            for (wi = 0; wi < 32; wi = wi + 1) begin
                wi_data = (32'h1 << wi);
                write_reg(4'h0, wi_data, 4'b1111, 2'b00);
                read_reg_data(4'h0, wi_actual, wi_resp);
                if (wi_actual !== wi_data || wi_resp !== 2'b00) begin
                    $display("READBACK_FAIL walking_ones[%0d]: wr=0x%08h got=0x%08h resp=0b%02b",
                             wi, wi_data, wi_actual, wi_resp);
                    readback_fail_count = readback_fail_count + 1;
                end else begin
                    readback_pass_count = readback_pass_count + 1;
                end
            end
        end

        // Test 6: Invalid address read (SLVERR, data=0x0)
        begin : invalid_read_blk
            reg [31:0] inv_data;
            reg [1:0] inv_resp;
            read_reg_data(4'hC, inv_data, inv_resp);
            if (inv_resp !== 2'b10) begin
                $display("READBACK_FAIL invalid_addr_read: resp=0b%02b expected=0b10", inv_resp);
                readback_fail_count = readback_fail_count + 1;
            end else if (inv_data !== 32'h00000000) begin
                $display("READBACK_FAIL invalid_addr_read: data=0x%08h expected=0x00000000", inv_data);
                readback_fail_count = readback_fail_count + 1;
            end else begin
                $display("READBACK_PASS invalid_addr_read: resp=SLVERR data=0x00000000");
                readback_pass_count = readback_pass_count + 1;
            end
        end

        $display("--- Readback Summary: %0d PASS, %0d FAIL ---", readback_pass_count, readback_fail_count);
        if (readback_fail_count > 0) begin
            fail("golden reference readback checks failed");
        end

        $display("PASS axi lite regs");
        $finish;
    end
endmodule
