`default_nettype none

// DMA subsystem top-level integration.
// Connects: cfg_slave → burst_planner → ar/aw channels → data_fifo →
//           rd/wr data channels → bresp_channel → completion_tracker
module dma_top #(
    parameter ADDR_W    = 32,
    parameter DATA_W    = 32,
    parameter LEN_W     = 8,
    parameter COUNT_W   = 16,
    parameter FIFO_DEPTH = 16,
    parameter MAX_BURST  = 4,
    parameter BYTES_PER_BEAT = 4
)(
    input  wire               clk_i,
    input  wire               rst_i,
    // Config interface
    input  wire               cfg_wr_en_i,
    input  wire [3:0]         cfg_addr_i,
    input  wire [DATA_W-1:0]  cfg_wdata_i,
    output wire [DATA_W-1:0]  cfg_rdata_o,
    // AXI Master
    output wire               m_axi_arvalid_o,
    input  wire               m_axi_arready_i,
    output wire [ADDR_W-1:0]  m_axi_araddr_o,
    output wire [7:0]         m_axi_arlen_o,
    output wire               m_axi_awvalid_o,
    input  wire               m_axi_awready_i,
    output wire [ADDR_W-1:0]  m_axi_awaddr_o,
    output wire [7:0]         m_axi_awlen_o,
    output wire               m_axi_wvalid_o,
    input  wire               m_axi_wready_i,
    output wire [DATA_W-1:0]  m_axi_wdata_o,
    output wire               m_axi_wlast_o,
    output wire [DATA_W/8-1:0] m_axi_wstrb_o,
    input  wire               m_axi_rvalid_i,
    output wire               m_axi_rready_o,
    input  wire [DATA_W-1:0]  m_axi_rdata_i,
    input  wire               m_axi_rlast_i,
    input  wire [1:0]         m_axi_rresp_i,
    input  wire               m_axi_bvalid_i,
    output wire               m_axi_bready_o,
    input  wire [1:0]         m_axi_bresp_i,
    // Interrupt
    output wire               irq_o
);

    // Internal wires
    wire [ADDR_W-1:0]  src_addr, dst_addr;
    wire [COUNT_W-1:0] byte_count;
    wire               start_pulse;
    wire               busy, done, error;

    // Burst planner outputs
    wire               rd_cmd_valid, rd_cmd_ready;
    wire [ADDR_W-1:0]  rd_cmd_addr;
    wire [LEN_W-1:0]   rd_cmd_len;
    wire               wr_cmd_valid, wr_cmd_ready;
    wire [ADDR_W-1:0]  wr_cmd_addr;
    wire [LEN_W-1:0]   wr_cmd_len;
    wire               planner_done_valid, planner_done_ready;
    wire               planner_error;
    wire [COUNT_W-1:0] planner_b_count;
    wire               planner_busy;

    // Data FIFO wires
    wire               fifo_wr_en, fifo_rd_en;
    wire [DATA_W:0]    fifo_wr_data, fifo_rd_data;
    wire               fifo_full, fifo_empty;

    // AXI R data channel
    wire               rd_error;

    // WLAST accepted pulse
    wire               wlast_accepted;

    // B channel wires (connect to completion tracker)
    wire               comp_done_valid, comp_done_ready;
    wire               comp_error, comp_busy;

    // ================================================================
    // Config slave
    // ================================================================
    dma_cfg_slave #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .COUNT_W(COUNT_W)) u_cfg (
        .clk_i(clk_i), .rst_i(rst_i),
        .cfg_wr_en_i(cfg_wr_en_i), .cfg_addr_i(cfg_addr_i),
        .cfg_wdata_i(cfg_wdata_i), .cfg_rdata_o(cfg_rdata_o),
        .src_addr_o(src_addr), .dst_addr_o(dst_addr),
        .byte_count_o(byte_count), .start_o(start_pulse),
        .busy_i(planner_busy), .done_i(comp_done_valid), .error_i(comp_error)
    );

    // ================================================================
    // Burst planner
    // ================================================================
    burst_planner #(
        .ADDR_W(ADDR_W), .LEN_W(LEN_W), .COUNT_W(COUNT_W),
        .MAX_BURST(MAX_BURST), .BYTES_PER_BEAT(BYTES_PER_BEAT)
    ) u_planner (
        .clk_i(clk_i), .rst_i(rst_i),
        .desc_valid_i(start_pulse), .desc_ready_o(),
        .desc_src_addr_i(src_addr), .desc_dst_addr_i(dst_addr),
        .desc_byte_count_i(byte_count),
        .rd_cmd_valid_o(rd_cmd_valid), .rd_cmd_ready_i(rd_cmd_ready),
        .rd_cmd_addr_o(rd_cmd_addr), .rd_cmd_len_o(rd_cmd_len),
        .wr_cmd_valid_o(wr_cmd_valid), .wr_cmd_ready_i(wr_cmd_ready),
        .wr_cmd_addr_o(wr_cmd_addr), .wr_cmd_len_o(wr_cmd_len),
        .done_valid_o(planner_done_valid), .done_ready_i(planner_done_ready),
        .error_o(planner_error), .b_count_o(planner_b_count),
        .busy_o(planner_busy)
    );

    // Planner done → not used directly (completion tracker handles done)
    assign planner_done_ready = 1'b1;

    // ================================================================
    // Address channels
    // ================================================================
    ar_channel #(.ADDR_W(ADDR_W), .LEN_W(LEN_W)) u_ar (
        .clk_i(clk_i), .rst_i(rst_i),
        .cmd_valid_i(rd_cmd_valid), .cmd_ready_o(rd_cmd_ready),
        .cmd_addr_i(rd_cmd_addr), .cmd_len_i(rd_cmd_len),
        .arvalid_o(m_axi_arvalid_o), .arready_i(m_axi_arready_i),
        .araddr_o(m_axi_araddr_o), .arlen_o(m_axi_arlen_o)
    );

    aw_channel #(.ADDR_W(ADDR_W), .LEN_W(LEN_W)) u_aw (
        .clk_i(clk_i), .rst_i(rst_i),
        .cmd_valid_i(wr_cmd_valid), .cmd_ready_o(wr_cmd_ready),
        .cmd_addr_i(wr_cmd_addr), .cmd_len_i(wr_cmd_len),
        .awvalid_o(m_axi_awvalid_o), .awready_i(m_axi_awready_i),
        .awaddr_o(m_axi_awaddr_o), .awlen_o(m_axi_awlen_o)
    );

    // ================================================================
    // Data FIFO (between read and write paths)
    // ================================================================
    data_fifo #(.DATA_W(DATA_W), .DEPTH(FIFO_DEPTH)) u_fifo (
        .clk_i(clk_i), .rst_i(rst_i),
        .wr_en_i(fifo_wr_en), .wr_data_i(fifo_wr_data), .full_o(fifo_full),
        .rd_en_i(fifo_rd_en), .rd_data_o(fifo_rd_data), .empty_o(fifo_empty)
    );

    // ================================================================
    // Read data channel (AXI R → FIFO)
    // ================================================================
    rd_data_channel #(.DATA_W(DATA_W)) u_rd_data (
        .rvalid_i(m_axi_rvalid_i), .rready_o(m_axi_rready_o),
        .rdata_i(m_axi_rdata_i), .rlast_i(m_axi_rlast_i),
        .rresp_i(m_axi_rresp_i),
        .fifo_wr_en_o(fifo_wr_en), .fifo_wr_data_o(fifo_wr_data),
        .fifo_full_i(fifo_full),
        .clk_i(clk_i), .rst_i(rst_i),
        .error_o(rd_error)
    );

    // ================================================================
    // Write data channel (FIFO → AXI W)
    // ================================================================
    wr_data_channel #(.DATA_W(DATA_W)) u_wr_data (
        .clk_i(clk_i), .rst_i(rst_i),
        .fifo_rd_en_o(fifo_rd_en), .fifo_rd_data_i(fifo_rd_data),
        .fifo_empty_i(fifo_empty),
        .wvalid_o(m_axi_wvalid_o), .wready_i(m_axi_wready_i),
        .wdata_o(m_axi_wdata_o), .wlast_o(m_axi_wlast_o),
        .wstrb_o(m_axi_wstrb_o),
        .wlast_accepted_o(wlast_accepted)
    );

    // ================================================================
    // B response channel → completion tracker
    // ================================================================
    completion_tracker #(.COUNT_W(COUNT_W)) u_comp (
        .clk_i(clk_i), .rst_i(rst_i),
        .desc_valid_i(start_pulse), .b_count_i(planner_b_count),
        .wlast_accepted_i(wlast_accepted),
        .bvalid_i(m_axi_bvalid_i), .bready_o(m_axi_bready_o),
        .bresp_i(m_axi_bresp_i),
        .done_valid_o(comp_done_valid), .done_ready_i(1'b1),
        .error_o(comp_error), .busy_o(comp_busy)
    );

    // Interrupt on completion
    assign irq_o = comp_done_valid;

endmodule
`default_nettype wire
