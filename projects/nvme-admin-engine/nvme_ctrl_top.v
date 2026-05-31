`default_nettype none
// ============================================================================
// nvme_ctrl_top — NVMe Admin Command Engine Integration Top
// Wires: reg_file → sq_fetch → admin_exec → cq_post
//        sq_fetch/cq_post → axi_adapter → AXI master
// ============================================================================
module nvme_ctrl_top (
    input  wire       clk_i,
    input  wire       rst_ni,
    // APB (to register file)
    input  wire       psel_i,
    input  wire       penable_i,
    input  wire [15:0] paddr_i,
    input  wire       pwrite_i,
    input  wire [31:0] pwdata_i,
    output wire [31:0] prdata_o,
    output wire       pready_o,
    output wire       pslverr_o,
    // Identify data write path (exposed for testbench to write to host mem)
    output wire       cq_data_wr_o,
    output wire [63:0] cq_data_addr_o,
    output wire [63:0] cq_data_o,
    output wire       cq_data_valid_o,
    output wire       cq_data_last_o,
    input  wire       cq_data_ready_i,

    // AXI-Lite Master (from adapter, to host memory testbench)
    output wire       m_axi_aw_valid,
    input  wire       m_axi_aw_ready,
    output wire [63:0] m_axi_aw_addr,
    output wire       m_axi_w_valid,
    input  wire       m_axi_w_ready,
    output wire [63:0] m_axi_w_data,
    output wire [7:0]  m_axi_w_strb,
    output wire       m_axi_w_last,
    output wire       m_axi_ar_valid,
    input  wire       m_axi_ar_ready,
    output wire [63:0] m_axi_ar_addr,
    output wire [7:0]  m_axi_ar_len,
    output wire [2:0]  m_axi_ar_size,
    input  wire       m_axi_r_valid,
    output wire       m_axi_r_ready,
    input  wire [63:0] m_axi_r_data,
    input  wire       m_axi_r_last,
    input  wire       m_axi_b_valid,
    output wire       m_axi_b_ready
);
    // ─────────────────────────────────────────────────
    // Register file signals
    // ─────────────────────────────────────────────────
    wire        ctrl_ready;
    wire [63:0] admin_sq_base, admin_cq_base;
    wire [15:0] admin_sq_depth, admin_cq_depth;
    wire        doorbell_valid;
    wire [7:0]  doorbell_qid;
    wire        doorbell_is_sq;
    wire [15:0] doorbell_value;

    // ─────────────────────────────────────────────────
    // SQ fetch signals
    // ─────────────────────────────────────────────────
    wire        s0_ar_valid, s0_ar_ready;
    wire [63:0] s0_ar_addr;
    wire [7:0]  s0_ar_len;
    wire [2:0]  s0_ar_size;
    wire        s0_r_valid, s0_r_ready;
    wire [63:0] s0_r_data;
    wire        s0_r_last;
    wire        cmd_valid, cmd_ready;
    wire [7:0]  cmd_opcode;
    wire [15:0] cmd_cid;
    wire [31:0] cmd_nsid;
    wire [63:0] cmd_prp1, cmd_prp2;
    wire [31:0] cmd_cdw10, cmd_cdw11;
    wire [7:0]  cmd_sqid;
    wire [15:0] sq_head_update;
    wire        sq_head_update_valid;

    // ─────────────────────────────────────────────────
    // Admin exec signals
    // ─────────────────────────────────────────────────
    wire        cq_data_wr;
    wire [63:0] cq_data_addr, cq_data;
    wire        cq_data_valid, cq_data_last, cq_data_ready;
    wire        cpl_valid, cpl_ready;
    wire [7:0]  cpl_sqid;
    wire [15:0] cpl_sqhd;
    wire [15:0] cpl_cid;
    wire [15:0] cpl_status;
    wire        cpl_has_data;
    wire        queue_alloc;
    wire [7:0]  queue_id;
    wire [15:0] queue_depth;
    wire        queue_is_sq;
    wire [7:0]  queue_cqid;

    // ─────────────────────────────────────────────────
    // CQ post signals
    // ─────────────────────────────────────────────────
    wire        s1_aw_valid, s1_aw_ready;
    wire [63:0] s1_aw_addr;
    wire        s1_w_valid, s1_w_ready;
    wire [63:0] s1_w_data;
    wire [7:0]  s1_w_strb;
    wire        s1_w_last;
    wire        s1_b_valid, s1_b_ready;

    // ─────────────────────────────────────────────────
    // Instantiations
    // ─────────────────────────────────────────────────

    nvme_reg_file u_reg_file (
        .clk_i, .rst_ni,
        .psel_i, .penable_i, .paddr_i, .pwrite_i, .pwdata_i,
        .prdata_o, .pready_o, .pslverr_o,
        .ctrl_ready_o(ctrl_ready),
        .admin_sq_base_o(admin_sq_base),
        .admin_cq_base_o(admin_cq_base),
        .admin_sq_depth_o(admin_sq_depth),
        .admin_cq_depth_o(admin_cq_depth),
        .doorbell_valid_o(doorbell_valid),
        .doorbell_qid_o(doorbell_qid),
        .doorbell_is_sq_o(doorbell_is_sq),
        .doorbell_value_o(doorbell_value)
    );

    nvme_sq_fetch u_sq_fetch (
        .clk_i, .rst_ni,
        .sq_base_i(admin_sq_base),
        .sq_depth_i(admin_sq_depth),
        .sq_id_i(8'd0),       // Admin SQ is always QID=0
        .cq_id_i(8'd0),       // Admin CQ is always CQID=0
        .credits_i(doorbell_value),
        .credits_valid_i(doorbell_valid && doorbell_is_sq && doorbell_qid == 8'd0),
        .axi_ar_valid_o(s0_ar_valid),
        .axi_ar_ready_i(s0_ar_ready),
        .axi_ar_addr_o(s0_ar_addr),
        .axi_ar_len_o(s0_ar_len),
        .axi_ar_size_o(s0_ar_size),
        .axi_r_valid_i(s0_r_valid),
        .axi_r_ready_o(s0_r_ready),
        .axi_r_data_i(s0_r_data),
        .axi_r_last_i(s0_r_last),
        .cmd_valid_o(cmd_valid),
        .cmd_ready_i(cmd_ready),
        .cmd_opcode_o(cmd_opcode),
        .cmd_cid_o(cmd_cid),
        .cmd_nsid_o(cmd_nsid),
        .cmd_prp1_o(cmd_prp1),
        .cmd_prp2_o(cmd_prp2),
        .cmd_cdw10_o(cmd_cdw10),
        .cmd_cdw11_o(cmd_cdw11),
        .cmd_sqid_o(cmd_sqid),
        .head_update_o(sq_head_update),
        .head_update_valid_o(sq_head_update_valid)
    );

    nvme_admin_exec u_admin_exec (
        .clk_i, .rst_ni,
        .cmd_valid_i(cmd_valid),
        .cmd_ready_o(cmd_ready),
        .cmd_opcode_i(cmd_opcode),
        .cmd_cid_i(cmd_cid),
        .cmd_nsid_i(cmd_nsid),
        .cmd_prp1_i(cmd_prp1),
        .cmd_prp2_i(cmd_prp2),
        .cmd_cdw10_i(cmd_cdw10),
        .cmd_cdw11_i(cmd_cdw11),
        .cmd_sqid_i(cmd_sqid),
        .cq_data_wr_o(cq_data_wr),
        .cq_data_addr_o(cq_data_addr),
        .cq_data_o(cq_data),
        .cq_data_valid_o(cq_data_valid),
        .cq_data_last_o(cq_data_last),
        .cq_data_ready_i(cq_data_ready),
        .cpl_valid_o(cpl_valid),
        .cpl_ready_i(cpl_ready),
        .cpl_sqid_o(cpl_sqid),
        .cpl_sqhd_o(),  // Not used — SQ head comes from sq_fetch directly
        .cpl_cid_o(cpl_cid),
        .cpl_status_o(cpl_status),
        .cpl_has_data_o(cpl_has_data),
        .queue_alloc_o(queue_alloc),
        .queue_id_o(queue_id),
        .queue_depth_o(queue_depth),
        .queue_is_sq_o(queue_is_sq),
        .queue_cqid_o(queue_cqid)
    );

    // Connect SQ head update to CQ completion SQHD field
    // Store sq_head when update pulse fires; use it when completion fires
    reg  [15:0] sq_head_held_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            sq_head_held_q <= 16'd0;
        else if (sq_head_update_valid)
            sq_head_held_q <= sq_head_update;
    end
    assign cpl_sqhd = sq_head_held_q;

    nvme_cq_post u_cq_post (
        .clk_i, .rst_ni,
        .cq_base_i(admin_cq_base),
        .cq_depth_i(admin_cq_depth),
        .cpl_valid_i(cpl_valid),
        .cpl_ready_o(cpl_ready),
        .cpl_sqid_i(cpl_sqid),
        .cpl_sqhd_i(cpl_sqhd),
        .cpl_cid_i(cpl_cid),
        .cpl_status_i(cpl_status),
        .cpl_has_data_i(cpl_has_data),
        .cq_data_done_i(1'b1),  // Phase 1: data goes via cq_data_* path directly, no wait needed
        .cq_data_head_i(sq_head_held_q),
        .axi_aw_valid_o(s1_aw_valid),
        .axi_aw_ready_i(s1_aw_ready),
        .axi_aw_addr_o(s1_aw_addr),
        .axi_w_valid_o(s1_w_valid),
        .axi_w_ready_i(s1_w_ready),
        .axi_w_data_o(s1_w_data),
        .axi_w_strb_o(s1_w_strb),
        .axi_w_last_o(s1_w_last)
    );

    // For Phase 1: Identify data writes go to host memory via testbench.
    // Top-level ports expose cq_data_* so the testbench can write to host_mem.
    assign cq_data_wr_o   = cq_data_wr;
    assign cq_data_addr_o = cq_data_addr;
    assign cq_data_o      = cq_data;
    assign cq_data_valid_o = cq_data_valid;
    assign cq_data_last_o  = cq_data_last;
    assign cq_data_ready   = cq_data_ready_i;  // driven from testbench

    nvme_axi_adapter u_axi_adapter (
        .clk_i, .rst_ni,
        .s0_ar_valid_i(s0_ar_valid),
        .s0_ar_ready_o(s0_ar_ready),
        .s0_ar_addr_i(s0_ar_addr),
        .s0_ar_len_i(s0_ar_len),
        .s0_ar_size_i(s0_ar_size),
        .s0_r_valid_o(s0_r_valid),
        .s0_r_ready_i(s0_r_ready),
        .s0_r_data_o(s0_r_data),
        .s0_r_last_o(s0_r_last),
        .s1_aw_valid_i(s1_aw_valid),
        .s1_aw_ready_o(s1_aw_ready),
        .s1_aw_addr_i(s1_aw_addr),
        .s1_w_valid_i(s1_w_valid),
        .s1_w_ready_o(s1_w_ready),
        .s1_w_data_i(s1_w_data),
        .s1_w_strb_i(s1_w_strb),
        .s1_w_last_i(s1_w_last),
        .s1_b_valid_o(s1_b_valid),
        .s1_b_ready_i(s1_b_ready),
        .m_axi_aw_valid, .m_axi_aw_ready, .m_axi_aw_addr,
        .m_axi_w_valid, .m_axi_w_ready, .m_axi_w_data, .m_axi_w_strb, .m_axi_w_last,
        .m_axi_ar_valid, .m_axi_ar_ready, .m_axi_ar_addr, .m_axi_ar_len, .m_axi_ar_size,
        .m_axi_r_valid, .m_axi_r_ready, .m_axi_r_data, .m_axi_r_last,
        .m_axi_b_valid, .m_axi_b_ready
    );

endmodule
`default_nettype wire
