`default_nettype none

// ============================================================================
// Module: nvme_cq_post
//
// Posts 16-byte Completion Queue Entries (CQE) to host memory via AXI writes.
// Part of the NVMe Admin Command Engine (L2 Subsystem).
//
// FSM: IDLE -> [WAIT_DATA] -> AW_REQ -> W_BEAT0 -> W_BEAT1 -> UPDATE_HEAD
//   - IDLE:      Wait for cpl_valid_i, capture completion fields
//   - WAIT_DATA: Wait for cq_data_done_i (Identify data write complete)
//   - AW_REQ:    Issue AXI write address
//   - W_BEAT0:   Write beat 0 (DW0=0, DW1=0 -- lower 8 bytes of CQE)
//   - W_BEAT1:   Write beat 1 (DW2+DW3 -- upper 8 bytes of CQE)
//   - UPDATE_HEAD: Advance head pointer, toggle phase tag on wrap
//
// CQE (16 bytes = 2 AXI beats at 64-bit width):
//   Beat 0 (bytes 7:0):  {DW1[31:0]=0, DW0[31:0]=0}
//   Beat 1 (bytes 15:8): {DW3[31:0], DW2[31:0]}
//     DW2[31:16] = {8'd0, cpl_sqid_i[7:0]}   (SQID)
//     DW2[15:0]  = cpl_sqhd_i[15:0]           (SQHD)
//     DW3[31:17] = cpl_status_i[14:0]         (Status)
//     DW3[16]    = phase_q                     (Phase Tag)
//     DW3[15:0]  = cpl_cid_i[15:0]            (CID)
//
// References:
//   - NVMe Base Spec 1.4c, Figure 46: Completion Queue Entry
//   - nvme-guidelines.md Section 4: CQE Format
//   - system-contract.md Module 4: nvme_cq_post
// ============================================================================

module nvme_cq_post (
    input  wire         clk_i,
    input  wire         rst_ni,

    // -------------------------------------
    // Configuration
    // -------------------------------------
    input  wire [63:0]  cq_base_i,
    input  wire [15:0]  cq_depth_i,        // 1-based depth

    // -------------------------------------
    // Completion from admin executor
    // -------------------------------------
    input  wire         cpl_valid_i,
    output wire         cpl_ready_o,
    input  wire [ 7:0]  cpl_sqid_i,
    input  wire [15:0]  cpl_sqhd_i,
    input  wire [15:0]  cpl_cid_i,
    input  wire [15:0]  cpl_status_i,
    input  wire         cpl_has_data_i,     // Identify has associated data write

    // -------------------------------------
    // Data write done (for Identify)
    // -------------------------------------
    input  wire         cq_data_done_i,
    input  wire [15:0]  cq_data_head_i,    // CQ head at time of data write

    // -------------------------------------
    // AXI Write (to host memory)
    // -------------------------------------
    output wire         axi_aw_valid_o,
    input  wire         axi_aw_ready_i,
    output wire [63:0]  axi_aw_addr_o,

    output wire         axi_w_valid_o,
    input  wire         axi_w_ready_i,
    output wire [63:0]  axi_w_data_o,
    output wire [ 7:0]  axi_w_strb_o,
    output wire         axi_w_last_o
);

    // ----------------------------------------------------------
    // FSM State Encoding (6 states > 3, per P2 FSM safety)
    // ----------------------------------------------------------
    localparam [2:0] IDLE        = 3'd0;
    localparam [2:0] WAIT_DATA   = 3'd1;
    localparam [2:0] AW_REQ      = 3'd2;
    localparam [2:0] W_BEAT0     = 3'd3;
    localparam [2:0] W_BEAT1     = 3'd4;
    localparam [2:0] UPDATE_HEAD = 3'd5;

    // ----------------------------------------------------------
    // Registered State (_q suffix per skill rules)
    // ----------------------------------------------------------
    reg [2:0]  state_q;
    reg [2:0]  state_d;

    reg [15:0] head_q;
    reg [15:0] head_d;

    reg        phase_q;
    reg        phase_d;

    // Captured completion fields (latched on accept in IDLE)
    reg [ 7:0] cpl_sqid_q;
    reg [15:0] cpl_sqhd_q;
    reg [15:0] cpl_cid_q;
    reg [15:0] cpl_status_q;
    reg        cpl_has_data_q;

    // ----------------------------------------------------------
    // Wires
    // ----------------------------------------------------------
    wire        wrap;
    wire [63:0] beat1_data;

    // ----------------------------------------------------------
    // FSM: Next-state logic (combinational process)
    // ----------------------------------------------------------
    always @(*) begin
        state_d = state_q;
        head_d  = head_q;
        phase_d = phase_q;

        case (state_q)
            // ------------------------------------------------
            // IDLE: Wait for completion from admin executor
            // ------------------------------------------------
            IDLE: begin
                if (cpl_valid_i) begin
                    state_d = cpl_has_data_i ? WAIT_DATA : AW_REQ;
                end
            end

            // ------------------------------------------------
            // WAIT_DATA: Stall until Identify data write done
            // ------------------------------------------------
            WAIT_DATA: begin
                if (cq_data_done_i) begin
                    state_d = AW_REQ;
                end
            end

            // ------------------------------------------------
            // AW_REQ: Issue AXI write address
            // ------------------------------------------------
            AW_REQ: begin
                if (axi_aw_ready_i) begin
                    state_d = W_BEAT0;
                end
            end

            // ------------------------------------------------
            // W_BEAT0: Write beat 0 (DW0+DW1 = 0)
            // ------------------------------------------------
            W_BEAT0: begin
                if (axi_w_ready_i) begin
                    state_d = W_BEAT1;
                end
            end

            // ------------------------------------------------
            // W_BEAT1: Write beat 1 (DW2+DW3), last beat
            // ------------------------------------------------
            W_BEAT1: begin
                if (axi_w_ready_i) begin
                    state_d = UPDATE_HEAD;
                end
            end

            // ------------------------------------------------
            // UPDATE_HEAD: Advance head, toggle phase on wrap
            // ------------------------------------------------
            UPDATE_HEAD: begin
                state_d = IDLE;
                head_d  = wrap ? 16'd0 : head_q + 16'd1;
                phase_d = wrap ? ~phase_q : phase_q;
            end
        endcase
    end

    // ----------------------------------------------------------
    // FSM: Sequential process (all registers reset per P3)
    // ----------------------------------------------------------
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q       <= IDLE;
            head_q        <= 16'd0;
            phase_q       <= 1'b1;  // NVMe: first pass through CQ writes P=1
            cpl_sqid_q    <= 8'd0;
            cpl_sqhd_q    <= 16'd0;
            cpl_cid_q     <= 16'd0;
            cpl_status_q  <= 16'd0;
            cpl_has_data_q <= 1'b0;
        end else begin
            state_q <= state_d;
            head_q  <= head_d;
            phase_q <= phase_d;

            // Capture completion data on the cycle it is accepted
            if (state_q == IDLE && cpl_valid_i) begin
                cpl_sqid_q    <= cpl_sqid_i;
                cpl_sqhd_q    <= cpl_sqhd_i;
                cpl_cid_q     <= cpl_cid_i;
                cpl_status_q  <= cpl_status_i;
                cpl_has_data_q <= cpl_has_data_i;
            end
        end
    end

    // ----------------------------------------------------------
    // Combinational helpers
    // ----------------------------------------------------------
    // Wrap condition: head is at the last slot of the CQ
    assign wrap = (head_q == cq_depth_i - 16'd1);

    // ----------------------------------------------------------
    // Control outputs (single-bit per skill rules)
    // ----------------------------------------------------------

    // Ready for completion only in IDLE state
    assign cpl_ready_o   = (state_q == IDLE);

    // AXI Write Address
    assign axi_aw_valid_o = (state_q == AW_REQ);
    assign axi_aw_addr_o  = cq_base_i + (head_q * 16);

    // AXI Write Data
    assign axi_w_valid_o  = (state_q == W_BEAT0)
                          | (state_q == W_BEAT1);
    assign axi_w_last_o   = (state_q == W_BEAT1);
    assign axi_w_strb_o   = 8'hFF;   // All 16 bytes valid

    // Beat 0: DW0=0, DW1=0 (lower 8 bytes of CQE, all zeros)
    // Beat 1: DW2+DW3 (upper 8 bytes of CQE, assembled below)
    assign axi_w_data_o   = (state_q == W_BEAT1) ? beat1_data : 64'd0;

    // ----------------------------------------------------------
    // CQE Beat 1 assembly (16 bytes, upper 8 bytes on AXI bus)
    //
    //   Little-endian memory layout (AXI byte 0 = LSB):
    //     Beat 1[31:0]  = DW2 = {8'd0, cpl_sqid_q[7:0], cpl_sqhd_q[15:0]}
    //       DW2[31:24]  = 8'd0
    //       DW2[23:16]  = cpl_sqid_q[7:0]
    //       DW2[15:0]   = cpl_sqhd_q[15:0]
    //     Beat 1[63:32] = DW3 = {cpl_status_q[14:0], phase_q, cpl_cid_q[15:0]}
    //       DW3[31:17]  = cpl_status_q[14:0]
    //       DW3[16]     = phase_q
    //       DW3[15:0]   = cpl_cid_q[15:0]
    // ----------------------------------------------------------
    assign beat1_data = {
        cpl_status_q[14:0],     // [63:49] DW3[31:17]
        phase_q,                // [48]    DW3[16]
        cpl_cid_q[15:0],        // [47:32] DW3[15:0]
        8'd0,                   // [31:24] DW2[31:24] (SQID upper zero)
        cpl_sqid_q[7:0],        // [23:16] DW2[23:16]
        cpl_sqhd_q[15:0]        // [15:0]  DW2[15:0]
    };

endmodule

`default_nettype wire
