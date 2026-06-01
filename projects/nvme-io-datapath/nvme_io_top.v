// =============================================================================
// nvme_io_top — NVMe I/O Data Path Top-Level Integration (Phase 3)
// =============================================================================
//
// Instantiates:
//   - nvme_sq_fetch  (reused): SQE fetch from host memory
//   - nvme_cq_post   (reused): CQE post to host memory
//   - nvme_cmd_tracker (new): 4-slot I/O command tracker
//   - nvme_prp_walker  (new): PRP traversal engine
//   - nvme_read_engine (new): NVM read + AXI write data path
//   - nvme_axi_adapter (extended): 4-source AXI mux
//
// Command flow:
//   SQ Fetch → demux (opcode=02h) → cmd_tracker → prp_walker → read_engine
//                                                              ↓
//   cmd_tracker ←── read_engine.done ──────────────────────────┘
//        ↓
//   cq_post → AXI adapter → Host Memory (CQE)
//
// =============================================================================

`default_nettype none

module nvme_io_top (
    input  wire         clk_i,
    input  wire         rst_ni,

    // ── SQ configuration (from testbench) ──
    input  wire [63:0]  sq_base_i,
    input  wire [15:0]  sq_depth_i,
    input  wire [15:0]  cq_depth_i,
    input  wire [63:0]  cq_base_i,

    // ── Doorbell input (from testbench) ──
    input  wire [15:0]  doorbell_tail_i,
    input  wire         doorbell_valid_i,

    // ── NVM SRAM interface (to testbench) ──
    output wire [63:0]  nvm_addr_o,
    output wire         nvm_rd_en_o,
    input  wire [63:0]  nvm_rdata_i,
    input  wire         nvm_rvalid_i,

    // ── AXI Master (to testbench host memory model) ──
    output wire         m_axi_ar_valid,
    input  wire         m_axi_ar_ready,
    output wire [63:0]  m_axi_ar_addr,
    output wire [7:0]   m_axi_ar_len,

    input  wire         m_axi_r_valid,
    output wire         m_axi_r_ready,
    input  wire [63:0]  m_axi_r_data,
    input  wire         m_axi_r_last,

    output wire         m_axi_aw_valid,
    input  wire         m_axi_aw_ready,
    output wire [63:0]  m_axi_aw_addr,
    output wire [7:0]   m_axi_aw_len,

    output wire         m_axi_w_valid,
    input  wire         m_axi_w_ready,
    output wire [63:0]  m_axi_w_data,
    output wire [7:0]   m_axi_w_strb,
    output wire         m_axi_w_last,

    input  wire         m_axi_b_valid,
    output wire         m_axi_b_ready,

    // ── Debug / monitoring ──
    output wire         cqe_written_o,      // pulse: CQE posted to host memory
    output wire [15:0]  cqe_cid_o,          // CID from posted CQE
    output wire [15:0]  cqe_status_o        // Status from posted CQE
);

    // =========================================================================
    // Internal wires — SQ Fetch → Demux
    // =========================================================================
    wire        sq_cmd_valid;
    wire        sq_cmd_ready;
    wire [7:0]  sq_cmd_opcode;
    wire [15:0] sq_cmd_cid;
    wire [31:0] sq_cmd_nsid;
    wire [63:0] sq_cmd_prp1;
    wire [63:0] sq_cmd_prp2;
    wire [31:0] sq_cmd_cdw10;   // SLBA[31:0]
    wire [31:0] sq_cmd_cdw11;   // SLBA[63:32]
    wire [7:0]  sq_cmd_sqid;
    wire [15:0] sq_head_update;
    wire        sq_head_update_valid;

    // SQ Fetch AXI → Adapter S0
    wire        s0_ar_valid, s0_ar_ready;
    wire [63:0] s0_ar_addr;
    wire [7:0]  s0_ar_len;
    wire        s0_r_valid,  s0_r_ready;
    wire [63:0] s0_r_data;
    wire        s0_r_last;

    // =========================================================================
    // Internal wires — Demux → cmd_tracker
    // =========================================================================
    wire        tkr_cmd_valid;
    wire        tkr_cmd_ready;
    wire [63:0] tkr_slba;

    // =========================================================================
    // Internal wires — cmd_tracker → prp_walker
    // =========================================================================
    wire        prp_start, prp_done, prp_error;
    wire [15:0] prp_error_status;
    wire [63:0] prp1, prp2;
    wire [31:0] prp_xfer_bytes;

    // =========================================================================
    // Internal wires — cmd_tracker → read_engine
    // =========================================================================
    wire        rd_start, rd_done, rd_error;
    wire [63:0] rd_slba;
    wire [31:0] rd_total_bytes;

    // =========================================================================
    // Internal wires — prp_walker → read_engine (page interface)
    // =========================================================================
    wire [63:0] page_addr;
    wire [15:0] page_bytes;
    wire        page_valid, page_ready, page_done;

    // =========================================================================
    // Internal wires — prp_walker → AXI adapter S2 (list fetch)
    // =========================================================================
    wire        s2_ar_valid, s2_ar_ready;
    wire [63:0] s2_ar_addr;
    wire [7:0]  s2_ar_len;
    wire        s2_r_valid,  s2_r_ready;
    wire [63:0] s2_r_data;
    wire        s2_r_last;

    // =========================================================================
    // Internal wires — read_engine → AXI adapter S3 (data write)
    // =========================================================================
    wire        s3_aw_valid, s3_aw_ready;
    wire [63:0] s3_aw_addr;
    wire [7:0]  s3_aw_len;
    wire        s3_w_valid,  s3_w_ready;
    wire [63:0] s3_w_data;
    wire [7:0]  s3_w_strb;
    wire        s3_w_last;
    wire        s3_b_valid,  s3_b_ready;

    // =========================================================================
    // Internal wires — cmd_tracker → cq_post
    // =========================================================================
    wire        cpl_valid, cpl_ready;
    wire [7:0]  cpl_sqid;
    wire [15:0] cpl_sqhd;
    wire [15:0] cpl_cid;
    wire [15:0] cpl_status;

    // =========================================================================
    // Internal wires — cq_post → AXI adapter S1
    // =========================================================================
    wire        s1_aw_valid, s1_aw_ready;
    wire [63:0] s1_aw_addr;
    wire        s1_w_valid,  s1_w_ready;
    wire [63:0] s1_w_data;
    wire [7:0]  s1_w_strb;
    wire        s1_w_last;
    wire        s1_b_valid,  s1_b_ready;

    // =========================================================================
    // Credit accumulator (simplified: pulse-based doorbell)
    // =========================================================================
    reg [15:0] credits_q;
    wire       credits_inc;

    assign credits_inc = doorbell_valid_i;  // each doorbell = 1 new command

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            credits_q <= 16'd0;
        else if (credits_inc && sq_head_update_valid)
            credits_q <= credits_q + 16'd1 - 16'd1;  // net: +1 doorbell, -1 fetched
        else if (credits_inc)
            credits_q <= credits_q + 16'd1;
        else if (sq_head_update_valid)
            credits_q <= credits_q - 16'd1;
    end

    // =========================================================================
    // Command demux: Admin vs NVM Read
    // =========================================================================
    localparam [7:0] OPC_NVM_READ = 8'h02;

    wire is_nvm_read = (sq_cmd_opcode == OPC_NVM_READ);

    assign tkr_cmd_valid = sq_cmd_valid && is_nvm_read;
    assign sq_cmd_ready  = is_nvm_read ? tkr_cmd_ready : 1'b1;

    // SLBA from CDW10[31:0] + CDW11[31:0]
    assign tkr_slba = {sq_cmd_cdw11, sq_cmd_cdw10};

    // =========================================================================
    // SQ head held register (for CQE.SQHD) — Phase 1 Bug #1 fix
    // =========================================================================
    reg [15:0] sq_head_held_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            sq_head_held_q <= 16'd0;
        else if (sq_head_update_valid)
            sq_head_held_q <= sq_head_update;
    end

    // =========================================================================
    // Module Instantiations
    // =========================================================================

    // ── SQ Fetch Engine (reused from Phase 1) ──
    nvme_sq_fetch u_sq_fetch (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .sq_base_i        (sq_base_i),
        .sq_depth_i       (sq_depth_i),
        .sq_id_i          (8'd0),           // Admin SQ for Phase 3 testing
        .cq_id_i          (8'd0),           // Admin CQ
        .credits_i        (16'd1),          // 1 credit per doorbell pulse
        .credits_valid_i  (credits_inc),
        .cmd_valid_o      (sq_cmd_valid),
        .cmd_ready_i      (sq_cmd_ready),
        .cmd_opcode_o     (sq_cmd_opcode),
        .cmd_cid_o        (sq_cmd_cid),
        .cmd_nsid_o       (sq_cmd_nsid),
        .cmd_prp1_o       (sq_cmd_prp1),
        .cmd_prp2_o       (sq_cmd_prp2),
        .cmd_cdw10_o      (sq_cmd_cdw10),
        .cmd_cdw11_o      (sq_cmd_cdw11),
        .cmd_sqid_o       (sq_cmd_sqid),
        .axi_ar_valid_o   (s0_ar_valid),
        .axi_ar_ready_i   (s0_ar_ready),
        .axi_ar_addr_o    (s0_ar_addr),
        .axi_ar_len_o     (s0_ar_len),
        .axi_ar_size_o    (),               // unused
        .axi_r_valid_i    (s0_r_valid),
        .axi_r_ready_o    (s0_r_ready),
        .axi_r_data_i     (s0_r_data),
        .axi_r_last_i     (s0_r_last),
        .head_update_o    (sq_head_update),
        .head_update_valid_o (sq_head_update_valid)
    );

    // ── Command Tracker (new) ──
    nvme_cmd_tracker #(
        .NUM_SLOTS(4),
        .LBA_SIZE(512)
    ) u_cmd_tracker (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .cmd_valid_i        (tkr_cmd_valid),
        .cmd_ready_o        (tkr_cmd_ready),
        .cmd_opcode_i       (sq_cmd_opcode),
        .cmd_cid_i          (sq_cmd_cid),
        .cmd_nsid_i         (sq_cmd_nsid),
        .cmd_prp1_i         (sq_cmd_prp1),
        .cmd_prp2_i         (sq_cmd_prp2),
        .cmd_slba_i         (tkr_slba),
        .cmd_nlb_i          (sq_cmd_cdw10[15:0]),  // NLB from CDW10[15:0]
        .cmd_sqid_i         (sq_cmd_sqid),
        .cmd_sq_head_i      (sq_head_held_q),
        .prp_start_o        (prp_start),
        .prp_done_i         (prp_done),
        .prp_error_i        (prp_error),
        .prp_error_status_i (prp_error_status),
        .prp_prp1_o         (prp1),
        .prp_prp2_o         (prp2),
        .prp_transfer_bytes_o (prp_xfer_bytes),
        .rd_start_o         (rd_start),
        .rd_done_i          (rd_done),
        .rd_error_i         (rd_error),
        .rd_slba_o          (rd_slba),
        .rd_total_bytes_o   (rd_total_bytes),
        .cpl_valid_o        (cpl_valid),
        .cpl_ready_i        (cpl_ready),
        .cpl_sqid_o         (cpl_sqid),
        .cpl_sqhd_o         (cpl_sqhd),
        .cpl_cid_o          (cpl_cid),
        .cpl_status_o       (cpl_status)
    );

    // ── PRP Walker (new) ──
    nvme_prp_walker #(
        .PAGE_SIZE(4096),
        .AXI_DATA_W(64),
        .AXI_ADDR_W(64),
        .LIST_ENTRIES(512)
    ) u_prp_walker (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .start_i            (prp_start),
        .done_o             (prp_done),
        .error_o            (prp_error),
        .error_status_o     (prp_error_status),
        .prp1_i             (prp1),
        .prp2_i             (prp2),
        .transfer_bytes_i   (prp_xfer_bytes),
        .page_addr_o        (page_addr),
        .page_bytes_o       (page_bytes),
        .page_valid_o       (page_valid),
        .page_ready_i       (page_ready),
        .page_done_i        (page_done),
        .list_ar_valid_o    (s2_ar_valid),
        .list_ar_ready_i    (s2_ar_ready),
        .list_ar_addr_o     (s2_ar_addr),
        .list_ar_len_o      (s2_ar_len),
        .list_r_valid_i     (s2_r_valid),
        .list_r_ready_o     (s2_r_ready),
        .list_r_data_i      (s2_r_data),
        .list_r_last_i      (s2_r_last)
    );

    // ── Read Engine (new) ──
    nvme_read_engine #(
        .AXI_DATA_W(64),
        .AXI_ADDR_W(64),
        .AXI_MAX_BURST(256),
        .LBA_SIZE(512),
        .FIFO_DEPTH(512),
        .FIFO_ADDR_W(9)
    ) u_read_engine (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .start_i            (rd_start),
        .done_o             (rd_done),
        .error_o            (rd_error),
        .slba_i             (rd_slba),
        .total_bytes_i      (rd_total_bytes),
        .page_addr_i        (page_addr),
        .page_bytes_i       (page_bytes),
        .page_valid_i       (page_valid),
        .page_ready_o       (page_ready),
        .page_done_o        (page_done),
        .nvm_addr_o         (nvm_addr_o),
        .nvm_rd_en_o        (nvm_rd_en_o),
        .nvm_rdata_i        (nvm_rdata_i),
        .nvm_rvalid_i       (nvm_rvalid_i),
        .axi_aw_valid_o     (s3_aw_valid),
        .axi_aw_ready_i     (s3_aw_ready),
        .axi_aw_addr_o      (s3_aw_addr),
        .axi_aw_len_o       (s3_aw_len),
        .axi_w_valid_o      (s3_w_valid),
        .axi_w_ready_i      (s3_w_ready),
        .axi_w_data_o       (s3_w_data),
        .axi_w_strb_o       (s3_w_strb),
        .axi_w_last_o       (s3_w_last),
        .axi_b_valid_i      (s3_b_valid),
        .axi_b_ready_o      (s3_b_ready),
        .axi_b_resp_i       (2'b00)         // assume OKAY
    );

    // ── CQ Post Engine (reused from Phase 1) ──
    // Note: cq_post does not have B channel ports — CQE writes don't need B ack
    nvme_cq_post u_cq_post (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .cq_base_i          (cq_base_i),
        .cq_depth_i         (cq_depth_i),
        .cpl_valid_i        (cpl_valid),
        .cpl_ready_o        (cpl_ready),
        .cpl_sqid_i         (cpl_sqid),
        .cpl_sqhd_i         (cpl_sqhd),
        .cpl_cid_i          (cpl_cid),
        .cpl_status_i       (cpl_status),
        .cpl_has_data_i     (1'b0),         // Read: no associated data write
        .cq_data_done_i     (1'b1),         // N/A (cpl_has_data=0 skips WAIT_DATA)
        .cq_data_head_i     (16'd0),
        .axi_aw_valid_o     (s1_aw_valid),
        .axi_aw_ready_i     (s1_aw_ready),
        .axi_aw_addr_o      (s1_aw_addr),
        .axi_w_valid_o      (s1_w_valid),
        .axi_w_ready_i      (s1_w_ready),
        .axi_w_data_o       (s1_w_data),
        .axi_w_strb_o       (s1_w_strb),
        .axi_w_last_o       (s1_w_last)
    );

    // ── AXI Adapter (extended) ──
    nvme_axi_adapter u_axi_adapter (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),

        .s0_ar_valid_i      (s0_ar_valid),
        .s0_ar_ready_o      (s0_ar_ready),
        .s0_ar_addr_i       (s0_ar_addr),
        .s0_ar_len_i        (s0_ar_len),
        .s0_r_valid_o       (s0_r_valid),
        .s0_r_ready_i       (s0_r_ready),
        .s0_r_data_o        (s0_r_data),
        .s0_r_last_o        (s0_r_last),

        .s1_aw_valid_i      (s1_aw_valid),
        .s1_aw_ready_o      (s1_aw_ready),
        .s1_aw_addr_i       (s1_aw_addr),
        .s1_w_valid_i       (s1_w_valid),
        .s1_w_ready_o       (s1_w_ready),
        .s1_w_data_i        (s1_w_data),
        .s1_w_strb_i        (s1_w_strb),
        .s1_w_last_i        (s1_w_last),
        .s1_b_valid_o       (s1_b_valid),
        .s1_b_ready_i       (s1_b_ready),

        .s2_ar_valid_i      (s2_ar_valid),
        .s2_ar_ready_o      (s2_ar_ready),
        .s2_ar_addr_i       (s2_ar_addr),
        .s2_ar_len_i        (s2_ar_len),
        .s2_r_valid_o       (s2_r_valid),
        .s2_r_ready_i       (s2_r_ready),
        .s2_r_data_o        (s2_r_data),
        .s2_r_last_o        (s2_r_last),

        .s3_aw_valid_i      (s3_aw_valid),
        .s3_aw_ready_o      (s3_aw_ready),
        .s3_aw_addr_i       (s3_aw_addr),
        .s3_aw_len_i        (s3_aw_len),
        .s3_w_valid_i       (s3_w_valid),
        .s3_w_ready_o       (s3_w_ready),
        .s3_w_data_i        (s3_w_data),
        .s3_w_strb_i        (s3_w_strb),
        .s3_w_last_i        (s3_w_last),
        .s3_b_valid_o       (s3_b_valid),
        .s3_b_ready_i       (s3_b_ready),

        .m_axi_ar_valid     (m_axi_ar_valid),
        .m_axi_ar_ready     (m_axi_ar_ready),
        .m_axi_ar_addr      (m_axi_ar_addr),
        .m_axi_ar_len       (m_axi_ar_len),
        .m_axi_r_valid      (m_axi_r_valid),
        .m_axi_r_ready      (m_axi_r_ready),
        .m_axi_r_data       (m_axi_r_data),
        .m_axi_r_last       (m_axi_r_last),
        .m_axi_aw_valid     (m_axi_aw_valid),
        .m_axi_aw_ready     (m_axi_aw_ready),
        .m_axi_aw_addr      (m_axi_aw_addr),
        .m_axi_aw_len       (m_axi_aw_len),
        .m_axi_w_valid      (m_axi_w_valid),
        .m_axi_w_ready      (m_axi_w_ready),
        .m_axi_w_data       (m_axi_w_data),
        .m_axi_w_strb       (m_axi_w_strb),
        .m_axi_w_last       (m_axi_w_last),
        .m_axi_b_valid      (m_axi_b_valid),
        .m_axi_b_ready      (m_axi_b_ready),
        .m_axi_b_resp       (2'b00)         // assume OKAY
    );

    // =========================================================================
    // Debug outputs
    // =========================================================================
    reg cqe_written_q;
    reg [15:0] cqe_cid_q;
    reg [15:0] cqe_status_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cqe_written_q  <= 1'b0;
            cqe_cid_q      <= 16'd0;
            cqe_status_q   <= 16'd0;
        end else begin
            cqe_written_q <= 1'b0;  // pulse default
            if (cpl_valid && cpl_ready) begin
                cqe_written_q <= 1'b1;
                cqe_cid_q     <= cpl_cid;
                cqe_status_q  <= cpl_status;
            end
        end
    end

    assign cqe_written_o = cqe_written_q;
    assign cqe_cid_o     = cqe_cid_q;
    assign cqe_status_o  = cqe_status_q;

endmodule

`default_nettype wire
