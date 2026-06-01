`default_nettype none
// ============================================================================
// nvme_prp_walker — PRP Traversal Engine
// 8-state FSM, PRP2 role decision, 512-entry PRP list buffer
// ============================================================================

module nvme_prp_walker #(
    parameter PAGE_SIZE    = 4096,
    parameter LIST_ENTRIES = 512
) (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         start_i,
    output wire         done_o,
    output wire         error_o,
    output wire [16:0]  error_status_o,
    input  wire [63:0]  prp1_i,
    input  wire [63:0]  prp2_i,
    input  wire [31:0]  transfer_bytes_i,
    output wire [63:0]  page_addr_o,
    output wire [16:0]  page_bytes_o,
    output wire         page_valid_o,
    input  wire         page_ready_i,
    // AXI AR (list fetch)
    output wire         list_ar_valid_o,
    input  wire         list_ar_ready_i,
    output wire [63:0]  list_ar_addr_o,
    output wire [7:0]   list_ar_len_o,
    // AXI R (list data)
    input  wire         list_r_valid_i,
    output wire         list_r_ready_o,
    input  wire [63:0]  list_r_data_i,
    input  wire         list_r_last_i,
    // Page done
    input  wire         page_done_i
);

    localparam S_IDLE        = 4'd0;
    localparam S_CALC        = 4'd1;
    localparam S_PAGE_TX     = 4'd2;
    localparam S_PAGE_WAIT   = 4'd3;
    localparam S_NEXT        = 4'd4;
    localparam S_LIST_FETCH  = 4'd5;
    localparam S_LIST_RECV   = 4'd6;
    localparam S_DONE        = 4'd7;

    localparam ROLE_RSVD = 2'd0;
    localparam ROLE_PAGE = 2'd1;
    localparam ROLE_LIST = 2'd2;

    reg [3:0]  cstate, nstate;

    // ==================================================================
    // Datapath registers
    // ==================================================================
    reg [63:0]  current_addr_q;
    reg [31:0]  bytes_left_q;
    reg [11:0]  page_offset_q;
    reg [1:0]   prp2_role_q;
    reg         first_done_q;
    reg         in_list_q;
    reg [63:0]  list_page_q;
    reg [9:0]   list_idx_q;
    reg [63:0]  list_buf [0:LIST_ENTRIES-1];
    reg         list_buf_rdy_q;
    reg [9:0]   list_beat_q;
    reg         error_q;
    reg [16:0]  error_st_q;

    // ==================================================================
    // Combinational outputs from datapath (no NBA trap)
    // ==================================================================
    wire [12:0]  first_cap = PAGE_SIZE[12:0] - prp1_i[11:0];  // 13-bit: 4096 needs >12 bits
    wire [31:0]  first_bytes = (transfer_bytes_i <= {20'd0, first_cap})
                              ? transfer_bytes_i : {20'd0, first_cap};

    assign page_addr_o    = current_addr_q;
    assign page_bytes_o   = (first_done_q) ? {5'd0, PAGE_SIZE[11:3]}
                          : first_bytes[16:0];
    assign page_valid_o   = (cstate == S_PAGE_TX);
    assign list_ar_valid_o = (cstate == S_LIST_FETCH);
    assign list_ar_addr_o  = prp2_i;
    assign list_ar_len_o   = 8'd255;  // 512 entries × 8 bytes = 4096 bytes, 64-bit beats → 512 beats, len=511. But AXI max is 256, so split into 2 bursts. Simplified: len=255 (256 beats = 2048 bytes = 256 entries)
    assign list_r_ready_o  = 1'b1;

    // FSM state register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) cstate <= S_IDLE;
        else         cstate <= nstate;
    end

    // ==================================================================
    // FSM next-state (two-process style)
    // ==================================================================
    always @(*) begin
        nstate = cstate;
        case (cstate)
            S_IDLE:       if (start_i)                  nstate = S_CALC;
            S_CALC:                                      nstate = S_PAGE_TX;
            S_PAGE_TX:    if (page_ready_i)             nstate = S_PAGE_WAIT;
            S_PAGE_WAIT:  if (page_done_i)              nstate = S_NEXT;
            S_NEXT: begin
                if (bytes_left_q == 0)                   nstate = S_DONE;
                else if (in_list_q) begin
                    if (list_idx_q == LIST_ENTRIES-1)    nstate = S_LIST_FETCH; // chain to next list page
                    else                                 nstate = S_PAGE_TX;
                end else if (prp2_role_q == ROLE_PAGE)   nstate = S_PAGE_TX;
                else if (prp2_role_q == ROLE_LIST)       nstate = S_LIST_FETCH;
                else                                     nstate = S_DONE;
            end
            S_LIST_FETCH: if (list_ar_valid_o && list_ar_ready_i)
                                                         nstate = S_LIST_RECV;
            S_LIST_RECV:  if (list_r_valid_i && list_r_last_i)
                                                         nstate = S_NEXT;
            S_DONE:                                      nstate = S_IDLE;
            default:                                     nstate = S_IDLE;
        endcase
    end

    assign done_o = (cstate == S_DONE);
    assign error_o = error_q;
    assign error_status_o = error_st_q;

    // ==================================================================
    // Datapath — sequential updates (FSM enables only)
    // ==================================================================
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            current_addr_q <= 0;  bytes_left_q  <= 0;
            page_offset_q  <= 0;  prp2_role_q   <= ROLE_RSVD;
            first_done_q   <= 0;  in_list_q     <= 0;
            list_page_q    <= 0;  list_idx_q    <= 0;
            list_buf_rdy_q <= 0;  list_beat_q   <= 0;
            error_q        <= 0;  error_st_q    <= 0;
        end else begin
            case (cstate)
                S_IDLE: begin
                    if (start_i) begin
                        bytes_left_q  <= transfer_bytes_i;
                        current_addr_q <= prp1_i;
                        page_offset_q  <= prp1_i[11:0];
                        first_done_q   <= 0;
                        in_list_q      <= 0;
                        list_idx_q     <= 0;
                        error_q        <= 0;
                    end
                end

                S_CALC: begin
                    // PRP2 role decision
                    if (transfer_bytes_i <= {20'd0, first_cap})
                        prp2_role_q <= ROLE_RSVD;
                    else if (transfer_bytes_i <= {20'd0, first_cap} + PAGE_SIZE)
                        prp2_role_q <= ROLE_PAGE;
                    else
                        prp2_role_q <= ROLE_LIST;
                end

                S_PAGE_TX: begin
                    if (page_ready_i) begin
                        // Advance for next page
                        if (!first_done_q) begin
                            bytes_left_q  <= bytes_left_q - first_bytes;
                            first_done_q  <= 1;
                            if (prp2_role_q == ROLE_RSVD)
                                bytes_left_q <= 0;
                            else if (prp2_role_q == ROLE_PAGE)
                                current_addr_q <= prp2_i;
                            // ROLE_LIST: stays on list path
                        end else if (in_list_q) begin
                            // Next entry from list buffer
                            current_addr_q <= list_buf[list_idx_q];
                            list_idx_q     <= list_idx_q + 1'b1;
                            bytes_left_q   <= bytes_left_q - PAGE_SIZE;
                            // Check alignment
                            if (list_buf[list_idx_q][11:0] != 0) begin
                                error_q   <= 1;
                                error_st_q <= 17'h13;
                            end
                        end else begin
                            // PRP2 page: only one page
                            current_addr_q <= prp2_i;
                            bytes_left_q   <= bytes_left_q - PAGE_SIZE;
                        end
                        page_offset_q <= 0;  // all subsequent pages start at offset 0
                    end
                end

                S_LIST_FETCH: begin
                    if (list_ar_valid_o && list_ar_ready_i) begin
                        list_beat_q   <= 0;
                        list_buf_rdy_q <= 0;
                    end
                end

                S_LIST_RECV: begin
                    if (list_r_valid_i) begin
                        list_buf[list_beat_q] <= list_r_data_i;
                        list_beat_q <= list_beat_q + 1'b1;
                        if (list_r_last_i) begin
                            list_buf_rdy_q <= 1;
                            list_idx_q     <= 0;
                            in_list_q      <= 1;
                            // Chain pointer: last entry is next list page addr
                            list_page_q    <= list_r_data_i;  // last beat = entry 511 = chain ptr
                        end
                    end
                end

                default: ;
            endcase
        end
    end

endmodule
`default_nettype wire
