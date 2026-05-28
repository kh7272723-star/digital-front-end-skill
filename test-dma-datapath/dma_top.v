`default_nettype none

// Top-level wrapper: DMA engine + source memory + destination memory.
module dma_top #(
    parameter ADDR_W = 8,
    parameter DATA_W = 32
)(
    input  wire               clk_i,
    input  wire               rst_i,
    // Config interface
    input  wire               cfg_wr_en_i,
    input  wire [3:0]         cfg_addr_i,
    input  wire [DATA_W-1:0]  cfg_wdata_i,
    output wire [DATA_W-1:0]  cfg_rdata_o
);

    // Internal wires
    wire                src_rd_en;
    wire [ADDR_W-1:0]   src_rd_addr;
    wire [DATA_W-1:0]   src_rd_data;
    wire                dst_wr_en;
    wire [ADDR_W-1:0]   dst_wr_addr;
    wire [DATA_W-1:0]   dst_wr_data;

    // DMA engine
    dma_engine #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_dma (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .cfg_wr_en_i(cfg_wr_en_i),
        .cfg_addr_i(cfg_addr_i),
        .cfg_wdata_i(cfg_wdata_i),
        .cfg_rdata_o(cfg_rdata_o),
        .src_rd_en_o(src_rd_en),
        .src_rd_addr_o(src_rd_addr),
        .src_rd_data_i(src_rd_data),
        .dst_wr_en_o(dst_wr_en),
        .dst_wr_addr_o(dst_wr_addr),
        .dst_wr_data_o(dst_wr_data)
    );

    // Source memory (read-only from DMA perspective)
    simple_mem #(.DATA_W(DATA_W), .ADDR_W(ADDR_W), .DEPTH(256)) u_src (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wr_en_i(1'b0),
        .wr_addr_i({ADDR_W{1'b0}}),
        .wr_data_i({DATA_W{1'b0}}),
        .rd_en_i(src_rd_en),
        .rd_addr_i(src_rd_addr),
        .rd_data_o(src_rd_data)
    );

    // Destination memory (write-only from DMA perspective)
    simple_mem #(.DATA_W(DATA_W), .ADDR_W(ADDR_W), .DEPTH(256)) u_dst (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .wr_en_i(dst_wr_en),
        .wr_addr_i(dst_wr_addr),
        .wr_data_i(dst_wr_data),
        .rd_en_i(1'b0),
        .rd_addr_i({ADDR_W{1'b0}}),
        .rd_data_o()
    );

endmodule
`default_nettype wire
