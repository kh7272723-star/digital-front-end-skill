`default_nettype none

module fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 16
) (
    input  wire             clk_i,
    input  wire             rst_ni,
    input  wire             wr_en_i,
    input  wire [WIDTH-1:0] wr_data_i,
    input  wire             rd_en_i,
    output wire [WIDTH-1:0] rd_data_o,
    output wire             empty_o,
    output wire             full_o
);

    assign rd_data_o = {WIDTH{1'b0}};
    assign empty_o = 1'b1;
    assign full_o = 1'b0;

endmodule
