`default_nettype none

// ADC sample packer: accumulates 12-bit samples into 192-bit blocks.
//
// Clock domain: adc_clk
// Reset: adc_rst (active-high, synchronized to adc_clk)
//
// Adc sample valid on rising edge. Every 16 valid samples forms one
// block (192 bits = 16 * 12). The packed block is presented on
// pkt_data_o with a single-cycle pkt_valid_o pulse.
//
// Sample storage: shift register. New sample goes to bits [11:0],
// existing samples shift left by 12 bits.
//
// Flow:
//   Cycle N:    adc_valid_i=1 with sample_cnt_q=15 (16th sample)
//               pack_buf_q updated with all 16 samples (NBA)
//               fifo_wr_en_q = 1 scheduled
//   Cycle N+1:  fifo_wr_en_q=1, fifo_wdata_q holds all 16 samples
//               (captured combinationally on cycle N)
//               async_fifo captures data on this rising edge

module adc_sample_packer (
    input  wire          adc_clk_i,
    input  wire          adc_rst_i,
    // ADC sample input
    input  wire          adc_valid_i,
    input  wire [11:0]   adc_data_i,
    // Packed output to async FIFO
    output wire          pkt_valid_o,
    output wire [191:0]  pkt_data_o
);

    // 16-sample block accumulation: 12-bit shift register
    reg [3:0]   sample_cnt_q;
    reg [191:0] pack_buf_q;

    // Registered FIFO write interface
    reg         fifo_wr_en_q;
    reg [191:0] fifo_wdata_q;

    // Write enable: pulse when 16th sample arrives
    // Capture the "post-update" buffer value combinationally:
    // pack_buf_q (15 samples) concatenated with current adc_data_i (16th sample).
    // This avoids the NBA read-before-write issue on the shift register.
    wire block_complete = adc_valid_i && (sample_cnt_q == 4'd15);
    wire [191:0] pack_next = {pack_buf_q[179:0], adc_data_i};

    always @(posedge adc_clk_i) begin
        if (adc_rst_i) begin
            sample_cnt_q <= 4'd0;
            pack_buf_q   <= 192'd0;
            fifo_wr_en_q <= 1'b0;
            fifo_wdata_q <= 192'd0;
        end else begin
            // Default: wr_en is a pulse
            fifo_wr_en_q <= 1'b0;

            if (adc_valid_i) begin
                // Shift in new sample (LSB-first)
                pack_buf_q <= {pack_buf_q[179:0], adc_data_i};

                if (block_complete) begin
                    sample_cnt_q <= 4'd0;
                    // Capture the full block (uses current register + current input)
                    fifo_wdata_q <= pack_next;
                    fifo_wr_en_q <= 1'b1;
                end else begin
                    sample_cnt_q <= sample_cnt_q + 4'd1;
                end
            end
        end
    end

    assign pkt_valid_o = fifo_wr_en_q;
    assign pkt_data_o  = fifo_wdata_q;

endmodule

`default_nettype wire
