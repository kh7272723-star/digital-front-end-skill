// =============================================================================
// nvme_prp_walker — PRP traversal engine
// =============================================================================
//
// Implements NVMe Base Spec 2.3 §4.3 PRP traversal algorithm in hardware.
// Given PRP1, PRP2, and transfer_bytes, emits a sequence of {page_addr,
// page_bytes} for each host memory page involved in the transfer.
//
// FSM (8 states, 4-bit):
//
//   IDLE ──start──► CALC_FIRST ──► PAGE_TX ──(done)──► DONE
//                                    │  ▲
//                           (page_done)│  │(page_ready)
//                                    ▼  │
//                                NEXT_PAGE──(role=LIST)──► LIST_FETCH
//                                    │                        │
//                               (role=PAGE)              LIST_FETCH_R
//                                    │                        │
//                                    └──► PAGE_TX ◄── LIST_WALK
//
// =============================================================================

`default_nettype none

module nvme_prp_walker #(
    parameter PAGE_SIZE       = 4096,
    parameter AXI_DATA_W      = 64,
    parameter AXI_ADDR_W      = 64,
    parameter LIST_ENTRIES    = 512    // PAGE_SIZE / (AXI_DATA_W/8) = 4096/8
) (
    input  wire         clk_i,
    input  wire         rst_ni,

    // Control
    input  wire         start_i,
    output reg          done_o,
    output reg          error_o,
    output reg  [15:0] error_status_o,

    // PRP registers
    input  wire [63:0]  prp1_i,
    input  wire [63:0]  prp2_i,
    input  wire [31:0]  transfer_bytes_i,

    // Page output → read_engine
    output reg  [63:0]  page_addr_o,
    output reg  [15:0]  page_bytes_o,
    output reg          page_valid_o,
    input  wire         page_ready_i,
    input  wire         page_done_i,

    // AXI AR (PRP List fetch)
    output reg          list_ar_valid_o,
    input  wire         list_ar_ready_i,
    output reg  [63:0]  list_ar_addr_o,
    output wire [7:0]   list_ar_len_o,

    // AXI R (PRP List data)
    input  wire         list_r_valid_i,
    output wire         list_r_ready_o,
    input  wire [63:0]  list_r_data_i,
    input  wire         list_r_last_i
);

    // =========================================================================
    // State encoding
    // =========================================================================
    localparam [3:0] S_IDLE         = 4'd0;
    localparam [3:0] S_CALC_FIRST   = 4'd1;
    localparam [3:0] S_PAGE_TX      = 4'd2;
    localparam [3:0] S_NEXT_PAGE    = 4'd3;
    localparam [3:0] S_LIST_FETCH   = 4'd4;
    localparam [3:0] S_LIST_FETCH_R = 4'd5;
    localparam [3:0] S_LIST_WALK    = 4'd6;
    localparam [3:0] S_DONE         = 4'd7;

    // PRP2 role encoding
    localparam [1:0] ROLE_RESERVED = 2'd0;
    localparam [1:0] ROLE_PAGE     = 2'd1;
    localparam [1:0] ROLE_LIST     = 2'd2;

    // NVMe status codes
    localparam [15:0] NVME_SC_SUCCESS            = 16'h0000;
    localparam [15:0] NVME_SC_PRP_OFFSET_INVALID = 16'h0013;

    // =========================================================================
    // Registers (_q = current, _d = next)
    // =========================================================================
    reg [3:0]   state_q, state_d;
    reg [63:0]  current_addr_q, current_addr_d;
    reg [31:0]  bytes_remaining_q, bytes_remaining_d;
    reg [11:0]  page_offset_q, page_offset_d;
    reg         in_list_q, in_list_d;
    reg [63:0]  list_page_addr_q, list_page_addr_d;
    reg [9:0]   list_index_q, list_index_d;       // 0..511
    reg [1:0]   prp2_role_q, prp2_role_d;
    reg         error_q, error_d;

    // Page handshake: prevent re-accept same page
    reg         page_accepted_q, page_accepted_d;

    // Latched inputs (captured on start_i)
    reg [63:0]  prp1_latch_q,  prp1_latch_d;
    reg [63:0]  prp2_latch_q,  prp2_latch_d;
    reg [31:0]  transfer_bytes_latch_q, transfer_bytes_latch_d;

    // PRP list buffer (512 entries × 64-bit)
    reg [63:0]  list_buf [0:LIST_ENTRIES-1];
    reg [9:0]   list_buf_wr_idx_q, list_buf_wr_idx_d;
    reg         list_buf_wr_en;  // combinational → sequential write gate

    // =========================================================================
    // Derived values
    // =========================================================================
    assign list_ar_len_o = 8'd255;  // 256 beats per AXI burst for 4KB page
    assign list_r_ready_o = (state_q == S_LIST_FETCH_R);

    // =========================================================================
    // Combinational FSM
    // =========================================================================
    always @(*) begin
        // ── Defaults (no-change for most registers) ──
        state_d          = state_q;
        current_addr_d   = current_addr_q;
        bytes_remaining_d= bytes_remaining_q;
        page_offset_d    = page_offset_q;
        in_list_d        = in_list_q;
        list_page_addr_d = list_page_addr_q;
        list_index_d     = list_index_q;
        prp2_role_d      = prp2_role_q;
        error_d          = error_q;
        page_accepted_d  = page_accepted_q;
        list_buf_wr_idx_d= list_buf_wr_idx_q;
        prp1_latch_d     = prp1_latch_q;
        prp2_latch_d     = prp2_latch_q;
        transfer_bytes_latch_d = transfer_bytes_latch_q;
        list_buf_wr_en   = 1'b0;

        // ── Output defaults ──
        page_addr_o      = 64'd0;
        page_bytes_o     = 16'd0;
        page_valid_o     = 1'b0;
        list_ar_valid_o  = 1'b0;
        list_ar_addr_o   = 64'd0;
        done_o           = 1'b0;
        error_o          = 1'b0;
        error_status_o   = NVME_SC_SUCCESS;

        case (state_q)

            // ── IDLE: wait for start_i ──
            S_IDLE: begin
                if (start_i) begin
                    prp1_latch_d           = prp1_i;
                    prp2_latch_d           = prp2_i;
                    transfer_bytes_latch_d = transfer_bytes_i;
                    state_d = S_CALC_FIRST;
                end
            end

            // ── CALC_FIRST: compute first_page_capacity, decide PRP2 role ──
            S_CALC_FIRST: begin
                reg [12:0] first_page_capacity;

                first_page_capacity = PAGE_SIZE - prp1_latch_q[11:0];

                page_offset_d = prp1_latch_q[11:0];
                current_addr_d = prp1_latch_q;

                if (transfer_bytes_latch_q <= first_page_capacity) begin
                    prp2_role_d = ROLE_RESERVED;
                end else if (transfer_bytes_latch_q <= (first_page_capacity + PAGE_SIZE)) begin
                    prp2_role_d = ROLE_PAGE;
                end else begin
                    prp2_role_d = ROLE_LIST;
                end

                in_list_d = 1'b0;
                bytes_remaining_d = transfer_bytes_latch_q;
                state_d = S_PAGE_TX;
            end

            // ── PAGE_TX: output {page_addr, page_bytes} to read_engine ──
            S_PAGE_TX: begin
                reg [31:0] bytes_this_page;

                bytes_this_page = PAGE_SIZE - page_offset_q;
                if (bytes_this_page > bytes_remaining_q)
                    bytes_this_page = bytes_remaining_q;

                page_addr_o  = current_addr_q;
                page_bytes_o = bytes_this_page[15:0];

                // Handshake: assert valid until accepted, then wait for done
                if (!page_accepted_q) begin
                    page_valid_o = 1'b1;
                    if (page_ready_i) page_accepted_d = 1'b1;
                end

                if (page_done_i) begin
                    bytes_remaining_d = bytes_remaining_q - bytes_this_page;
                    page_accepted_d = 1'b0;  // clear for next page

                    if (bytes_remaining_q - bytes_this_page == 0) begin
                        state_d = S_DONE;
                    end else begin
                        page_offset_d = 12'd0;  // all subsequent pages start offset=0
                        state_d = S_NEXT_PAGE;
                    end
                end
            end

            // ── NEXT_PAGE: select next page source ──
            S_NEXT_PAGE: begin
                if (!in_list_q) begin
                    // Coming from first page (PRP1)
                    if (prp2_role_q == ROLE_PAGE) begin
                        // PRP2 = second memory page (Case B)
                        current_addr_d = {prp2_latch_q[63:12], 12'h000};
                        in_list_d = 1'b0;
                        state_d = S_PAGE_TX;
                    end else begin
                        // PRP2 = PRP List pointer (Case C)
                        in_list_d = 1'b1;
                        list_page_addr_d = prp2_latch_q;
                        list_index_d = 10'd0;
                        list_buf_wr_idx_d = 10'd0;
                        state_d = S_LIST_FETCH;
                    end
                end else begin
                    // Walking PRP list
                    if (list_index_q < 10'd511) begin
                        // Normal PRP entry: check offset == 0
                        if (list_buf[list_index_q][11:0] != 12'd0) begin
                            error_d = 1'b1;
                            error_o = 1'b1;
                            error_status_o = NVME_SC_PRP_OFFSET_INVALID;
                            state_d = S_DONE;
                        end else begin
                            current_addr_d = list_buf[list_index_q];
                            list_index_d = list_index_q + 10'd1;
                            state_d = S_PAGE_TX;
                        end
                    end else begin
                        // Entry 511: chain pointer or end
                        if (list_buf[511] == 64'd0) begin
                            // Chain broken: no more list pages but bytes remain
                            error_d = 1'b1;
                            error_o = 1'b1;
                            error_status_o = NVME_SC_PRP_OFFSET_INVALID;
                            state_d = S_DONE;
                        end else begin
                            list_page_addr_d = list_buf[511];
                            list_index_d = 10'd0;
                            list_buf_wr_idx_d = 10'd0;
                            state_d = S_LIST_FETCH;
                        end
                    end
                end
            end

            // ── LIST_FETCH: issue AXI AR for PRP list page ──
            S_LIST_FETCH: begin
                list_ar_valid_o = 1'b1;
                list_ar_addr_o  = list_page_addr_q;

                if (list_ar_ready_i) begin
                    state_d = S_LIST_FETCH_R;
                end
            end

            // ── LIST_FETCH_R: receive AXI R beats → list_buf ──
            S_LIST_FETCH_R: begin
                if (list_r_valid_i) begin
                    // Write list_buf via sequential block (list_buf_wr_en)
                    list_buf_wr_en = 1'b1;
                    list_buf_wr_idx_d = list_buf_wr_idx_q + 10'd1;

                    if (list_r_last_i) begin
                        state_d = S_LIST_WALK;
                    end
                end
            end

            // ── LIST_WALK: validate first entry of freshly-fetched list ──
            S_LIST_WALK: begin
                if (list_buf[list_index_q][11:0] != 12'd0) begin
                    error_d = 1'b1;
                    error_o = 1'b1;
                    error_status_o = NVME_SC_PRP_OFFSET_INVALID;
                    state_d = S_DONE;
                end else begin
                    current_addr_d = list_buf[list_index_q];
                    list_index_d = list_index_q + 10'd1;
                    state_d = S_PAGE_TX;
                end
            end

            // ── DONE: pulse done_o, return to IDLE ──
            S_DONE: begin
                done_o = 1'b1;
                state_d = S_IDLE;
            end

            default: state_d = S_IDLE;

        endcase
    end

    // =========================================================================
    // Sequential block
    // =========================================================================
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q           <= S_IDLE;
            current_addr_q    <= 64'd0;
            bytes_remaining_q <= 32'd0;
            page_offset_q     <= 12'd0;
            in_list_q         <= 1'b0;
            list_page_addr_q  <= 64'd0;
            list_index_q      <= 10'd0;
            prp2_role_q       <= ROLE_RESERVED;
            error_q           <= 1'b0;
            page_accepted_q   <= 1'b0;
            list_buf_wr_idx_q <= 10'd0;
            prp1_latch_q      <= 64'd0;
            prp2_latch_q      <= 64'd0;
            transfer_bytes_latch_q <= 32'd0;
        end else begin
            state_q           <= state_d;
            current_addr_q    <= current_addr_d;
            bytes_remaining_q <= bytes_remaining_d;
            page_offset_q     <= page_offset_d;
            in_list_q         <= in_list_d;
            list_page_addr_q  <= list_page_addr_d;
            list_index_q      <= list_index_d;
            prp2_role_q       <= prp2_role_d;
            error_q           <= error_d;
            page_accepted_q   <= page_accepted_d;
            list_buf_wr_idx_q <= list_buf_wr_idx_d;
            prp1_latch_q      <= prp1_latch_d;
            prp2_latch_q      <= prp2_latch_d;
            transfer_bytes_latch_q <= transfer_bytes_latch_d;

            // list_buf write (gated by combinational flag)
            if (list_buf_wr_en) begin
                list_buf[list_buf_wr_idx_q] <= list_r_data_i;
            end
        end
    end

endmodule

`default_nettype wire
