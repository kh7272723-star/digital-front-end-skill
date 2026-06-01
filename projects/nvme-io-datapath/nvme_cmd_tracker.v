// =============================================================================
// nvme_cmd_tracker — 4-slot outstanding I/O command tracker
// =============================================================================
//
// Cycle Trace (Read command, single slot):
//
// Cycle:   0     1     2     3     4     5     6
// clk_i    ^     ^     ^     ^     ^     ^     ^
//
// cmd_valid_i ___/‾‾‾\___________________________
// cmd_ready_o ___/‾‾‾‾‾‾‾‾\_____________________ (slot 0 free → ready=1)
// slot_valid[0] ________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_
// wr_ptr_q    00      01 (enqueued to slot 0)
//
// state_q     IDLE   ISSUE_PRP___________________ IDLE
// prp_start_o ________/‾‾‾\______________________ (1-cycle pulse)
// prp_done_i  ________________/‾‾‾\______________ (from PRP walker)
// rd_start_o  _______________________/‾‾‾\_______ (1 cycle after prp_done)
// rd_done_i   ______________________________/‾‾‾\ (from read engine)
//
// cpl_valid_o ____________________________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾ (level, held until cpl_ready)
// cpl_ready_i ___________________________________________/‾‾‾\_______
// slot_valid[0]________________________________________________\______ (slot freed)
//
// =============================================================================
//
// Error path cycle trace:
//
// Cycle:   0     1     2     3     4
// clk_i    ^     ^     ^     ^     ^
//
// state_q     ISSUE_PRP___________________ ISSUE_CMPL
// prp_done_i  ________/‾‾‾\______________
// prp_error_i ________/‾‾‾\______________ (error status captured)
// cpl_valid_o ___________________________/‾‾‾‾‾‾‾‾‾ (level)
// cpl_status_o[15:0] transitions from 16'h0000 to error_code
//
// =============================================================================

`default_nettype none

module nvme_cmd_tracker #(
    parameter NUM_SLOTS = 4,
    parameter LBA_SIZE  = 512
) (
    input  wire         clk_i,
    input  wire         rst_ni,

    // Command input from demux
    input  wire         cmd_valid_i,
    output wire         cmd_ready_o,
    input  wire [7:0]   cmd_opcode_i,
    input  wire [15:0]  cmd_cid_i,
    input  wire [31:0]  cmd_nsid_i,
    input  wire [63:0]  cmd_prp1_i,
    input  wire [63:0]  cmd_prp2_i,
    input  wire [63:0]  cmd_slba_i,
    input  wire [15:0]  cmd_nlb_i,
    input  wire [7:0]   cmd_sqid_i,
    input  wire [15:0]  cmd_sq_head_i,

    // PRP Walker control
    output reg          prp_start_o,
    input  wire         prp_done_i,
    input  wire         prp_error_i,
    input  wire [15:0]  prp_error_status_i,
    output wire [63:0]  prp_prp1_o,
    output wire [63:0]  prp_prp2_o,
    output wire [31:0]  prp_transfer_bytes_o,

    // Read Engine control
    output reg          rd_start_o,
    input  wire         rd_done_i,
    input  wire         rd_error_i,
    output wire [63:0]  rd_slba_o,
    output wire [31:0]  rd_total_bytes_o,

    // Completion output to CQ Post
    output reg          cpl_valid_o,
    input  wire         cpl_ready_i,
    output wire [7:0]   cpl_sqid_o,
    output wire [15:0]  cpl_sqhd_o,
    output wire [15:0]  cpl_cid_o,
    output wire [15:0]  cpl_status_o
);

    // =========================================================================
    // Slot register arrays
    // =========================================================================
    reg [3:0]   slot_valid_q;

    reg [15:0]  slot_cid    [0:NUM_SLOTS-1];
    reg [31:0]  slot_nsid   [0:NUM_SLOTS-1];
    reg [63:0]  slot_prp1   [0:NUM_SLOTS-1];
    reg [63:0]  slot_prp2   [0:NUM_SLOTS-1];
    reg [63:0]  slot_slba   [0:NUM_SLOTS-1];
    reg [15:0]  slot_nlb    [0:NUM_SLOTS-1];
    reg [7:0]   slot_sqid   [0:NUM_SLOTS-1];
    reg [15:0]  slot_sqhd   [0:NUM_SLOTS-1];

    // =========================================================================
    // Pointer registers
    // =========================================================================
    reg [1:0]   wr_ptr_q;       // next free slot (enqueue)
    reg [1:0]   rd_ptr_q;       // next command to issue (dequeue)

    // =========================================================================
    // Processing FSM
    // =========================================================================
    localparam [1:0] IDLE       = 2'd0;
    localparam [1:0] ISSUE_BOTH = 2'd1;  // issue prp_start + rd_start simultaneously
    localparam [1:0] WAIT_DONE  = 2'd2;  // wait for both prp_done + rd_done
    localparam [1:0] ISSUE_CMPL = 2'd3;

    reg [1:0]  state_q, state_d;
    reg        error_q, error_d;
    reg [15:0] error_status_q, error_status_d;
    reg        cpl_valid_d;
    reg        prp_done_seen_q, prp_done_seen_d;  // track which engines finished
    reg        rd_done_seen_q,  rd_done_seen_d;

    // =========================================================================
    // Combinational: enqueue control
    // =========================================================================
    // cmd_ready_o: accept when the slot at wr_ptr is free
    wire enq_slot_free = !slot_valid_q[wr_ptr_q];
    assign cmd_ready_o = enq_slot_free;

    // Number of occupied slots (for debug / unused)
    // wire [2:0] occupied = slot_valid_q[0] + slot_valid_q[1]
    //                     + slot_valid_q[2] + slot_valid_q[3];

    // =========================================================================
    // Combinational: read-pointer slot selection
    // =========================================================================
    wire rd_slot_valid = slot_valid_q[rd_ptr_q];

    // =========================================================================
    // Combinational: output multiplexing from selected slot
    // =========================================================================
    assign prp_prp1_o            = slot_prp1 [rd_ptr_q];
    assign prp_prp2_o            = slot_prp2 [rd_ptr_q];
    assign prp_transfer_bytes_o  = (slot_nlb[rd_ptr_q] + 16'd1) * LBA_SIZE;
    assign rd_slba_o             = slot_slba [rd_ptr_q];
    assign rd_total_bytes_o      = (slot_nlb[rd_ptr_q] + 16'd1) * LBA_SIZE;
    assign cpl_sqid_o            = slot_sqid [rd_ptr_q];
    assign cpl_sqhd_o            = slot_sqhd [rd_ptr_q];
    assign cpl_cid_o             = slot_cid  [rd_ptr_q];
    assign cpl_status_o          = error_q ? error_status_q : 16'h0000;

    // =========================================================================
    // FSM: next-state logic
    // =========================================================================
    always @(*) begin
        state_d  = state_q;
        error_d  = error_q;
        error_status_d = error_status_q;
        cpl_valid_d = 1'b0;
        prp_done_seen_d = prp_done_seen_q;
        rd_done_seen_d  = rd_done_seen_q;

        case (state_q)

            IDLE: begin
                if (rd_slot_valid) begin
                    state_d = ISSUE_BOTH;
                    error_d = 1'b0;
                    error_status_d = 16'h0000;
                end
            end

            ISSUE_BOTH: begin
                // prp_start_o and rd_start_o are pulsed from edge detection
                // Move to WAIT_DONE on the next cycle
                state_d = WAIT_DONE;
                prp_done_seen_d = 1'b0;
                rd_done_seen_d  = 1'b0;
            end

            WAIT_DONE: begin
                if (prp_done_i) begin
                    prp_done_seen_d = 1'b1;
                    if (prp_error_i) begin
                        error_d = 1'b1;
                        error_status_d = prp_error_status_i;
                    end
                end
                if (rd_done_i) begin
                    rd_done_seen_d = 1'b1;
                    if (rd_error_i) begin
                        error_d = 1'b1;
                        error_status_d = 16'h0005;  // Data Transfer Error
                    end
                end
                // Both done (or PRP error → skip read)
                if ((prp_done_seen_d && rd_done_seen_d) || (prp_done_seen_d && error_d)) begin
                    state_d = ISSUE_CMPL;
                end
            end

            ISSUE_CMPL: begin
                cpl_valid_d = 1'b1;
                if (cpl_ready_i) begin
                    state_d = IDLE;
                end
            end

            default: state_d = IDLE;

        endcase
    end

    // =========================================================================
    // Registered outputs: prp_start_o, rd_start_o (pulses)
    // =========================================================================
    // These are 1-cycle pulses generated from FSM state transitions.
    // They must be exactly 1 cycle wide.
    reg prev_prp_start;  // for pulse edge detection (not needed - use state_q)
    // prp_start_o is asserted in ISSUE_PRP state on first cycle
    // rd_start_o is asserted in ISSUE_RD state on first cycle

    // Edge detection for pulse generation — both fire on ISSUE_BOTH entry
    wire enter_issue_both = (state_q == IDLE) && (state_d == ISSUE_BOTH);

    // =========================================================================
    // Sequential block: registers + state update + slot management
    // =========================================================================
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q         <= IDLE;
            error_q         <= 1'b0;
            error_status_q  <= 16'h0000;
            prp_done_seen_q <= 1'b0;
            rd_done_seen_q  <= 1'b0;
            slot_valid_q    <= 4'h0;
            wr_ptr_q        <= 2'd0;
            rd_ptr_q        <= 2'd0;
            prp_start_o     <= 1'b0;
            rd_start_o      <= 1'b0;
            cpl_valid_o     <= 1'b0;
        end else begin
            state_q  <= state_d;
            error_q  <= error_d;
            error_status_q <= error_status_d;
            prp_done_seen_q <= prp_done_seen_d;
            rd_done_seen_q  <= rd_done_seen_d;

            // ── Defaults: pulse signals deassert ──
            prp_start_o <= 1'b0;
            rd_start_o  <= 1'b0;

            // ── Enqueue: accept new command ──
            if (cmd_valid_i && cmd_ready_o) begin
                slot_valid_q[wr_ptr_q] <= 1'b1;
                slot_cid   [wr_ptr_q] <= cmd_cid_i;
                slot_nsid  [wr_ptr_q] <= cmd_nsid_i;
                slot_prp1  [wr_ptr_q] <= cmd_prp1_i;
                slot_prp2  [wr_ptr_q] <= cmd_prp2_i;
                slot_slba  [wr_ptr_q] <= cmd_slba_i;
                slot_nlb   [wr_ptr_q] <= cmd_nlb_i;
                slot_sqid  [wr_ptr_q] <= cmd_sqid_i;
                slot_sqhd  [wr_ptr_q] <= cmd_sq_head_i;
                wr_ptr_q   <= wr_ptr_q + 2'd1;
            end else begin
                wr_ptr_q <= wr_ptr_q;
            end

            // ── Issue both start pulses simultaneously ──
            if (enter_issue_both) begin
                prp_start_o <= 1'b1;
                rd_start_o  <= 1'b1;
            end

            // ── Dequeue: command complete ──
            if (state_d == ISSUE_CMPL && cpl_ready_i) begin
                slot_valid_q[rd_ptr_q] <= 1'b0;
                rd_ptr_q <= rd_ptr_q + 2'd1;
            end else begin
                rd_ptr_q <= rd_ptr_q;
            end

            // ── Completion output ──
            cpl_valid_o <= cpl_valid_d;
        end
    end

    // =========================================================================
    // Slot storage: write-only on enqueue (no async read — combinational mux
    // uses slot_*[rd_ptr_q] directly, which synthesizes to LUT RAM)
    // =========================================================================
    // The slot_* arrays are written in the sequential block above.
    // They are read combinationally via the assign statements.
    // Icarus/iverilog supports 2D reg arrays with indexing.

endmodule

`default_nettype wire
