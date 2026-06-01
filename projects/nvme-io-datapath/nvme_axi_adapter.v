// =============================================================================
// nvme_axi_adapter — AXI channel mux/arbiter with per-burst source tracking
// =============================================================================
//
// One-outstanding-per-channel discipline:
//   - AR:  ar_busy_q blocks new AR until RLAST returns
//   - AW:  aw_busy_q blocks new AW until WLAST completes
// This guarantees ar_source_s2_q / aw_source_s3_q are never overwritten
// while a burst is in flight.
//
// Arbitration: fixed priority
//   AR:  S2 (PRP list) > S0 (SQ fetch)
//   AW:  S3 (read engine) > S1 (CQ post)
//
// =============================================================================

`default_nettype none

module nvme_axi_adapter (
    input  wire         clk_i,
    input  wire         rst_ni,

    // ── S0: SQ Fetch (AR+R) ──
    input  wire         s0_ar_valid_i,
    output wire         s0_ar_ready_o,
    input  wire [63:0]  s0_ar_addr_i,
    input  wire [7:0]   s0_ar_len_i,
    output wire         s0_r_valid_o,
    input  wire         s0_r_ready_i,
    output wire [63:0]  s0_r_data_o,
    output wire         s0_r_last_o,

    // ── S1: CQ Post (AW+W+B) ──
    input  wire         s1_aw_valid_i,
    output wire         s1_aw_ready_o,
    input  wire [63:0]  s1_aw_addr_i,
    input  wire         s1_w_valid_i,
    output wire         s1_w_ready_o,
    input  wire [63:0]  s1_w_data_i,
    input  wire [7:0]   s1_w_strb_i,
    input  wire         s1_w_last_i,
    output wire         s1_b_valid_o,
    input  wire         s1_b_ready_i,

    // ── S2: PRP Walker (AR+R) ──
    input  wire         s2_ar_valid_i,
    output wire         s2_ar_ready_o,
    input  wire [63:0]  s2_ar_addr_i,
    input  wire [7:0]   s2_ar_len_i,
    output wire         s2_r_valid_o,
    input  wire         s2_r_ready_i,
    output wire [63:0]  s2_r_data_o,
    output wire         s2_r_last_o,

    // ── S3: Read Engine (AW+W+B) ──
    input  wire         s3_aw_valid_i,
    output wire         s3_aw_ready_o,
    input  wire [63:0]  s3_aw_addr_i,
    input  wire [7:0]   s3_aw_len_i,
    input  wire         s3_w_valid_i,
    output wire         s3_w_ready_o,
    input  wire [63:0]  s3_w_data_i,
    input  wire [7:0]   s3_w_strb_i,
    input  wire         s3_w_last_i,
    output wire         s3_b_valid_o,
    input  wire         s3_b_ready_i,

    // ── Master AXI ──
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
    input  wire [1:0]   m_axi_b_resp
);

    // =========================================================================
    // AR channel — one-outstanding discipline
    // =========================================================================

    // Busy flag: set on AR accept, clear when RLAST returns
    reg ar_busy_q;
    wire ar_accept  = m_axi_ar_valid && m_axi_ar_ready;
    wire r_last_beat = m_axi_r_valid && m_axi_r_ready && m_axi_r_last;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ar_busy_q <= 1'b0;
        end else if (ar_accept) begin
            ar_busy_q <= 1'b1;
        end else if (r_last_beat) begin
            ar_busy_q <= 1'b0;
        end else begin
            ar_busy_q <= ar_busy_q;
        end
    end

    // Priority: S2 > S0. Block new AR if busy.
    wire ar_sel_s2;
    assign ar_sel_s2 = s2_ar_valid_i && !ar_busy_q;

    assign m_axi_ar_valid = ar_sel_s2 ? s2_ar_valid_i
                         : (!ar_busy_q ? s0_ar_valid_i : 1'b0);
    assign m_axi_ar_addr  = ar_sel_s2 ? s2_ar_addr_i : s0_ar_addr_i;
    assign m_axi_ar_len   = ar_sel_s2 ? s2_ar_len_i  : s0_ar_len_i;

    assign s2_ar_ready_o = ar_sel_s2 && m_axi_ar_ready;
    assign s0_ar_ready_o = !ar_sel_s2 && !ar_busy_q && m_axi_ar_ready;

    // Source tracking: latched at AR accept, stable for entire R burst
    reg ar_source_s2_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ar_source_s2_q <= 1'b0;
        end else if (ar_accept) begin
            ar_source_s2_q <= ar_sel_s2;
        end else begin
            ar_source_s2_q <= ar_source_s2_q;
        end
    end

    // R demux: route to tracked source
    assign m_axi_r_ready = ar_source_s2_q ? s2_r_ready_i : s0_r_ready_i;

    assign s2_r_valid_o =  ar_source_s2_q && m_axi_r_valid;
    assign s2_r_data_o  = m_axi_r_data;
    assign s2_r_last_o  = m_axi_r_last;

    assign s0_r_valid_o = !ar_source_s2_q && m_axi_r_valid;
    assign s0_r_data_o  = m_axi_r_data;
    assign s0_r_last_o  = m_axi_r_last;

    // =========================================================================
    // AW/W channel — one-outstanding discipline
    // =========================================================================

    // Busy flag: set on AW accept, clear when WLAST returns
    reg aw_busy_q;
    wire aw_accept   = m_axi_aw_valid && m_axi_aw_ready;
    wire w_last_beat = m_axi_w_valid && m_axi_w_ready && m_axi_w_last;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_busy_q <= 1'b0;
        end else if (aw_accept) begin
            aw_busy_q <= 1'b1;
        end else if (w_last_beat) begin
            aw_busy_q <= 1'b0;
        end else begin
            aw_busy_q <= aw_busy_q;
        end
    end

    // Priority: S3 > S1. Block new AW if busy.
    wire aw_sel_s3;
    assign aw_sel_s3 = s3_aw_valid_i && !aw_busy_q;

    assign m_axi_aw_valid = aw_sel_s3 ? s3_aw_valid_i
                         : (!aw_busy_q ? s1_aw_valid_i : 1'b0);
    assign m_axi_aw_addr  = aw_sel_s3 ? s3_aw_addr_i : s1_aw_addr_i;
    assign m_axi_aw_len   = aw_sel_s3 ? s3_aw_len_i  : 8'd1;

    assign s3_aw_ready_o = aw_sel_s3 && m_axi_aw_ready;
    assign s1_aw_ready_o = !aw_sel_s3 && !aw_busy_q && m_axi_aw_ready;

    // Source tracking: latched at AW accept, stable for entire W burst
    reg aw_source_s3_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_source_s3_q <= 1'b0;
        end else if (aw_accept) begin
            aw_source_s3_q <= aw_sel_s3;
        end else begin
            aw_source_s3_q <= aw_source_s3_q;
        end
    end

    // W mux: route from tracked source
    assign m_axi_w_valid = aw_source_s3_q ? s3_w_valid_i : s1_w_valid_i;
    assign m_axi_w_data  = aw_source_s3_q ? s3_w_data_i  : s1_w_data_i;
    assign m_axi_w_strb  = aw_source_s3_q ? s3_w_strb_i  : s1_w_strb_i;
    assign m_axi_w_last  = aw_source_s3_q ? s3_w_last_i  : s1_w_last_i;

    assign s3_w_ready_o =  aw_source_s3_q && m_axi_w_ready;
    assign s1_w_ready_o = !aw_source_s3_q && m_axi_w_ready;

    // B demux: route to tracked source
    assign m_axi_b_ready = aw_source_s3_q ? s3_b_ready_i : s1_b_ready_i;

    assign s3_b_valid_o =  aw_source_s3_q && m_axi_b_valid;
    assign s1_b_valid_o = !aw_source_s3_q && m_axi_b_valid;

endmodule

`default_nettype wire
