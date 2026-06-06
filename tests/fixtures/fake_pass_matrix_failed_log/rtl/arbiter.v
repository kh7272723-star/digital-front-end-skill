`default_nettype none

module arbiter #(
    parameter N = 4
) (
    input  wire             clk_i,
    input  wire             rst_ni,
    input  wire [N-1:0]     req_i,
    output wire [N-1:0]     gnt_o
);

    assign gnt_o = req_i;

endmodule
