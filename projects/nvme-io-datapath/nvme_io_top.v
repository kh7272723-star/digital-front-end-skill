`default_nettype none
// ============================================================================
// nvme_io_top — NVMe I/O Datapath (core path only)
// ============================================================================

module nvme_io_top (
    input  wire         clk_i,
    input  wire         rst_ni,
    // Command input (from testbench — replaces sq_fetch for validation)
    input  wire         cmd_valid_i,
    output wire         cmd_ready_o,
    input  wire [7:0]   cmd_opcode_i,
    input  wire [16:0]  cmd_cid_i,
    input  wire [31:0]  cmd_nsid_i,
    input  wire [63:0]  cmd_prp1_i,
    input  wire [63:0]  cmd_prp2_i,
    input  wire [63:0]  cmd_slba_i,
    input  wire [16:0]  cmd_nlb_i,
    input  wire [7:0]   cmd_sqid_i,
    input  wire [16:0]  cmd_sq_head_i,
    // Completion output (to testbench — replaces cq_post for validation)
    output wire         cpl_valid_o,
    input  wire         cpl_ready_i,
    output wire [7:0]   cpl_sqid_o,
    output wire [16:0]  cpl_sqhd_o,
    output wire [16:0]  cpl_cid_o,
    output wire [16:0]  cpl_status_o,
    // NVM SRAM
    output wire [63:0]  nvm_addr_o,
    output wire         nvm_rd_en_o,
    input  wire [63:0]  nvm_rdata_i,
    input  wire         nvm_rvalid_i,
    // AXI master (read engine only — data write to host)
    output wire         m_axi_aw_valid, input  wire m_axi_aw_ready,
    output wire [63:0]  m_axi_aw_addr,  output wire [7:0] m_axi_aw_len,
    output wire         m_axi_w_valid,  input  wire m_axi_w_ready,
    output wire [63:0]  m_axi_w_data,   output wire [7:0] m_axi_w_strb,
    output wire         m_axi_w_last,
    input  wire         m_axi_b_valid,  output wire m_axi_b_ready
);

    // ==================================================================
    // cmd_tracker
    // ==================================================================
    wire        prp_start, prp_done, prp_error;
    wire [16:0] prp_error_status;
    wire [63:0] prp_prp1, prp_prp2;
    wire [31:0] prp_transfer_bytes;
    wire        rd_start, rd_done;
    wire [63:0] rd_slba;
    wire [31:0] rd_total_bytes;

    nvme_cmd_tracker #(.NUM_SLOTS(4)) inst_tracker (
        .clk_i, .rst_ni,
        .cmd_valid_i,  .cmd_ready_o,
        .cmd_opcode_i, .cmd_cid_i, .cmd_nsid_i,
        .cmd_prp1_i,   .cmd_prp2_i,
        .cmd_slba_i,   .cmd_nlb_i,
        .cmd_sqid_i,   .cmd_sq_head_i,
        .prp_start_o(prp_start), .prp_done_i(prp_done),
        .prp_error_i(prp_error), .prp_error_status_i(prp_error_status),
        .prp_prp1_o(prp_prp1),   .prp_prp2_o(prp_prp2),
        .prp_transfer_bytes_o(prp_transfer_bytes),
        .rd_start_o(rd_start),   .rd_done_i(rd_done),
        .rd_slba_o(rd_slba),     .rd_total_bytes_o(rd_total_bytes),
        .cpl_valid_o,            .cpl_ready_i,
        .cpl_sqid_o, .cpl_sqhd_o, .cpl_cid_o, .cpl_status_o
    );

    // ==================================================================
    // prp_walker
    // ==================================================================
    wire [63:0] page_addr;
    wire [16:0] page_bytes;
    wire        page_valid, page_last, page_ready, page_done;

    nvme_prp_walker inst_prp (
        .clk_i, .rst_ni,
        .start_i(prp_start),       .done_o(prp_done),
        .error_o(prp_error),       .error_status_o(prp_error_status),
        .prp1_i(prp_prp1),         .prp2_i(prp_prp2),
        .transfer_bytes_i(prp_transfer_bytes),
        .page_addr_o(page_addr),   .page_bytes_o(page_bytes),
        .page_valid_o(page_valid), .page_last_o(page_last),
        .page_ready_i(page_ready),
        .list_ar_valid_o(),        .list_ar_ready_i(1'b0),
        .list_ar_addr_o(),         .list_ar_len_o(),
        .list_r_valid_i(1'b0),     .list_r_ready_o(),
        .list_r_data_i(64'd0),     .list_r_last_i(1'b0),
        .page_done_i(page_done)
    );

    // ==================================================================
    // read_engine
    // ==================================================================
    nvme_read_engine inst_read (
        .clk_i, .rst_ni,
        .start_i(rd_start),        .done_o(rd_done),
        .slba_i(rd_slba),          .total_bytes_i(rd_total_bytes),
        .page_addr_i(page_addr),   .page_bytes_i(page_bytes),
        .page_valid_i(page_valid), .page_last_i(page_last),
        .page_ready_o(page_ready),
        .page_done_o(page_done),
        .nvm_addr_o,               .nvm_rd_en_o,
        .nvm_rdata_i,              .nvm_rvalid_i,
        .nvm_rready_o(),
        .axi_aw_valid_o(m_axi_aw_valid), .axi_aw_ready_i(m_axi_aw_ready),
        .axi_aw_addr_o(m_axi_aw_addr),   .axi_aw_len_o(m_axi_aw_len),
        .axi_w_valid_o(m_axi_w_valid),   .axi_w_ready_i(m_axi_w_ready),
        .axi_w_data_o(m_axi_w_data),     .axi_w_strb_o(m_axi_w_strb),
        .axi_w_last_o(m_axi_w_last),
        .axi_b_valid_i(m_axi_b_valid),   .axi_b_ready_o(m_axi_b_ready),
        .axi_b_resp_i(2'd0)
    );

endmodule
`default_nettype wire
