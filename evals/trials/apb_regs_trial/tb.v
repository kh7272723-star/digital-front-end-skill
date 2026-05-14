`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;
    reg wait_i;
    reg psel_i;
    reg penable_i;
    reg pwrite_i;
    reg [3:0] paddr_i;
    reg [31:0] pwdata_i;
    reg [3:0] pstrb_i;
    wire pready_o;
    wire [31:0] prdata_o;
    wire pslverr_o;
    wire [31:0] reg0_o;
    wire [31:0] reg1_o;

    integer cycle_count;

    apb_regs dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wait_i(wait_i),
        .psel_i(psel_i),
        .penable_i(penable_i),
        .pwrite_i(pwrite_i),
        .paddr_i(paddr_i),
        .pwdata_i(pwdata_i),
        .pstrb_i(pstrb_i),
        .pready_o(pready_o),
        .prdata_o(prdata_o),
        .pslverr_o(pslverr_o),
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
            psel_i = 1'b0;
            penable_i = 1'b0;
            pwrite_i = 1'b0;
            paddr_i = 4'h0;
            pwdata_i = 32'h0000_0000;
            pstrb_i = 4'b0000;
            wait_i = 1'b0;
        end
    endtask

    task apb_write;
        input [3:0] addr;
        input [31:0] data;
        input [3:0] strb;
        input insert_wait;
        input expect_error;
        begin
            paddr_i = addr;
            pwdata_i = data;
            pstrb_i = strb;
            pwrite_i = 1'b1;
            psel_i = 1'b1;
            penable_i = 1'b0;
            wait_i = 1'b0;
            step();
            if (reg0_o !== reg0_o || reg1_o !== reg1_o) begin
                fail("unreachable x check");
            end

            penable_i = 1'b1;
            if (insert_wait) begin
                wait_i = 1'b1;
                #1;
                if (pready_o !== 1'b0) begin
                    fail("pready_o should be low during wait state");
                end
                step();
                wait_i = 1'b0;
            end

            #1;
            if (pready_o !== 1'b1) begin
                fail("pready_o should be high for completed access");
            end
            if (pslverr_o !== expect_error) begin
                fail("unexpected pslverr_o on write");
            end
            step();
            idle_bus();
            step();
        end
    endtask

    task apb_read;
        input [3:0] addr;
        input [31:0] expected_data;
        input expect_error;
        input insert_wait;
        begin
            paddr_i = addr;
            pwrite_i = 1'b0;
            psel_i = 1'b1;
            penable_i = 1'b0;
            wait_i = 1'b0;
            step();

            penable_i = 1'b1;
            if (insert_wait) begin
                wait_i = 1'b1;
                #1;
                if (pready_o !== 1'b0) begin
                    fail("pready_o should be low during read wait state");
                end
                step();
                wait_i = 1'b0;
            end

            #1;
            if (pready_o !== 1'b1) begin
                fail("pready_o should be high for read access");
            end
            if (prdata_o !== expected_data) begin
                fail("unexpected prdata_o");
            end
            if (pslverr_o !== expect_error) begin
                fail("unexpected pslverr_o on read");
            end
            step();
            idle_bus();
            step();
        end
    endtask

    initial begin
        cycle_count = 0;
        rst_i = 1'b1;
        idle_bus();
        repeat (2) step();
        rst_i = 1'b0;
        step();
        if (reg0_o !== 32'h0000_0000 || reg1_o !== 32'h0000_0000) begin
            fail("registers did not reset");
        end

        paddr_i = 4'h0;
        pwdata_i = 32'h1111_2222;
        pstrb_i = 4'b1111;
        pwrite_i = 1'b1;
        psel_i = 1'b1;
        penable_i = 1'b0;
        step();
        if (reg0_o !== 32'h0000_0000) begin
            fail("setup phase must not update register");
        end
        idle_bus();
        step();

        apb_write(4'h0, 32'h1122_3344, 4'b1111, 1'b1, 1'b0);
        if (reg0_o !== 32'h1122_3344) begin
            fail("full write to reg0 failed");
        end
        apb_read(4'h0, 32'h1122_3344, 1'b0, 1'b1);

        apb_write(4'h0, 32'h0000_aa00, 4'b0010, 1'b0, 1'b0);
        if (reg0_o !== 32'h1122_aa44) begin
            fail("partial byte write failed");
        end
        apb_read(4'h0, 32'h1122_aa44, 1'b0, 1'b0);

        apb_write(4'h4, 32'h5566_7788, 4'b1111, 1'b0, 1'b0);
        if (reg1_o !== 32'h5566_7788) begin
            fail("write to reg1 failed");
        end
        apb_read(4'h4, 32'h5566_7788, 1'b0, 1'b0);

        apb_write(4'hc, 32'hffff_ffff, 4'b1111, 1'b0, 1'b1);
        if (reg0_o !== 32'h1122_aa44 || reg1_o !== 32'h5566_7788) begin
            fail("invalid write changed state");
        end
        apb_read(4'hc, 32'h0000_0000, 1'b1, 1'b0);

        $display("PASS apb regs");
        $finish;
    end
endmodule
