// Integration TB: instantiates dma_top with parameterized instantiation.
// pre_integration_gate should detect this as integration TB.
`default_nettype none
`timescale 1ns/1ps

module tb_dma_top;

    reg clk_i;
    reg rst_ni;
    reg start_i;
    wire done_o;

    // Parameterized instantiation pattern: module #(...) inst (...)
    dma_top #(
        .DATA_WIDTH(32)
    ) inst_dut (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),
        .start_i(start_i),
        .done_o (done_o)
    );

    initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i;
    end

    initial begin
        rst_ni = 0;
        start_i = 0;
        #20 rst_ni = 1;
        #10 start_i = 1;
        #10 start_i = 0;
        #50 $display("ALL_TESTS_PASS");
        $display("SIMULATION_DONE");
        $finish;
    end

endmodule
