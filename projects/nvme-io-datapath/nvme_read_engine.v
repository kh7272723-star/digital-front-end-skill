`default_nettype none
// nvme_read_engine — NVM Read → AXI Write Engine
// Pages processed immediately on arrival. Done = all accepted pages drained.
module nvme_read_engine #(
    parameter AXI_MAX_BURST   = 64,
    parameter LBA_SIZE        = 512,
    parameter DATA_FIFO_DEPTH = 64
) (
    input  wire         clk_i, input  wire         rst_ni,
    input  wire         start_i, output wire         done_o,
    input  wire [63:0]  slba_i,  input  wire [31:0]  total_bytes_i,
    input  wire [63:0]  page_addr_i,  input  wire [16:0]  page_bytes_i,
    input  wire         page_valid_i, output wire         page_ready_o,
    output wire         page_done_o,
    output wire [63:0]  nvm_addr_o,   output wire         nvm_rd_en_o,
    input  wire [63:0]  nvm_rdata_i,  input  wire         nvm_rvalid_i,
    output wire         nvm_rready_o,
    output wire         axi_aw_valid_o, input  wire         axi_aw_ready_i,
    output wire [63:0]  axi_aw_addr_o,  output wire [7:0]   axi_aw_len_o,
    output wire         axi_w_valid_o,  input  wire         axi_w_ready_i,
    output wire [63:0]  axi_w_data_o,   output wire [7:0]   axi_w_strb_o,
    output wire         axi_w_last_o,
    input  wire         axi_b_valid_i,  output wire         axi_b_ready_o,
    input  wire [1:0]   axi_b_resp_i
);
    localparam F_AW = $clog2(DATA_FIFO_DEPTH);

    // Page accounting (race-free: separate in/out counters)
    reg [7:0]  page_in_q, page_out_q;
    assign page_ready_o = 1'b1;  // always accept, no backpressure

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin page_in_q <= 0; page_out_q <= 0; end
        else begin
            if (page_valid_i && page_ready_o) page_in_q <= page_in_q + 1'b1;
            if (page_done_o)      page_out_q <= page_out_q + 1'b1;
        end
    end

    // ==================================================================
    // FWFT FIFO
    // ==================================================================
    reg [63:0]     fifo_mem [0:DATA_FIFO_DEPTH-1];
    reg [F_AW-1:0] fifo_wptr_q, fifo_rptr_q;
    reg [F_AW:0]   fifo_cnt_q;
    wire fifo_wr = nvm_rvalid_i;
    wire fifo_rd = axi_w_valid_o && axi_w_ready_i;

    always @(posedge clk_i) begin
        if (fifo_wr && (fifo_cnt_q < DATA_FIFO_DEPTH))
            fifo_mem[fifo_wptr_q] <= nvm_rdata_i;
    end
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin fifo_wptr_q <= 0; fifo_rptr_q <= 0; fifo_cnt_q <= 0; end
        else begin
            if (fifo_wr && (fifo_cnt_q < DATA_FIFO_DEPTH)) fifo_wptr_q <= fifo_wptr_q + 1'b1;
            if (fifo_rd)                                     fifo_rptr_q <= fifo_rptr_q + 1'b1;
            case ({fifo_wr && (fifo_cnt_q < DATA_FIFO_DEPTH), fifo_rd})
                2'b10: fifo_cnt_q <= fifo_cnt_q + 1'b1;
                2'b01: fifo_cnt_q <= fifo_cnt_q - 1'b1;
                default: ;
            endcase
        end
    end
    wire [63:0] fifo_rdata = fifo_mem[fifo_rptr_q];

    // ==================================================================
    // NVM Read — processes current page, no page buffer needed
    // ==================================================================
    reg [31:0]  nvm_offset_q;
    reg [16:0]  page_remain_q;
    reg [63:0]  page_host_q;
    reg         page_live_q;
    reg         page_nvm_done_q;
    reg         page_draining_q;

    wire nvm_issue = page_live_q && (page_remain_q > 0) && (fifo_cnt_q < DATA_FIFO_DEPTH);
    assign nvm_rd_en_o  = nvm_issue;
    assign nvm_addr_o   = slba_i * LBA_SIZE + nvm_offset_q;
    assign nvm_rready_o = 1'b1;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            nvm_offset_q <= 0; page_remain_q <= 0; page_host_q <= 0;
            page_live_q <= 0; page_nvm_done_q <= 0; page_draining_q <= 0;
        end else begin
            if (start_i) nvm_offset_q <= 0;

            // Page acceptance: start processing immediately
            if (page_valid_i && !page_live_q) begin
                page_live_q     <= 1;
                page_host_q     <= page_addr_i;
                page_remain_q   <= page_bytes_i;
                page_nvm_done_q <= 0;
                page_draining_q <= 0;
            end

            if (nvm_issue) begin
                nvm_offset_q  <= nvm_offset_q + 32'd8;
                page_remain_q <= page_remain_q - 17'd8;
                if (page_remain_q <= 17'd8) page_nvm_done_q <= 1;
            end

            if (page_nvm_done_q && !page_draining_q) page_draining_q <= 1;

            // Page W/B drain complete
            if (page_draining_q && !w_act_q && (b_cnt_q == 0)) begin
                page_live_q     <= 0;
                page_draining_q <= 0;
            end
        end
    end

    wire page_drain_done = page_draining_q && !w_act_q && (b_cnt_q == 0);
    assign page_done_o = page_drain_done;
    // Done: last page fully drained AND all pages accounted
    wire all_pages_match = (page_in_q == page_out_q) && (page_in_q > 0);
    assign done_o = page_drain_done && all_pages_match;

    // ==================================================================
    // AW Controller
    // ==================================================================
    reg aw_vld_q, w_act_q;
    reg [63:0] aw_addr_q;
    reg [7:0]  aw_len_q, w_beat_q, w_blen_q;
    reg [15:0] aw_left_q;

    assign axi_aw_valid_o = aw_vld_q && (fifo_cnt_q > aw_len_q) && !w_act_q;
    assign axi_aw_addr_o  = aw_addr_q;
    assign axi_aw_len_o   = aw_len_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_vld_q <= 0; aw_addr_q <= 0; aw_len_q <= 0; aw_left_q <= 0;
        end else begin
            if (page_valid_i && !page_live_q) begin
                aw_addr_q <= page_addr_i;
                aw_left_q <= page_bytes_i[16:3];
                aw_vld_q  <= 1;
                aw_len_q  <= (page_bytes_i[16:3] > AXI_MAX_BURST) ? (AXI_MAX_BURST - 1)
                           : (page_bytes_i[16:3] - 1);
            end
            if (axi_aw_valid_o && axi_aw_ready_i) begin
                aw_addr_q <= aw_addr_q + ({56'd0, aw_len_q} + 1) * 8;
                if (aw_left_q > ({8'd0, aw_len_q} + 1)) begin
                    aw_left_q <= aw_left_q - ({8'd0, aw_len_q} + 1);
                    aw_len_q  <= (aw_left_q - ({8'd0, aw_len_q} + 1) > AXI_MAX_BURST)
                               ? (AXI_MAX_BURST - 1) : (aw_left_q - ({8'd0, aw_len_q} + 1) - 1);
                end else begin aw_left_q <= 0; aw_vld_q <= 0; end
            end
        end
    end

    // ==================================================================
    // W Controller
    // ==================================================================
    assign axi_w_valid_o = w_act_q;
    assign axi_w_data_o  = fifo_rdata;
    assign axi_w_strb_o  = 8'hFF;
    assign axi_w_last_o  = w_act_q && (w_beat_q == w_blen_q);

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin w_act_q <= 0; w_beat_q <= 0; w_blen_q <= 0; end
        else begin
            if (axi_aw_valid_o && axi_aw_ready_i && !w_act_q) begin
                w_act_q <= 1; w_beat_q <= 0; w_blen_q <= aw_len_q;
            end
            if (w_act_q && axi_w_valid_o && axi_w_ready_i) begin
                if (w_beat_q == w_blen_q) w_act_q <= 0;
                else                       w_beat_q <= w_beat_q + 1'b1;
            end
        end
    end

    // ==================================================================
    // B Controller
    // ==================================================================
    reg [7:0] b_cnt_q;
    assign axi_b_ready_o = 1'b1;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) b_cnt_q <= 0;
        else begin
            if (axi_aw_valid_o && axi_aw_ready_i) b_cnt_q <= b_cnt_q + 1'b1;
            if (axi_b_valid_i)                     b_cnt_q <= b_cnt_q - 1'b1;
        end
    end
endmodule
`default_nettype wire
