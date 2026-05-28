`default_nettype none
`timescale 1ns / 1ps

// Testbench for DMA subsystem.
// Golden reference Strategy D: source data → DMA → destination → compare.
module tb_dma_subsystem;

    parameter ADDR_W = 32;
    parameter DATA_W = 32;
    parameter NUM_WORDS = 16;

    reg               clk_i;
    reg               rst_i;
    reg               cfg_wr_en_i;
    reg [3:0]         cfg_addr_i;
    reg [DATA_W-1:0]  cfg_wdata_i;
    wire [DATA_W-1:0] cfg_rdata_o;

    // AXI wires
    wire               arvalid, arready;
    wire [ADDR_W-1:0]  araddr;
    wire [7:0]         arlen;
    wire               awvalid, awready;
    wire [ADDR_W-1:0]  awaddr;
    wire [7:0]         awlen;
    wire               wvalid, wready;
    wire [DATA_W-1:0]  wdata;
    wire               wlast;
    wire [3:0]         wstrb;
    wire               rvalid, rready;
    wire [DATA_W-1:0]  rdata;
    wire               rlast;
    wire [1:0]         rresp;
    wire               bvalid, bready;
    wire [1:0]         bresp;
    wire               irq;

    // Clock: 100MHz
    initial begin
        clk_i = 0;
        #5;
        forever #5 clk_i = ~clk_i;
    end

    // DUT
    dma_top #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .FIFO_DEPTH(16), .MAX_BURST(4)
    ) dut (
        .clk_i(clk_i), .rst_i(rst_i),
        .cfg_wr_en_i(cfg_wr_en_i), .cfg_addr_i(cfg_addr_i),
        .cfg_wdata_i(cfg_wdata_i), .cfg_rdata_o(cfg_rdata_o),
        .m_axi_arvalid_o(arvalid), .m_axi_arready_i(arready),
        .m_axi_araddr_o(araddr), .m_axi_arlen_o(arlen),
        .m_axi_awvalid_o(awvalid), .m_axi_awready_i(awready),
        .m_axi_awaddr_o(awaddr), .m_axi_awlen_o(awlen),
        .m_axi_wvalid_o(wvalid), .m_axi_wready_i(wready),
        .m_axi_wdata_o(wdata), .m_axi_wlast_o(wlast),
        .m_axi_wstrb_o(wstrb),
        .m_axi_rvalid_i(rvalid), .m_axi_rready_o(rready),
        .m_axi_rdata_i(rdata), .m_axi_rlast_i(rlast),
        .m_axi_rresp_i(rresp),
        .m_axi_bvalid_i(bvalid), .m_axi_bready_o(bready),
        .m_axi_bresp_i(bresp),
        .irq_o(irq)
    );

    // AXI memory slave
    axi_mem_slave #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .DEPTH(256)) mem (
        .clk_i(clk_i), .rst_i(rst_i),
        .arvalid_i(arvalid), .arready_o(arready),
        .araddr_i(araddr), .arlen_i(arlen),
        .rvalid_o(rvalid), .rready_i(rready),
        .rdata_o(rdata), .rlast_o(rlast), .rresp_o(rresp),
        .awvalid_i(awvalid), .awready_o(awready),
        .awaddr_i(awaddr), .awlen_i(awlen),
        .wvalid_i(wvalid), .wready_o(wready),
        .wdata_i(wdata), .wlast_i(wlast), .wstrb_i(wstrb),
        .bvalid_o(bvalid), .bready_i(bready), .bresp_o(bresp)
    );

    // VCD dump
    initial begin
        $dumpfile("sim.vcd");
        $dumpvars(0, tb_dma_subsystem);
    end

    // Timeout
    initial begin
        #100000;
        $display("FAIL: simulation timeout");
        $display("SIMULATION_DONE");
        $finish;
    end

    // Helper task
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

    integer i;
    integer errors;

    initial begin
        cfg_wr_en_i = 0;
        cfg_addr_i  = 0;
        cfg_wdata_i = 0;

        // Reset
        rst_i = 1;
        repeat (4) @(posedge clk_i);
        rst_i = 0;
        repeat (2) @(posedge clk_i);

        // Pre-load source memory (addresses 0x00-0x3F, 16 words)
        for (i = 0; i < NUM_WORDS; i = i + 1) begin
            mem.mem[i] = i + 1;
        end
        // Clear destination (addresses 0x80-0xBF)
        for (i = 0; i < NUM_WORDS; i = i + 1) begin
            mem.mem[32 + i] = 0; // addr 0x80 >> 2 = 32
        end

        $display("RESET_RELEASED");

        // Configure and start DMA
        $display("TEST_START test_1_dma_transfer");
        cfg_write(4'h0, 32'h00000000); // src_addr = 0x00
        cfg_write(4'h4, 32'h00000080); // dst_addr = 0x80
        cfg_write(4'h8, NUM_WORDS * 4); // byte_count = 64
        cfg_write(4'hC, 32'h00000001); // start

        // Wait for completion with debug
        repeat (30) begin
            @(posedge clk_i); #1;
            $display("  t=%0d: pl=%0d rem=%0d ar_v=%0b ar_r=%0b aw_v=%0b aw_r=%0b w_v=%0b w_r=%0b r_v=%0b r_r=%0b fw=%0b fe=%0b b_v=%0b b_r=%0b comp=%0b",
                     $time/10, dut.u_planner.state_q, dut.u_planner.beats_rem_q,
                     dut.m_axi_arvalid_o, dut.m_axi_arready_i,
                     dut.m_axi_awvalid_o, dut.m_axi_awready_i,
                     dut.m_axi_wvalid_o, dut.m_axi_wready_i,
                     dut.m_axi_rvalid_i, dut.m_axi_rready_o,
                     dut.fifo_wr_en, dut.fifo_empty,
                     dut.m_axi_bvalid_i, dut.m_axi_bready_o,
                     dut.u_comp.active_q);
        end
        repeat (470) @(posedge clk_i);

        // Check done status
        cfg_wr_en_i = 0;
        @(posedge clk_i); #1;
        if (cfg_rdata_o[1]) // done bit
            $display("DMA completed (done=1)");
        else begin
            $display("GOLDEN_FAIL: DMA did not complete (status=%08h)", cfg_rdata_o);
            $display("SIMULATION_DONE");
            $finish;
        end

        // Golden reference: compare destination against source
        errors = 0;
        for (i = 0; i < NUM_WORDS; i = i + 1) begin
            if (mem.mem[32 + i] !== mem.mem[i]) begin
                $display("GOLDEN_FAIL word %0d: expected=%08h actual=%08h",
                         i, mem.mem[i], mem.mem[32 + i]);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("GOLDEN_PASS: %0d words transferred, 0 mismatches", NUM_WORDS);
        else
            $display("GOLDEN_FAIL: %0d words, %0d mismatches", NUM_WORDS, errors);

        if (errors == 0)
            $display("TEST_PASS test_1");
        else
            $display("TEST_FAIL test_1");

        $display("ALL_TESTS_PASS");
        $display("SIMULATION_DONE");
        $finish;
    end

endmodule
`default_nettype wire
