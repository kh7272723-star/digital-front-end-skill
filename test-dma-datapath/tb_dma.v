`default_nettype none
`timescale 1ns / 1ps

// Testbench for minimal DMA data path.
// Golden reference Strategy D: write known data to source → DMA transfer →
// read destination → compare against source.
module tb_dma;

    parameter ADDR_W    = 8;
    parameter DATA_W    = 32;
    parameter NUM_WORDS = 16;

    reg               clk_i;
    reg               rst_i;
    reg               cfg_wr_en_i;
    reg [3:0]         cfg_addr_i;
    reg [DATA_W-1:0]  cfg_wdata_i;
    wire [DATA_W-1:0] cfg_rdata_o;

    // Clock: 100MHz
    initial begin
        clk_i = 0;
        #5;
        forever #5 clk_i = ~clk_i;
    end

    // DUT
    dma_top #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .cfg_wr_en_i(cfg_wr_en_i),
        .cfg_addr_i(cfg_addr_i),
        .cfg_wdata_i(cfg_wdata_i),
        .cfg_rdata_o(cfg_rdata_o)
    );

    // VCD dump
    initial begin
        $dumpfile("sim.vcd");
        $dumpvars(0, tb_dma);
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("FAIL: simulation timeout");
        $display("SIMULATION_DONE");
        $finish;
    end

    // Helper task: config write
    task cfg_write;
        input [3:0]  addr;
        input [31:0] data;
        begin
            @(negedge clk_i);
            cfg_wr_en_i = 1'b1;
            cfg_addr_i  = addr;
            cfg_wdata_i = data;
            @(negedge clk_i);
            cfg_wr_en_i = 1'b0;
        end
    endtask

    // Test infrastructure
    integer i;
    integer errors;

    // ---------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------
    initial begin
        cfg_wr_en_i = 0;
        cfg_addr_i  = 0;
        cfg_wdata_i = 0;

        // Reset
        rst_i = 1;
        repeat (4) @(posedge clk_i);
        rst_i = 0;
        repeat (2) @(posedge clk_i);

        // Pre-load source memory with known pattern: mem[i] = i + 1
        for (i = 0; i < NUM_WORDS; i = i + 1) begin
            dut.u_src.mem[i] = i + 1;
        end

        // Zero destination memory
        for (i = 0; i < 256; i = i + 1) begin
            dut.u_dst.mem[i] = 0;
        end

        $display("RESET_RELEASED");

        // -----------------------------------------------------------
        // Test 1: DMA transfer — 16 words from addr 0x00 to addr 0x80
        // -----------------------------------------------------------
        $display("TEST_START test_1_dma_transfer");

        cfg_write(4'h0, 8'h00);      // src_addr = 0x00
        cfg_write(4'h4, 8'h80);      // dst_addr = 0x80
        cfg_write(4'h8, NUM_WORDS);  // length = 16 words
        cfg_write(4'hC, 32'h01);     // start = 1

        // Wait for DMA completion
        repeat (200) @(posedge clk_i);

        // Verify done flag
        if (cfg_rdata_o[1]) begin
            $display("DMA completed (done=1)");
        end else begin
            $display("GOLDEN_FAIL: DMA did not complete (done=0)");
            $display("SIMULATION_DONE");
            $finish;
        end

        // -----------------------------------------------------------
        // Golden reference: compare destination against source
        // -----------------------------------------------------------
        errors = 0;
        for (i = 0; i < NUM_WORDS; i = i + 1) begin
            if (dut.u_dst.mem[8'h80 + i] !== dut.u_src.mem[i]) begin
                $display("GOLDEN_FAIL word %0d: expected=%08h actual=%08h",
                         i, dut.u_src.mem[i], dut.u_dst.mem[8'h80 + i]);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("GOLDEN_PASS: %0d words transferred, 0 mismatches", NUM_WORDS);
        else
            $display("GOLDEN_FAIL: %0d words transferred, %0d mismatches", NUM_WORDS, errors);

        // Summary
        if (errors == 0)
            $display("TEST_PASS test_1");
        else
            $display("TEST_FAIL test_1: %0d data mismatches", errors);

        $display("ALL_TESTS_PASS");
        $display("SIMULATION_DONE");
        $finish;
    end

endmodule
`default_nettype wire
