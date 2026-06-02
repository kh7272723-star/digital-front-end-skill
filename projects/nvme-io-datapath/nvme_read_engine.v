`default_nettype none
module nvme_read_engine #(
    parameter AXI_MAX_BURST   = 64,
    parameter LBA_SIZE        = 512,
    parameter DATA_FIFO_DEPTH = 64
) (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         start_i,
    output wire         done_o,
    input  wire [63:0]  slba_i,
    input  wire [31:0]  total_bytes_i,
    input  wire [63:0]  page_addr_i,
    input  wire [16:0]  page_bytes_i,
    input  wire         page_valid_i,
    input  wire         page_last_i,
    output wire         page_ready_o,
    output wire         page_done_o,
    output wire [63:0]  nvm_addr_o,
    output wire         nvm_rd_en_o,
    input  wire [63:0]  nvm_rdata_i,
    input  wire         nvm_rvalid_i,
    output wire         nvm_rready_o,
    output wire         axi_aw_valid_o,
    input  wire         axi_aw_ready_i,
    output wire [63:0]  axi_aw_addr_o,
    output wire [7:0]   axi_aw_len_o,
    output wire         axi_w_valid_o,
    input  wire         axi_w_ready_i,
    output wire [63:0]  axi_w_data_o,
    output wire [7:0]   axi_w_strb_o,
    output wire         axi_w_last_o,
    input  wire         axi_b_valid_i,
    output wire         axi_b_ready_o,
    input  wire [1:0]   axi_b_resp_i
);
    localparam FA = $clog2(DATA_FIFO_DEPTH);

    // ======================================================================
    // Page tracking
    // ======================================================================
    reg [7:0] pg_in_q;
    reg [7:0] pg_out_q;
    reg       last_seen_q;

    assign page_ready_o = 1'b1;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pg_in_q     <= 0;
            pg_out_q    <= 0;
            last_seen_q <= 0;
        end else begin
            if (page_valid_i)
                pg_in_q <= pg_in_q + 1'b1;
            if (page_done_o)
                pg_out_q <= pg_out_q + 1'b1;
            if (page_valid_i && page_last_i)
                last_seen_q <= 1'b1;
        end
    end

    // ======================================================================
    // FWFT Data FIFO
    // ======================================================================
    reg [63:0]       fmem [0:DATA_FIFO_DEPTH-1];
    reg [FA-1:0]     fwp_q;
    reg [FA-1:0]     frp_q;
    reg [FA:0]       fcnt_q;

    wire fw = nvm_rvalid_i;
    wire fr = axi_w_valid_o && axi_w_ready_i;

    always @(posedge clk_i) begin
        if (fw && fcnt_q < DATA_FIFO_DEPTH)
            fmem[fwp_q] <= nvm_rdata_i;
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            fwp_q  <= 0;
            frp_q  <= 0;
            fcnt_q <= 0;
        end else begin
            if (fw && fcnt_q < DATA_FIFO_DEPTH)
                fwp_q <= fwp_q + 1'b1;
            if (fr)
                frp_q <= frp_q + 1'b1;
            case ({fw && fcnt_q < DATA_FIFO_DEPTH, fr})
                2'b10:   fcnt_q <= fcnt_q + 1'b1;
                2'b01:   fcnt_q <= fcnt_q - 1'b1;
                default: ;
            endcase
        end
    end

    wire [63:0] frd = fmem[frp_q];

    // ======================================================================
    // NVM read + page control
    // ======================================================================
    reg [31:0] nvm_off_q;
    reg [16:0] pg_rem_q;
    reg [63:0] pg_host_q;
    reg        pg_live_q;
    reg        pg_nvm_done_q;
    reg        pg_drain_q;
    reg        pg_pend_q;
    reg [63:0] pend_a_q;
    reg [16:0] pend_b_q;
    reg        pend_last_q;

    wire nvm_go = pg_live_q
               && (pg_rem_q >= 17'd8)
               && (fcnt_q < DATA_FIFO_DEPTH);

    assign nvm_rd_en_o  = nvm_go;
    assign nvm_addr_o   = slba_i * LBA_SIZE + nvm_off_q;
    assign nvm_rready_o = 1'b1;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            nvm_off_q     <= 0;
            pg_rem_q      <= 0;
            pg_host_q     <= 0;
            pg_live_q     <= 0;
            pg_nvm_done_q <= 0;
            pg_drain_q    <= 0;
            pg_pend_q     <= 0;
            pend_a_q      <= 0;
            pend_b_q      <= 0;
            pend_last_q   <= 0;
        end else begin
            if (start_i)
                nvm_off_q <= 0;

            // Accept page: either direct or to pending slot
            if (page_valid_i) begin
                if (!pg_live_q) begin
                    pg_live_q     <= 1;
                    pg_host_q     <= page_addr_i;
                    pg_rem_q      <= page_bytes_i;
                    pg_nvm_done_q <= 0;
                    pg_drain_q    <= 0;
                end else begin
                    pg_pend_q   <= 1;
                    pend_a_q    <= page_addr_i;
                    pend_b_q    <= page_bytes_i;
                    pend_last_q <= page_last_i;
                end
            end

            // Start pending page when current done
            if (pg_pend_q && page_drain_done) begin
                pg_live_q     <= 1;
                pg_host_q     <= pend_a_q;
                pg_rem_q      <= pend_b_q;
                pg_nvm_done_q <= 0;
                pg_drain_q    <= 0;
                pg_pend_q     <= 0;
            end

            if (nvm_go) begin
                nvm_off_q <= nvm_off_q + 32'd8;
                pg_rem_q  <= pg_rem_q - 17'd8;
                if (pg_rem_q <= 17'd8)
                    pg_nvm_done_q <= 1;
            end else if (pg_nvm_done_q && !pg_drain_q) begin
                pg_drain_q <= 1;
            end else if (page_drain_done) begin
                pg_live_q  <= 0;
                pg_drain_q <= 0;
            end
        end
    end

    wire page_drain_done = pg_drain_q
                        && !w_act_q
                        && (b_cnt_q == 0);

    assign page_done_o = page_drain_done;
    assign done_o      = page_drain_done
                      && (pg_in_q == pg_out_q)
                      && (pg_in_q > 0)
                      && last_seen_q;

    // ======================================================================
    // AW Controller (two-process FSM + separate datapath, C5/C6/C7)
    // ======================================================================
    localparam AW_IDLE  = 1'b0;
    localparam AW_ISSUE = 1'b1;

    reg aw_cstate;
    reg aw_nstate;

    // New page accepted (either direct or from pending slot)
    wire aw_page_accepted = (page_valid_i && !pg_live_q && !pg_pend_q)
                         || (pg_pend_q && page_drain_done);

    // Select page parameters: pending slot takes priority
    wire [63:0] aw_next_addr  = pg_pend_q ? pend_a_q    : page_addr_i;
    wire [15:0] aw_next_beats = pg_pend_q ? pend_b_q[16:3]
                                          : page_bytes_i[16:3];

    // ==================================================================
    // Process 1: FSM state register
    // ==================================================================
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            aw_cstate <= AW_IDLE;
        else
            aw_cstate <= aw_nstate;
    end

    // ==================================================================
    // Process 2: FSM next-state + single-bit control outputs (C7)
    // ==================================================================
    reg aw_load_o;     // load new page params into AW datapath
    reg aw_advance_o;  // advance address and recalculate after AW handshake
    reg aw_done_o;     // last burst of page accepted — return to IDLE

    always @(*) begin
        aw_nstate   = aw_cstate;
        aw_load_o   = 1'b0;
        aw_advance_o = 1'b0;
        aw_done_o   = 1'b0;

        case (aw_cstate)
            AW_IDLE: begin
                if (aw_page_accepted) begin
                    aw_load_o = 1'b1;
                    aw_nstate = AW_ISSUE;
                end
            end

            AW_ISSUE: begin
                if (axi_aw_valid_o && axi_aw_ready_i) begin
                    aw_advance_o = 1'b1;
                    if (aw_left_q <= ({8'd0, aw_l_q} + 1)) begin
                        aw_done_o = 1'b1;
                        aw_nstate = AW_IDLE;
                    end
                end
            end

            default: aw_nstate = AW_IDLE;
        endcase
    end

    // AW outputs (gated by FSM state)
    assign axi_aw_valid_o = (aw_cstate == AW_ISSUE)
                         && (fcnt_q > aw_l_q)
                         && !w_act_q;
    assign axi_aw_addr_o  = aw_a_q;
    assign axi_aw_len_o   = aw_l_q;

    // ==================================================================
    // AW datapath registers (sequential, gated by FSM single-bit enables)
    // ==================================================================
    reg [63:0] aw_a_q;
    reg [7:0]  aw_l_q;
    reg [15:0] aw_left_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_a_q    <= 0;
            aw_l_q    <= 0;
            aw_left_q <= 0;
        end else begin
            // Load new page params (FSM enable)
            if (aw_load_o) begin
                aw_a_q    <= aw_next_addr;
                aw_left_q <= aw_next_beats;
                aw_l_q    <= (aw_next_beats > AXI_MAX_BURST)
                           ? (AXI_MAX_BURST - 1)
                           : (aw_next_beats - 1);
            end

            // Advance after AW handshake
            if (aw_advance_o) begin
                aw_a_q <= aw_a_q + ({56'd0, aw_l_q} + 1) * 8;
                if (!aw_done_o) begin
                    aw_left_q <= aw_left_q - ({8'd0, aw_l_q} + 1);
                    aw_l_q    <= (aw_left_q - ({8'd0, aw_l_q} + 1) > AXI_MAX_BURST)
                               ? (AXI_MAX_BURST - 1)
                               : (aw_left_q - ({8'd0, aw_l_q} + 1) - 1);
                end
            end
        end
    end

    // ======================================================================
    // W Controller
    // ======================================================================
    reg       w_act_q;
    reg [7:0] w_b_q;
    reg [7:0] w_blen_q;

    assign axi_w_valid_o = w_act_q;
    assign axi_w_data_o  = frd;
    assign axi_w_strb_o  = 8'hFF;
    assign axi_w_last_o  = w_act_q && (w_b_q == w_blen_q);

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            w_act_q  <= 0;
            w_b_q    <= 0;
            w_blen_q <= 0;
        end else begin
            if (axi_aw_valid_o && axi_aw_ready_i && !w_act_q) begin
                w_act_q  <= 1;
                w_b_q    <= 0;
                w_blen_q <= aw_l_q;
            end
            if (w_act_q && axi_w_valid_o && axi_w_ready_i) begin
                if (w_b_q == w_blen_q)
                    w_act_q <= 0;
                else
                    w_b_q <= w_b_q + 1'b1;
            end
        end
    end

    // ======================================================================
    // B Controller
    // ======================================================================
    reg [7:0] b_cnt_q;

    assign axi_b_ready_o = 1'b1;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            b_cnt_q <= 0;
        end else begin
            if (axi_aw_valid_o && axi_aw_ready_i)
                b_cnt_q <= b_cnt_q + 1'b1;
            if (axi_b_valid_i)
                b_cnt_q <= b_cnt_q - 1'b1;
        end
    end

endmodule
`default_nettype wire
