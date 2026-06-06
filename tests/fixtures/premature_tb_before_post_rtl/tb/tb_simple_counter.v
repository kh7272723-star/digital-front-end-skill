// TB: This file should NOT exist before post-rtl PASS.
// The post-rtl gate should flag this as premature TB generation.
`default_nettype none
`timescale 1ns/1ps

module tb_simple_counter;

    reg clk_i;
    reg rst_ni;
    reg inc_i;
    reg clr_i;
    wire [7:0] count_o;

    simple_counter u_dut (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),
        .inc_i  (inc_i),
        .clr_i  (clr_i),
        .count_o(count_o)
    );

    initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i;
    end

    initial begin
        rst_ni = 0;
        inc_i  = 0;
        clr_i  = 0;
        #20 rst_ni = 1;
        #10 inc_i = 1;
        #10 inc_i = 0;
        #10 $display("count=%d", count_o);
        $finish;
    end

endmodule
