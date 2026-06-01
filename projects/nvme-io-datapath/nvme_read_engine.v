// =============================================================================
// nvme_read_engine — NVM Read Data Path
// =============================================================================
// AW: fires independently from page info (no FIFO coupling)
// W:  WVALID = w_active_q && !fifo_empty (data-available gate)
// FIFO: pipeline depth only (64 entries), independent of transfer size
// =============================================================================

`default_nettype none

module nvme_read_engine #(
    parameter AXI_DATA_W    = 64,
    parameter AXI_ADDR_W    = 64,
    parameter AXI_MAX_BURST = 256,
    parameter LBA_SIZE      = 512,
    parameter FIFO_DEPTH    = 64,      // pipeline depth, not page-size dependent
    parameter FIFO_ADDR_W   = 6        // $clog2(64)
) (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         start_i,
    output reg          done_o,
    output reg          error_o,
    input  wire [63:0]  slba_i,
    input  wire [31:0]  total_bytes_i,
    input  wire [63:0]  page_addr_i,
    input  wire [15:0]  page_bytes_i,
    input  wire         page_valid_i,
    output reg          page_ready_o,
    output reg          page_done_o,
    output wire [63:0]  nvm_addr_o,
    output wire         nvm_rd_en_o,
    input  wire [63:0]  nvm_rdata_i,
    input  wire         nvm_rvalid_i,
    output reg          axi_aw_valid_o,
    input  wire         axi_aw_ready_i,
    output reg  [63:0]  axi_aw_addr_o,
    output reg  [7:0]   axi_aw_len_o,
    output reg          axi_w_valid_o,
    input  wire         axi_w_ready_i,
    output wire [63:0]  axi_w_data_o,
    output wire [7:0]   axi_w_strb_o,
    output wire         axi_w_last_o,
    input  wire         axi_b_valid_i,
    output wire         axi_b_ready_o,
    input  wire [1:0]   axi_b_resp_i
);

    // =========================================================================
    // FWFT FIFO — pipeline depth only (F1 compliance)
    // =========================================================================
    reg  [63:0] fifo_mem [0:FIFO_DEPTH-1];
    reg  [FIFO_ADDR_W-1:0] fifo_wr_ptr_q;
    reg  [FIFO_ADDR_W-1:0] fifo_rd_ptr_q;
    reg  [FIFO_ADDR_W:0]   fifo_count_q;

    wire fifo_empty;
    wire fifo_full;
    wire [63:0] fifo_rdata;

    assign fifo_empty = (fifo_count_q == 0);
    assign fifo_full  = (fifo_count_q == FIFO_DEPTH);
    assign fifo_rdata = fifo_mem[fifo_rd_ptr_q];      // FWFT: combinational read

    wire fifo_wr_en;
    assign fifo_wr_en = nvm_rvalid_i;                  // NVM data arrival

    wire w_handshake;
    assign w_handshake = axi_w_valid_o && axi_w_ready_i;

    wire fifo_rd_en;
    assign fifo_rd_en = w_handshake;

    // =========================================================================
    // NVM read interface
    // =========================================================================
    assign nvm_addr_o  = nvm_offset_q;                 // byte offset from SLBA
    assign nvm_rd_en_o = page_active_q && (page_remain_q > 0) && !fifo_full;

    reg [31:0] nvm_offset_q;
    reg [31:0] total_remaining_q;
    reg [15:0] page_remain_q;
    reg        page_active_q;

    wire page_nvm_done;
    assign page_nvm_done = page_active_q && (page_remain_q == 0);

    // =========================================================================
    // Cross-block event wires (combinational pulses)
    // =========================================================================
    wire page_accept;
    assign page_accept = page_valid_i && page_ready_o;

    wire w_last_pulse;
    assign w_last_pulse = w_active_q && w_handshake && (w_beat_q == w_burst_len_q);

    wire b_fire_pulse;
    assign b_fire_pulse = axi_b_valid_i && axi_b_ready_o;

    // =========================================================================
    // AW: burst parameters computed combinationally from page state
    // =========================================================================
    wire [7:0]  aw_burst_len;
    wire [8:0]  aw_burst_beats;
    wire [63:0] aw_burst_addr;

    // DP4-compliant burst length computation — purely combinational
    reg  [11:0] aw_bytes_to_boundary;
    reg  [8:0]  aw_total_beats;
    reg  [8:0]  aw_beats_to_boundary;
    reg  [8:0]  aw_requested_beats;

    always @(*) begin
        aw_bytes_to_boundary = 13'h1000 - {1'b0, aw_page_offset_q};
        aw_beats_to_boundary = {1'b0, aw_bytes_to_boundary[11:3]};
        aw_total_beats       = (aw_page_remain_q + 15'd7) >> 3;

        if (aw_total_beats < aw_beats_to_boundary)
            aw_requested_beats = aw_total_beats;
        else
            aw_requested_beats = aw_beats_to_boundary;
    end

    assign aw_burst_beats = (aw_total_beats <= 9'd255) ? aw_total_beats
                                                       : aw_requested_beats;
    assign aw_burst_len   = aw_burst_beats[7:0] - 8'd1;
    assign aw_burst_addr  = (aw_page_base_q & ~64'hFFF) | {52'd0, aw_page_offset_q};

    // =========================================================================
    // AW page tracking registers
    // =========================================================================
    reg        aw_active_q;
    reg [63:0] aw_page_base_q;
    reg [15:0] aw_page_remain_q;
    reg [11:0] aw_page_offset_q;

    // =========================================================================
    // W controller registers
    // =========================================================================
    reg        w_active_q;
    reg [7:0]  w_beat_q;
    reg [7:0]  w_burst_len_q;
    reg [63:0] w_data_pipe_q;

    assign axi_w_data_o = w_data_pipe_q;                 // combinational from pipe
    assign axi_w_last_o = w_active_q && (w_beat_q == w_burst_len_q);
    assign axi_w_strb_o = 8'hFF;

    // =========================================================================
    // B outstanding counter
    // =========================================================================
    reg [7:0]  b_outstanding_q;
    assign axi_b_ready_o = 1'b1;

    // =========================================================================
    // Sequential blocks — grouped by function (C20)
    // Each register written in exactly ONE block (E1)
    // All branches have explicit hold (C19)
    // =========================================================================

    // ── (1) FIFO write pointer + memory write ──
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            fifo_wr_ptr_q <= 0;
        end else if (fifo_wr_en) begin
            fifo_mem[fifo_wr_ptr_q] <= nvm_rdata_i;
            fifo_wr_ptr_q <= fifo_wr_ptr_q + 1;
        end else begin
            fifo_wr_ptr_q <= fifo_wr_ptr_q;
        end
    end

    // ── (2) FIFO read pointer ──
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            fifo_rd_ptr_q <= 0;
        end else if (fifo_rd_en) begin
            fifo_rd_ptr_q <= fifo_rd_ptr_q + 1;
        end else begin
            fifo_rd_ptr_q <= fifo_rd_ptr_q;
        end
    end

    // ── (3) FIFO occupancy ──
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            fifo_count_q <= 0;
        end else begin
            case ({fifo_wr_en, fifo_rd_en})
                2'b10: fifo_count_q <= fifo_count_q + 1;
                2'b01: fifo_count_q <= fifo_count_q - 1;
                default: fifo_count_q <= fifo_count_q;
            endcase
        end
    end

    // ── (4) NVM offset + page tracking ──
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            nvm_offset_q      <= 0;
            total_remaining_q <= 0;
            page_remain_q     <= 0;
            page_active_q     <= 1'b0;
        end else begin
            if (start_i) begin
                nvm_offset_q      <= 0;
                total_remaining_q <= total_bytes_i;
                page_remain_q     <= 0;
                page_active_q     <= 1'b0;
            end else if (page_accept) begin
                page_active_q <= 1'b1;
                page_remain_q <= page_bytes_i;
            end else if (page_active_q && page_nvm_done && aw_page_remain_q == 0
                         && !aw_active_q && b_outstanding_q == 0 && !w_active_q) begin
                page_active_q <= 1'b0;
            end else if (nvm_rd_en_o) begin
                nvm_offset_q      <= nvm_offset_q + 8;
                page_remain_q     <= page_remain_q - 8;
                total_remaining_q <= total_remaining_q - 8;
            end else begin
                nvm_offset_q      <= nvm_offset_q;
                total_remaining_q <= total_remaining_q;
                page_remain_q     <= page_remain_q;
                page_active_q     <= page_active_q;
            end
        end
    end

    // ── (5) Page handshake: ready / done ──
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            page_ready_o <= 1'b0;
            page_done_o  <= 1'b0;
        end else begin
            page_done_o <= 1'b0;
            if (start_i) begin
                page_ready_o <= 1'b1;
            end else if (page_accept) begin
                page_ready_o <= 1'b0;
            end else if (page_active_q && page_nvm_done && aw_page_remain_q == 0
                         && !aw_active_q && b_outstanding_q == 0 && !w_active_q) begin
                page_done_o  <= 1'b1;
                page_ready_o <= 1'b1;
            end else begin
                page_ready_o <= page_ready_o;
            end
        end
    end

    // ── (6) AW page state: base / remain / offset ──
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_page_base_q   <= 0;
            aw_page_remain_q <= 0;
            aw_page_offset_q <= 0;
        end else begin
            if (page_accept) begin
                aw_page_base_q   <= page_addr_i;
                aw_page_remain_q <= page_bytes_i;
                aw_page_offset_q <= page_addr_i[11:0];
            end else if (w_last_pulse) begin
                aw_page_offset_q <= aw_page_offset_q
                    + (w_burst_len_q + 9'd1) * 12'd8;
                aw_page_remain_q <= aw_page_remain_q
                    - (w_burst_len_q + 9'd1) * 12'd8;
            end else begin
                aw_page_base_q   <= aw_page_base_q;
                aw_page_remain_q <= aw_page_remain_q;
                aw_page_offset_q <= aw_page_offset_q;
            end
        end
    end

    // ── (7) AW controller: fires from page info alone (no FIFO coupling) ──
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_active_q    <= 1'b0;
            axi_aw_valid_o <= 1'b0;
            axi_aw_addr_o  <= 0;
            axi_aw_len_o   <= 0;
        end else begin
            if (start_i) begin
                aw_active_q    <= 1'b0;
                axi_aw_valid_o <= 1'b0;
            end else begin
                // Issue AW when: page active, no AW in flight, bytes remain
                if (page_active_q && !aw_active_q && !axi_aw_valid_o
                    && aw_page_remain_q > 0) begin
                    axi_aw_valid_o <= 1'b1;
                    axi_aw_addr_o  <= aw_burst_addr;
                    axi_aw_len_o   <= aw_burst_len;
                    aw_active_q    <= 1'b1;
                end
                // AW handshake complete → deassert valid
                if (axi_aw_valid_o && axi_aw_ready_i) begin
                    axi_aw_valid_o <= 1'b0;
                end
                // WLAST clears AW active → ready for next burst
                if (w_last_pulse) begin
                    aw_active_q <= 1'b0;
                end
            end
        end
    end

    // ── (8) W controller: WVALID = w_active_q && !fifo_empty ──
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            w_active_q    <= 1'b0;
            w_beat_q      <= 0;
            w_burst_len_q <= 0;
            axi_w_valid_o <= 1'b0;
            w_data_pipe_q <= 0;
        end else if (start_i) begin
            w_active_q    <= 1'b0;
            axi_w_valid_o <= 1'b0;
        end else begin
            // Start W after AW sent, pre-load first beat from FIFO
            if (aw_active_q && !w_active_q && !axi_aw_valid_o) begin
                w_active_q    <= 1'b1;
                w_beat_q      <= 0;
                w_burst_len_q <= axi_aw_len_o;
                w_data_pipe_q <= fifo_rdata;
            end
            // Pre-fetch next FIFO entry on each handshake (except last beat)
            if (w_active_q && w_handshake && w_beat_q != w_burst_len_q) begin
                w_data_pipe_q <= fifo_mem[fifo_rd_ptr_q + 1];
            end
            // WVALID = w_active_q, gated by data availability
            if (w_active_q) begin
                if (!fifo_empty) begin
                    axi_w_valid_o <= 1'b1;
                end else begin
                    axi_w_valid_o <= 1'b0;
                end
                if (w_handshake) begin
                    if (w_beat_q == w_burst_len_q) begin
                        w_active_q <= 1'b0;
                    end else begin
                        w_beat_q <= w_beat_q + 8'd1;
                    end
                end
            end else begin
                axi_w_valid_o <= 1'b0;
            end
        end
    end

    // ── (9) B outstanding counter ──
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            b_outstanding_q <= 0;
        end else if (start_i) begin
            b_outstanding_q <= 0;
        end else if (w_last_pulse && b_fire_pulse) begin
            b_outstanding_q <= b_outstanding_q;
        end else if (w_last_pulse) begin
            b_outstanding_q <= b_outstanding_q + 1;
        end else if (b_fire_pulse) begin
            b_outstanding_q <= b_outstanding_q - 1;
        end else begin
            b_outstanding_q <= b_outstanding_q;
        end
    end

    // ── (10) Done / Error ──
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            done_o  <= 1'b0;
            error_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (b_fire_pulse && axi_b_resp_i != 2'b00) begin
                error_o <= 1'b1;
            end
            if (page_active_q && page_nvm_done && aw_page_remain_q == 0
                && !aw_active_q && b_outstanding_q == 0 && !w_active_q
                && total_remaining_q == 0) begin
                done_o <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
