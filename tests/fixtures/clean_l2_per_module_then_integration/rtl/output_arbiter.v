`default_nettype none

module output_arbiter (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [1:0]  req_i,
    output wire [1:0]  gnt_o
);

    assign gnt_o = req_i;

endmodule
