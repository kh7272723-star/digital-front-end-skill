`default_nettype none

// NVMe AXI Adapter — simplified AXI-Lite master mux
//
// Phase 1 supports exactly 2 sources:
//   Source 0: SQ Fetch Engine      (AR channel only — reads from host memory)
//   Source 1: CQ Post Engine       (AW+W channel only — writes to host memory)
//
// Since AR and AW/W use independent AXI channels with distinct valid/ready
// pairs, no arbitration is needed. This module is a pure combinational
// pass-through mux (zero latency).
//
// Map:
//   Source 0  →  m_axi AR / R channels
//   Source 1  →  m_axi AW / W / B channels

module nvme_axi_adapter (
    // Clock and reset (unused in Phase 1 — pure combinational)
    input  wire         clk_i,
    input  wire         rst_ni,

    // -----------------------------------------------------------------------
    // Source 0: SQ Fetch Engine (AR channel only)
    // -----------------------------------------------------------------------
    input  wire         s0_ar_valid_i,
    output wire         s0_ar_ready_o,
    input  wire [63:0]  s0_ar_addr_i,
    input  wire [7:0]   s0_ar_len_i,
    input  wire [2:0]   s0_ar_size_i,

    output wire         s0_r_valid_o,
    input  wire         s0_r_ready_i,
    output wire [63:0]  s0_r_data_o,
    output wire         s0_r_last_o,

    // -----------------------------------------------------------------------
    // Source 1: CQ Post Engine (AW+W channel only)
    // -----------------------------------------------------------------------
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

    // -----------------------------------------------------------------------
    // AXI Master Interface (to host memory / top-level testbench)
    // -----------------------------------------------------------------------
    // Read Address  — Source 0 drives
    output wire         m_axi_ar_valid,
    input  wire         m_axi_ar_ready,
    output wire [63:0]  m_axi_ar_addr,
    output wire [7:0]   m_axi_ar_len,
    output wire [2:0]   m_axi_ar_size,

    // Read Data  — routes to Source 0
    input  wire         m_axi_r_valid,
    output wire         m_axi_r_ready,
    input  wire [63:0]  m_axi_r_data,
    input  wire         m_axi_r_last,

    // Write Address  — Source 1 drives
    output wire         m_axi_aw_valid,
    input  wire         m_axi_aw_ready,
    output wire [63:0]  m_axi_aw_addr,

    // Write Data  — Source 1 drives
    output wire         m_axi_w_valid,
    input  wire         m_axi_w_ready,
    output wire [63:0]  m_axi_w_data,
    output wire [7:0]   m_axi_w_strb,
    output wire         m_axi_w_last,

    // Write Response  — routes to Source 1
    input  wire         m_axi_b_valid,
    output wire         m_axi_b_ready
);

    // -----------------------------------------------------------------------
    // AR channel: Source 0 → Master
    // -----------------------------------------------------------------------
    assign m_axi_ar_valid = s0_ar_valid_i;
    assign s0_ar_ready_o  = m_axi_ar_ready;
    assign m_axi_ar_addr  = s0_ar_addr_i;
    assign m_axi_ar_len   = s0_ar_len_i;
    assign m_axi_ar_size  = s0_ar_size_i;

    // -----------------------------------------------------------------------
    // R channel: Master → Source 0
    // -----------------------------------------------------------------------
    assign s0_r_valid_o = m_axi_r_valid;
    assign m_axi_r_ready = s0_r_ready_i;
    assign s0_r_data_o  = m_axi_r_data;
    assign s0_r_last_o  = m_axi_r_last;

    // -----------------------------------------------------------------------
    // AW channel: Source 1 → Master
    // -----------------------------------------------------------------------
    assign m_axi_aw_valid = s1_aw_valid_i;
    assign s1_aw_ready_o  = m_axi_aw_ready;
    assign m_axi_aw_addr  = s1_aw_addr_i;

    // -----------------------------------------------------------------------
    // W channel: Source 1 → Master
    // -----------------------------------------------------------------------
    assign m_axi_w_valid = s1_w_valid_i;
    assign s1_w_ready_o  = m_axi_w_ready;
    assign m_axi_w_data  = s1_w_data_i;
    assign m_axi_w_strb  = s1_w_strb_i;
    assign m_axi_w_last  = s1_w_last_i;

    // -----------------------------------------------------------------------
    // B channel: Master → Source 1
    // -----------------------------------------------------------------------
    assign s1_b_valid_o = m_axi_b_valid;
    assign m_axi_b_ready = s1_b_ready_i;

endmodule

`default_nettype wire
