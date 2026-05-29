`default_nettype none

// ADC Capture Top: multi-clock ADC data capture and AXI-Stream output.
//
// Clock domains:
//   adc_clk_i (400MHz) - ADC sample reception and block packing
//   sys_clk_i  (100MHz) - AXI-Stream serialization
//
// Reset: Single rst_ni (active-low async), synchronized per domain.
//
// CDC crossing via async FIFO (gray-coded pointers, 2FF synchronizers).
//
// Data path:
//   adc_valid_i + adc_data_i[11:0]   (adc_clk domain)
//     -> adc_sample_packer (16 samples -> 192-bit block)
//     -> async_fifo (192-bit, depth=8)
//     -> axis_serializer (192-bit -> 6 x 32-bit AXI-Stream beats)
//     -> m_axis_tvalid/tdata/tlast     (sys_clk domain)

module adc_capture_top (
    input  wire         rst_ni,            // async active-low reset
    // ADC clock domain
    input  wire         adc_clk_i,
    input  wire         adc_valid_i,
    input  wire [11:0]  adc_data_i,
    // System clock domain
    input  wire         sys_clk_i,
    // AXI-Stream output (sys_clk domain)
    output wire         m_axis_tvalid_o,
    input  wire         m_axis_tready_i,
    output wire [31:0]  m_axis_tdata_o,
    output wire         m_axis_tlast_o
);

    // -----------------------------------------------------------
    // Reset synchronizers (one per domain)
    // -----------------------------------------------------------
    wire adc_rst;   // synchronized active-high reset for adc_clk domain
    wire sys_rst;   // synchronized active-high reset for sys_clk domain

    reset_synchronizer u_rst_adc (
        .clk_i (adc_clk_i),
        .rst_ni(rst_ni),
        .rst_o (adc_rst)
    );

    reset_synchronizer u_rst_sys (
        .clk_i (sys_clk_i),
        .rst_ni(rst_ni),
        .rst_o (sys_rst)
    );

    // -----------------------------------------------------------
    // Internal signals
    // -----------------------------------------------------------
    // Packer -> FIFO (adc_clk domain)
    wire        pkt_valid;
    wire [191:0] pkt_data;

    // FIFO -> Serializer (sys_clk domain)
    wire [191:0] fifo_rdata;
    wire         fifo_empty;
    wire         fifo_rd_en;

    // -----------------------------------------------------------
    // ADC sample packer (adc_clk domain)
    // -----------------------------------------------------------
    adc_sample_packer u_packer (
        .adc_clk_i   (adc_clk_i),
        .adc_rst_i   (adc_rst),
        .adc_valid_i (adc_valid_i),
        .adc_data_i  (adc_data_i),
        .pkt_valid_o (pkt_valid),
        .pkt_data_o  (pkt_data)
    );

    // -----------------------------------------------------------
    // Async FIFO (CDC crossing: adc_clk -> sys_clk)
    // -----------------------------------------------------------
    async_fifo #(
        .DATA_WIDTH(192),
        .DEPTH     (8)
    ) u_fifo (
        .wr_clk_i (adc_clk_i),
        .wr_rst_i (adc_rst),
        .wr_en_i  (pkt_valid),
        .wdata_i  (pkt_data),
        .full_o   (),
        .rd_clk_i (sys_clk_i),
        .rd_rst_i (sys_rst),
        .rd_en_i  (fifo_rd_en),
        .rdata_o  (fifo_rdata),
        .empty_o  (fifo_empty)
    );

    // -----------------------------------------------------------
    // AXI-Stream serializer (sys_clk domain)
    // -----------------------------------------------------------
    axis_serializer u_serializer (
        .sys_clk_i       (sys_clk_i),
        .sys_rst_i       (sys_rst),
        .fifo_data_i     (fifo_rdata),
        .fifo_empty_i    (fifo_empty),
        .fifo_rd_en_o    (fifo_rd_en),
        .m_axis_tvalid_o (m_axis_tvalid_o),
        .m_axis_tready_i (m_axis_tready_i),
        .m_axis_tdata_o  (m_axis_tdata_o),
        .m_axis_tlast_o  (m_axis_tlast_o)
    );

endmodule

`default_nettype wire
