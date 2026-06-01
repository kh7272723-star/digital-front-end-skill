`default_nettype none
// ============================================================================
// nvme_read_engine — NVM Read → AXI Write Engine
//
// NBA-aware design (per nba-ordering-guide.md):
//   w_last_o  = combinational assign from w_beat_q           (Trap 1)
//   w_data_o  = combinational assign from FIFO rdata         (Trap 2)
//   FIFO wr   = nvm_rvalid_i (not gated by consumer)         (Trap 6)
//   Beat ctr  = gated on valid && ready                      (Trap 4)
//   Offset    = advances on issue, not arrival               (Trap 5)
//   WVALID    = w_active_q only                              (P12)
//   AW decoupled from FIFO state                             (user spec)
// ============================================================================

module nvme_read_engine #(
    parameter AXI_DATA_W      = 64,
    parameter AXI_MAX_BURST   = 256,
    parameter LBA_SIZE        = 512,
    parameter DATA_FIFO_DEPTH = 64
) (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         start_i,
    output wire         done_o,
    input  wire [63:0]  slba_i,
    input  wire [31:0]  total_bytes_i,
    // Page input
    input  wire [63:0]  page_addr_i,
    input  wire [16:0]  page_bytes_i,
    input  wire         page_valid_i,
    output wire         page_ready_o,
    output wire         page_done_o,
    // NVM SRAM
    output wire [63:0]  nvm_addr_o,
    output wire         nvm_rd_en_o,
    input  wire [63:0]  nvm_rdata_i,
    input  wire         nvm_rvalid_i,
    output wire         nvm_rready_o,
    // AXI AW
    output wire         axi_aw_valid_o,
    input  wire         axi_aw_ready_i,
    output wire [63:0]  axi_aw_addr_o,
    output wire [7:0]   axi_aw_len_o,
    // AXI W
    output wire         axi_w_valid_o,
    input  wire         axi_w_ready_i,
    output wire [63:0]  axi_w_data_o,
    output wire [7:0]   axi_w_strb_o,
    output wire         axi_w_last_o,
    // AXI B
    input  wire         axi_b_valid_i,
    output wire         axi_b_ready_o,
    input  wire [1:0]   axi_b_resp_i
);

    localparam F_AW = $clog2(DATA_FIFO_DEPTH);

    // ==================================================================
    // FWFT Data FIFO
    // ==================================================================
    reg [63:0]                   fifo_mem [0:DATA_FIFO_DEPTH-1];
    reg [F_AW-1:0]               fifo_wptr_q, fifo_rptr_q;
    reg [F_AW:0]                 fifo_cnt_q;

    wire fifo_wr    = nvm_rvalid_i;                             // Trap 6
    wire fifo_full  = (fifo_cnt_q == DATA_FIFO_DEPTH);
    wire fifo_empty = (fifo_cnt_q == 0);
    wire fifo_rd    = axi_w_valid_o && axi_w_ready_i;

    always @(posedge clk_i) begin
        if (fifo_wr && !fifo_full)
            fifo_mem[fifo_wptr_q] <= nvm_rdata_i;
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            fifo_wptr_q <= 0; fifo_rptr_q <= 0; fifo_cnt_q <= 0;
        end else begin
            if (fifo_wr && !fifo_full)   fifo_wptr_q <= fifo_wptr_q + 1'b1;
            if (fifo_rd)                 fifo_rptr_q <= fifo_rptr_q + 1'b1;
            case ({fifo_wr && !fifo_full, fifo_rd})
                2'b10: fifo_cnt_q <= fifo_cnt_q + 1'b1;
                2'b01: fifo_cnt_q <= fifo_cnt_q - 1'b1;
                default: ;
            endcase
        end
    end

    wire [63:0] fifo_rdata = fifo_mem[fifo_rptr_q];            // Trap 2: combinational

    // ==================================================================
    // NVM Read Controller
    // ==================================================================
    reg [31:0]  nvm_offset_q;
    reg [31:0]  nvm_total_q;
    reg [16:0]  page_remain_q;
    reg [63:0]  page_host_addr_q;
    reg         page_live_q;
    reg         page_done_q;
    reg         all_pages_q;

    wire nvm_issue = page_live_q && (page_remain_q > 17'd0)
                  && (fifo_cnt_q < DATA_FIFO_DEPTH);           // fill FIFO fully

    assign nvm_rd_en_o  = nvm_issue;
    assign nvm_addr_o   = slba_i * LBA_SIZE + nvm_offset_q;
    assign nvm_rready_o = 1'b1;
    assign page_ready_o = !page_live_q || page_done_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            nvm_offset_q    <= 0;  nvm_total_q   <= 0;
            page_remain_q   <= 0;  page_host_addr_q <= 0;
            page_live_q     <= 0;  page_done_q   <= 0;
            all_pages_q     <= 0;
        end else begin
            if (start_i && !page_live_q) begin   // only on cold start
                nvm_total_q <= total_bytes_i;  nvm_offset_q <= 0;
                page_done_q <= 0;
                all_pages_q <= 0;
            end

            if (page_valid_i && page_ready_o) begin
                page_live_q       <= 1;
                page_host_addr_q  <= page_addr_i;
                page_remain_q     <= page_bytes_i;
                page_done_q       <= 0;
            end

            if (nvm_issue) begin
                nvm_offset_q  <= nvm_offset_q + 32'd8;       // Trap 5
                page_remain_q <= page_remain_q - 17'd8;
                if (page_remain_q <= 17'd8)                  // last read issued
                    page_done_q <= 1;
            end

            if (page_done_o) begin                             // page fully drained
                page_live_q  <= 0;
                all_pages_q  <= 1;
            end
        end
    end

    // ==================================================================
    // AW Controller — beat-count-driven, decoupled from FIFO
    // ==================================================================
    reg         aw_vld_q;
    reg [63:0]  aw_addr_q;
    reg [7:0]   aw_len_q;
    reg [15:0]  aw_left_q;          // beats remaining for page

    assign axi_aw_valid_o = aw_vld_q && (fifo_cnt_q > aw_len_q);  // gate on FIFO pre-fill
    assign axi_aw_addr_o  = aw_addr_q;
    assign axi_aw_len_o   = aw_len_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_vld_q <= 0; aw_addr_q <= 0; aw_len_q <= 0; aw_left_q <= 0;
        end else begin
            if (page_valid_i && page_ready_o) begin
                aw_addr_q <= page_addr_i;
                aw_left_q <= page_bytes_i[16:3];             // bytes → beats
                aw_vld_q  <= 1;
                aw_len_q  <= (page_bytes_i[16:3] > AXI_MAX_BURST)
                           ? (AXI_MAX_BURST - 1) : (page_bytes_i[16:3] - 1);
            end

            if (aw_vld_q && axi_aw_ready_i) begin
                aw_addr_q <= aw_addr_q + ({56'd0, aw_len_q} + 1) * 8;
                if (aw_left_q > ({8'd0, aw_len_q} + 1)) begin
                    aw_left_q <= aw_left_q - ({8'd0, aw_len_q} + 1);
                    aw_len_q  <= (aw_left_q - ({8'd0, aw_len_q} + 1) > AXI_MAX_BURST)
                               ? (AXI_MAX_BURST - 1)
                               : (aw_left_q - ({8'd0, aw_len_q} + 1) - 1);
                end else begin
                    aw_left_q <= 0;
                    aw_vld_q  <= 0;
                end
            end
        end
    end

    // ==================================================================
    // W Controller
    // ==================================================================
    reg        w_act_q;
    reg [7:0]  w_beat_q;
    reg [7:0]  w_blen_q;

    assign axi_w_valid_o = w_act_q;                          // P12
    assign axi_w_data_o  = fifo_rdata;                       // Trap 2
    assign axi_w_strb_o  = 8'hFF;
    assign axi_w_last_o  = w_act_q && (w_beat_q == w_blen_q);// Trap 1

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            w_act_q <= 0; w_beat_q <= 0; w_blen_q <= 0;
        end else begin
            // Start burst when AW actually goes out (FIFO gate in axi_aw_valid_o)
            if (axi_aw_valid_o && axi_aw_ready_i && !w_act_q) begin
                w_act_q  <= 1;
                w_beat_q <= 0;
                w_blen_q <= aw_len_q;
            end

            // Beat advance
            if (w_act_q && axi_w_valid_o && axi_w_ready_i) begin // Trap 4
                if (w_beat_q == w_blen_q)
                    w_act_q <= 0;
                else
                    w_beat_q <= w_beat_q + 1'b1;
            end
        end
    end

    // ==================================================================
    // B Controller
    // ==================================================================
    reg [7:0]  b_cnt_q;

    assign axi_b_ready_o = 1'b1;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            b_cnt_q <= 0;
        end else begin
            if (start_i) b_cnt_q <= 0;

            if (axi_aw_valid_o && axi_aw_ready_i)   // gate: only when AW actually issued
                b_cnt_q <= b_cnt_q + 1'b1;
            if (axi_b_valid_i)
                b_cnt_q <= b_cnt_q - 1'b1;
        end
    end

    assign page_done_o = page_done_q && !w_act_q && (b_cnt_q == 0);
    assign done_o      = all_pages_q && !w_act_q && (b_cnt_q == 0);

endmodule
`default_nettype wire
