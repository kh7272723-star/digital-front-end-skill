`default_nettype none

module pipeline_stage #(
    parameter WIDTH = 8
) (
    input  wire             clk_i,
    input  wire             rst_ni,
    input  wire             valid_i,
    input  wire [WIDTH-1:0] data_i,
    output wire             ready_o,
    output wire             valid_o,
    output wire [WIDTH-1:0] data_o
);

    assign ready_o = 1'b1;
    assign valid_o = valid_i;
    assign data_o = data_i;

endmodule
