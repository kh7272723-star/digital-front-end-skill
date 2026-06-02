`default_nettype none
// ============================================================================
// nvme_axi_adapter — 4-Source AXI Mux/Demux
// Fixed priority: AR: S2 > S0; AW/W: S3 > S1
// ============================================================================

module nvme_axi_adapter (
    input  wire         clk_i,
    input  wire         rst_ni,
    // S0: SQ Fetch (AR+R)
    input  wire         s0_ar_valid_i,  output wire s0_ar_ready_o,
    input  wire [63:0]  s0_ar_addr_i,   input  wire [7:0] s0_ar_len_i,
    output wire         s0_r_valid_o,   input  wire s0_r_ready_i,
    output wire [63:0]  s0_r_data_o,    output wire s0_r_last_o,
    // S1: CQ Post (AW+W+B)
    input  wire         s1_aw_valid_i,  output wire s1_aw_ready_o,
    input  wire [63:0]  s1_aw_addr_i,
    input  wire         s1_w_valid_i,   output wire s1_w_ready_o,
    input  wire [63:0]  s1_w_data_i,    input  wire [7:0] s1_w_strb_i,
    input  wire         s1_w_last_i,
    output wire         s1_b_valid_o,   input  wire s1_b_ready_i,
    // S2: PRP Walker (AR+R)
    input  wire         s2_ar_valid_i,  output wire s2_ar_ready_o,
    input  wire [63:0]  s2_ar_addr_i,   input  wire [7:0] s2_ar_len_i,
    output wire         s2_r_valid_o,   input  wire s2_r_ready_i,
    output wire [63:0]  s2_r_data_o,    output wire s2_r_last_o,
    // S3: Read Engine (AW+W+B)
    input  wire         s3_aw_valid_i,  output wire s3_aw_ready_o,
    input  wire [63:0]  s3_aw_addr_i,   input  wire [7:0] s3_aw_len_i,
    input  wire         s3_w_valid_i,   output wire s3_w_ready_o,
    input  wire [63:0]  s3_w_data_i,    input  wire [7:0] s3_w_strb_i,
    input  wire         s3_w_last_i,
    output wire         s3_b_valid_o,   input  wire s3_b_ready_i,
    // Master AXI
    output wire         m_axi_ar_valid, input  wire m_axi_ar_ready,
    output wire [63:0]  m_axi_ar_addr,  output wire [7:0] m_axi_ar_len,
    input  wire         m_axi_r_valid,  output wire m_axi_r_ready,
    input  wire [63:0]  m_axi_r_data,   input  wire m_axi_r_last,
    output wire         m_axi_aw_valid, input  wire m_axi_aw_ready,
    output wire [63:0]  m_axi_aw_addr,  output wire [7:0] m_axi_aw_len,
    output wire         m_axi_w_valid,  input  wire m_axi_w_ready,
    output wire [63:0]  m_axi_w_data,   output wire [7:0] m_axi_w_strb,
    output wire         m_axi_w_last,
    input  wire         m_axi_b_valid,  output wire m_axi_b_ready
);

    // ==================================================================
    // AR arbitration: S2 > S0
    // ==================================================================
    wire ar_sel_s2 = s2_ar_valid_i;
    wire ar_sel_s0 = s0_ar_valid_i && !s2_ar_valid_i;

    assign m_axi_ar_valid = ar_sel_s2 ? s2_ar_valid_i
                          : ar_sel_s0 ? s0_ar_valid_i
                          : 1'b0;
    assign m_axi_ar_addr  = ar_sel_s2 ? s2_ar_addr_i : s0_ar_addr_i;
    assign m_axi_ar_len   = ar_sel_s2 ? s2_ar_len_i  : s0_ar_len_i;

    assign s2_ar_ready_o = ar_sel_s2 && m_axi_ar_ready;
    assign s0_ar_ready_o = ar_sel_s0 && m_axi_ar_ready;

    // AR source tracking for R demux
    reg ar_src_s2_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            ar_src_s2_q <= 0;
        else if (m_axi_ar_valid && m_axi_ar_ready)
            ar_src_s2_q <= ar_sel_s2;
    end

    // R demux
    assign m_axi_r_ready = ar_src_s2_q ? s2_r_ready_i : s0_r_ready_i;
    assign s2_r_valid_o  = ar_src_s2_q && m_axi_r_valid;
    assign s2_r_data_o   = m_axi_r_data;
    assign s2_r_last_o   = m_axi_r_last;
    assign s0_r_valid_o  = !ar_src_s2_q && m_axi_r_valid;
    assign s0_r_data_o   = m_axi_r_data;
    assign s0_r_last_o   = m_axi_r_last;

    // ==================================================================
    // AW/W arbitration: S3 > S1
    // ==================================================================
    wire aw_sel_s3 = s3_aw_valid_i;
    wire aw_sel_s1 = s1_aw_valid_i && !s3_aw_valid_i;

    assign m_axi_aw_valid = aw_sel_s3 ? s3_aw_valid_i
                          : aw_sel_s1 ? s1_aw_valid_i
                          : 1'b0;
    assign m_axi_aw_addr  = aw_sel_s3 ? s3_aw_addr_i : s1_aw_addr_i;
    assign m_axi_aw_len   = aw_sel_s3 ? s3_aw_len_i  : 8'd0;

    assign s3_aw_ready_o = aw_sel_s3 && m_axi_aw_ready;
    assign s1_aw_ready_o = aw_sel_s1 && m_axi_aw_ready;

    // W mux (follows AW selection)
    wire w_sel_s3 = s3_w_valid_i;
    wire w_sel_s1 = s1_w_valid_i && !s3_w_valid_i;

    assign m_axi_w_valid = w_sel_s3 ? s3_w_valid_i
                         : w_sel_s1 ? s1_w_valid_i : 1'b0;
    assign m_axi_w_data  = w_sel_s3 ? s3_w_data_i  : s1_w_data_i;
    assign m_axi_w_strb  = w_sel_s3 ? s3_w_strb_i  : s1_w_strb_i;
    assign m_axi_w_last  = w_sel_s3 ? s3_w_last_i  : s1_w_last_i;

    assign s3_w_ready_o = w_sel_s3 && m_axi_w_ready;
    assign s1_w_ready_o = w_sel_s1 && m_axi_w_ready;

    // AW source tracking for B demux
    reg aw_src_s3_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            aw_src_s3_q <= 0;
        else if (m_axi_aw_valid && m_axi_aw_ready)
            aw_src_s3_q <= aw_sel_s3;
    end

    // B demux
    assign m_axi_b_ready = aw_src_s3_q ? s3_b_ready_i : s1_b_ready_i;
    assign s3_b_valid_o  = aw_src_s3_q && m_axi_b_valid;
    assign s1_b_valid_o  = !aw_src_s3_q && m_axi_b_valid;

endmodule
`default_nettype wire
