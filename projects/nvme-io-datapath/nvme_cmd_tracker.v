`default_nettype none
// ============================================================================
// nvme_cmd_tracker — Slot-based NVMe I/O Command Tracker
// 4-slot FIFO, FIFO-ordered issue, completion aggregation
// ============================================================================

module nvme_cmd_tracker #(
    parameter NUM_SLOTS = 4,
    parameter LBA_SIZE  = 512
) (
    input  wire         clk_i,
    input  wire         rst_ni,
    // Command input
    input  wire         cmd_valid_i,
    output wire         cmd_ready_o,
    input  wire [7:0]   cmd_opcode_i,
    input  wire [16:0]  cmd_cid_i,
    input  wire [31:0]  cmd_nsid_i,
    input  wire [63:0]  cmd_prp1_i,
    input  wire [63:0]  cmd_prp2_i,
    input  wire [63:0]  cmd_slba_i,
    input  wire [16:0]  cmd_nlb_i,
    input  wire [7:0]   cmd_sqid_i,
    input  wire [16:0]  cmd_sq_head_i,
    // PRP walker
    output wire         prp_start_o,
    input  wire         prp_done_i,
    input  wire         prp_error_i,
    input  wire [16:0]  prp_error_status_i,
    output wire [63:0]  prp_prp1_o,
    output wire [63:0]  prp_prp2_o,
    output wire [31:0]  prp_transfer_bytes_o,
    // Read engine
    output wire         rd_start_o,
    input  wire         rd_done_i,
    output wire [63:0]  rd_slba_o,
    output wire [31:0]  rd_total_bytes_o,
    // Completion
    output wire         cpl_valid_o,
    input  wire         cpl_ready_i,
    output wire [7:0]   cpl_sqid_o,
    output wire [16:0]  cpl_sqhd_o,
    output wire [16:0]  cpl_cid_o,
    output wire [16:0]  cpl_status_o
);

    localparam SLOT_W = NUM_SLOTS;
    localparam IDX_W  = $clog2(NUM_SLOTS);  // 2 for 4 slots

    // Slot storage (packed per field for simplicity)
    reg [SLOT_W-1:0]           slot_vld_q;
    reg [16:0]                 slot_cid    [0:NUM_SLOTS-1];
    reg [31:0]                 slot_nsid   [0:NUM_SLOTS-1];
    reg [63:0]                 slot_prp1   [0:NUM_SLOTS-1];
    reg [63:0]                 slot_prp2   [0:NUM_SLOTS-1];
    reg [63:0]                 slot_slba   [0:NUM_SLOTS-1];
    reg [16:0]                 slot_nlb    [0:NUM_SLOTS-1];
    reg [7:0]                  slot_sqid   [0:NUM_SLOTS-1];
    reg [16:0]                 slot_sqhd   [0:NUM_SLOTS-1];

    reg [IDX_W-1:0]            wr_ptr_q, rd_ptr_q;
    reg                        busy_q;    // PRP/read in progress for current slot

    wire slot_free  = !slot_vld_q[wr_ptr_q];
    assign cmd_ready_o = slot_free;

    wire [IDX_W-1:0] cur_slot = rd_ptr_q;

    // Accepted: command written to slot
    wire cmd_accept = cmd_valid_i && cmd_ready_o;

    // ==================================================================
    // Slot management + command accept
    // ==================================================================
    integer si;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            slot_vld_q <= 0;  wr_ptr_q <= 0;  rd_ptr_q <= 0;  busy_q <= 0;
            for (si = 0; si < NUM_SLOTS; si = si + 1) begin
                slot_cid[si] <= 0;  slot_nsid[si]  <= 0;
                slot_prp1[si] <= 0; slot_prp2[si]  <= 0;
                slot_slba[si] <= 0; slot_nlb[si]   <= 0;
                slot_sqid[si] <= 0; slot_sqhd[si]  <= 0;
            end
        end else begin
            if (cmd_accept) begin
                slot_vld_q[wr_ptr_q] <= 1;
                slot_cid   [wr_ptr_q] <= cmd_cid_i;
                slot_nsid  [wr_ptr_q] <= cmd_nsid_i;
                slot_prp1  [wr_ptr_q] <= cmd_prp1_i;
                slot_prp2  [wr_ptr_q] <= cmd_prp2_i;
                slot_slba  [wr_ptr_q] <= cmd_slba_i;
                slot_nlb   [wr_ptr_q] <= cmd_nlb_i;
                slot_sqid  [wr_ptr_q] <= cmd_sqid_i;
                slot_sqhd  [wr_ptr_q] <= cmd_sq_head_i;
                wr_ptr_q <= wr_ptr_q + 1'b1;
            end

            // Advance to next slot when current command fully done
            if (cpl_valid_o && cpl_ready_i) begin
                slot_vld_q[cur_slot] <= 0;
                rd_ptr_q <= rd_ptr_q + 1'b1;
                busy_q   <= 0;
            end

            // Start processing when slot available and not busy
            if (slot_vld_q[cur_slot] && !busy_q && !cpl_valid_o)
                busy_q <= 1;
        end
    end

    // ==================================================================
    // PRP start: pulse when busy_q transitions (first cycle of processing)
    // ==================================================================
    wire prp_go = slot_vld_q[cur_slot] && !busy_q && !cpl_valid_o;
    assign prp_start_o = prp_go;
    assign prp_prp1_o  = slot_prp1[cur_slot];
    assign prp_prp2_o  = slot_prp2[cur_slot];
    assign prp_transfer_bytes_o = (slot_nlb[cur_slot] + 17'd1) * LBA_SIZE;

    // ==================================================================
    // Read start: pulse after PRP done (next cycle)
    // ==================================================================
    reg prp_done_r;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) prp_done_r <= 0;
        else         prp_done_r <= prp_done_i;
    end
    assign rd_start_o      = prp_done_i && !prp_done_r;  // rising edge of prp_done
    assign rd_slba_o       = slot_slba[cur_slot];
    assign rd_total_bytes_o = prp_transfer_bytes_o;

    // ==================================================================
    // Completion: level flag after read done
    // ==================================================================
    reg rd_done_r;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) rd_done_r <= 0;
        else         rd_done_r <= rd_done_i;
    end

    reg        cpl_vld_q;
    reg [16:0] cpl_status_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cpl_vld_q    <= 0;
            cpl_status_q <= 0;
        end else begin
            if (cpl_vld_q && cpl_ready_i)
                cpl_vld_q <= 0;

            if (rd_done_i && !rd_done_r) begin  // rising edge
                cpl_vld_q    <= 1;
                cpl_status_q <= prp_error_i ? prp_error_status_i : 17'd0;
            end
        end
    end

    assign cpl_valid_o  = cpl_vld_q;
    assign cpl_sqid_o   = slot_sqid[cur_slot];
    assign cpl_sqhd_o   = slot_sqhd[cur_slot];
    assign cpl_cid_o    = slot_cid[cur_slot];
    assign cpl_status_o = cpl_status_q;

endmodule
`default_nettype wire
