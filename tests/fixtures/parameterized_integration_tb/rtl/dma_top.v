`default_nettype none

module dma_top #(
    parameter DATA_WIDTH = 32
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        start_i,
    output wire        done_o
);

    wire rd_done;
    wire wr_done;

    dma_rd_engine inst_rd (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),
        .start_i(start_i),
        .done_o (rd_done)
    );

    dma_wr_engine inst_wr (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),
        .start_i(start_i),
        .done_o (wr_done)
    );

    assign done_o = rd_done && wr_done;

endmodule
