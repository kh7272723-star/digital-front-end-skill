`default_nettype none

// ============================================================================
// Module: nvme_admin_exec
//
// NVMe Admin Command Executor.
// Executes Admin commands: Identify (0x06), Create I/O CQ (0x05),
// Create I/O SQ (0x01). All other opcodes return Invalid Opcode error.
//
// FSM: IDLE -> DECODE -> [DATA_XFER (Identify only)] -> CPL_OUT -> IDLE
//   - IDLE:      Wait for cmd_valid_i with CQ post ready
//   - DECODE:    Opcode decode, validation, determine data/error path (1 cycle)
//   - DATA_XFER: 512-beat data write for Identify Controller/Namespace
//   - CPL_OUT:   Present completion, wait for cpl_ready_i acknowledge
//
// For Identify (CNS=0x01/0x00), outputs 4096 bytes of Identify data via
// cq_data_* handshake interface (512 beats of 64-bit data at PRP1 base addr).
//
// References:
//   - NVMe Base Spec 1.4c, Section 5: Admin Command Set
//   - nvme-guidelines.md Section 3: Admin commands, Section 4: CQE status codes
//   - system-contract.md Module 3: nvme_admin_exec
// ============================================================================

module nvme_admin_exec (
    input  wire         clk_i,
    input  wire         rst_ni,

    // -------------------------------------
    // Command from SQ fetch (parsed SQE)
    // -------------------------------------
    input  wire         cmd_valid_i,
    output wire         cmd_ready_o,
    input  wire [ 7:0]  cmd_opcode_i,
    input  wire [15:0]  cmd_cid_i,
    input  wire [31:0]  cmd_nsid_i,
    input  wire [63:0]  cmd_prp1_i,
    input  wire [63:0]  cmd_prp2_i,
    input  wire [31:0]  cmd_cdw10_i,
    input  wire [31:0]  cmd_cdw11_i,
    input  wire [ 7:0]  cmd_sqid_i,

    // -------------------------------------
    // Identify data write (AXI-like handshake)
    // -------------------------------------
    output wire         cq_data_wr_o,
    output wire [63:0]  cq_data_addr_o,
    output wire [63:0]  cq_data_o,
    output wire         cq_data_valid_o,
    output wire         cq_data_last_o,
    input  wire         cq_data_ready_i,

    // -------------------------------------
    // Completion to CQ post engine
    // -------------------------------------
    output wire         cpl_valid_o,
    input  wire         cpl_ready_i,
    output wire [ 7:0]  cpl_sqid_o,
    output wire [15:0]  cpl_sqhd_o,
    output wire [15:0]  cpl_cid_o,
    output wire [15:0]  cpl_status_o,
    output wire         cpl_has_data_o,

    // -------------------------------------
    // Queue allocation (Create I/O CQ / SQ)
    // -------------------------------------
    output wire         queue_alloc_o,
    output wire [ 7:0]  queue_id_o,
    output wire [15:0]  queue_depth_o,
    output wire         queue_is_sq_o,
    output wire [ 7:0]  queue_cqid_o
);

    // ======================================================================
    // Parameters
    // ======================================================================
    parameter MAX_QUEUES = 5;          // Max I/O queues (0=admin + 1..4)
    parameter MQES       = 255;        // Max Queue Entries Supported

    // ======================================================================
    // FSM State Encoding (4 states, two-process per skill rules)
    // ======================================================================
    localparam [1:0] IDLE      = 2'd0;
    localparam [1:0] DECODE    = 2'd1;
    localparam [1:0] DATA_XFER = 2'd2;
    localparam [1:0] CPL_OUT   = 2'd3;

    // ======================================================================
    // Status Code definitions (NVMe Base Spec 1.4c, Figure 129)
    //   Generic Command Status (SCT=0):
    //     SC=0x00 Success, 0x01 Invalid Opcode, 0x02 Invalid Field
    //     0x0B Invalid Queue Identifier, 0x0C Invalid Queue Size
    //     0x0D Invalid Queue Create (CQ doesn't exist / queue already exists)
    //
    //   Encoding: cpl_status_o[15:0] = {5'd0, SCT[2:0], SC[7:0]}
    //     status[7:0]   = SC
    //     status[10:8]  = SCT
    //     status[15:11] = reserved (0)
    // ======================================================================
    localparam [7:0] SC_SUCCESS       = 8'h00;
    localparam [7:0] SC_INVALID_OP    = 8'h01;
    localparam [7:0] SC_INVALID_FIELD = 8'h02;
    localparam [7:0] SC_INVALID_QID   = 8'h0B;
    localparam [7:0] SC_INVALID_QSIZE = 8'h0C;
    localparam [7:0] SC_INVALID_CREATE = 8'h0D;

    // SCT = 3'd0 (Generic) for all status values in this module
    localparam [15:0] STATUS_SUCCESS       = {5'd0, 3'd0, SC_SUCCESS};
    localparam [15:0] STATUS_INVALID_OP    = {5'd0, 3'd0, SC_INVALID_OP};
    localparam [15:0] STATUS_INVALID_FIELD = {5'd0, 3'd0, SC_INVALID_FIELD};
    localparam [15:0] STATUS_INVALID_QID   = {5'd0, 3'd0, SC_INVALID_QID};
    localparam [15:0] STATUS_INVALID_QSIZE = {5'd0, 3'd0, SC_INVALID_QSIZE};
    localparam [15:0] STATUS_INVALID_CREATE = {5'd0, 3'd0, SC_INVALID_CREATE};

    // ======================================================================
    // Opcode constants
    // ======================================================================
    localparam [7:0] OPC_CREATE_SQ = 8'h01;
    localparam [7:0] OPC_CREATE_CQ = 8'h05;
    localparam [7:0] OPC_IDENTIFY  = 8'h06;

    // ======================================================================
    // Identify CNS constants
    // ======================================================================
    localparam [7:0] CNS_NAMESPACE  = 8'h00;
    localparam [7:0] CNS_CONTROLLER = 8'h01;

    // ======================================================================
    // Data transfer constants
    // ======================================================================
    localparam [8:0] IDENT_BEAT_MAX = 9'd511;  // 512 beats - 1

    // ======================================================================
    // Registered State (_q suffix per skill rules)
    // ======================================================================
    reg [1:0]  state_q;
    reg [1:0]  state_d;

    // Captured command fields (latched on accept in IDLE)
    reg [ 7:0] opcode_q;
    reg [15:0] cid_q;
    reg [31:0] nsid_q;
    reg [63:0] prp1_q;
    reg [63:0] prp2_q;
    reg [31:0] cdw10_q;
    reg [31:0] cdw11_q;
    reg [ 7:0] sqid_q;

    // Data transfer beat counter (0..511 beats)
    reg [8:0]  beat_count_q;

    // Completion registers (hold stable until cpl_ready_i accept)
    reg [15:0] cpl_status_q;
    reg [15:0] cpl_cid_q;
    reg [ 7:0] cpl_sqid_q;
    reg        cpl_has_data_q;

    // ======================================================================
    // Wires
    // ======================================================================
    wire        is_ident;           // Opcode is Identify
    wire        is_ident_valid_cns; // CNS is 0x00 or 0x01 (produces data)
    wire        is_create_cq;       // Opcode is Create I/O CQ
    wire        is_create_sq;       // Opcode is Create I/O SQ
    wire        create_qid_ok;      // QID > 0 and QID < MAX_QUEUES
    wire        create_qsize_ok;    // QSIZE <= MQES
    wire        create_cqid_ok;     // CQID < MAX_QUEUES (for SQ)
    wire        queue_alloc_req;    // Valid create command in DECODE

    // Beat counter control
    reg         beat_count_load;
    reg         beat_count_inc;
    wire        data_xfer_active;   // Handshake in progress (data consumed)
    wire        data_xfer_done;     // All beats transferred

    // ======================================================================
    // Combinational helpers
    // ======================================================================
    assign is_ident           = (opcode_q == OPC_IDENTIFY);
    assign is_ident_valid_cns = (cdw10_q[7:0] == CNS_CONTROLLER)
                              | (cdw10_q[7:0] == CNS_NAMESPACE);
    assign is_create_cq       = (opcode_q == OPC_CREATE_CQ);
    assign is_create_sq       = (opcode_q == OPC_CREATE_SQ);

    // Validation checks
    assign create_qid_ok   = (cdw10_q[15:0] > 16'd0)
                           && (cdw10_q[15:0] < MAX_QUEUES);
    assign create_qsize_ok = (cdw10_q[31:16] <= MQES);
    assign create_cqid_ok  = (cdw11_q[15:4] < MAX_QUEUES);

    // Queue allocation request: valid create command in DECODE state
    assign queue_alloc_req = is_create_cq | is_create_sq;

    // Data transfer
    assign data_xfer_active = cq_data_valid_o & cq_data_ready_i;
    assign data_xfer_done   = data_xfer_active & (beat_count_q == IDENT_BEAT_MAX);

    // ======================================================================
    // FSM: Next-state logic (combinational process)
    // ======================================================================
    always @(*) begin
        state_d         = state_q;
        beat_count_load = 1'b0;
        beat_count_inc  = 1'b0;

        case (state_q)

            // ------------------------------------------------
            // IDLE: Wait for valid command with CQ post ready
            // ------------------------------------------------
            IDLE: begin
                if (cmd_valid_i & cpl_ready_i) begin
                    state_d = DECODE;
                end
            end

            // ------------------------------------------------
            // DECODE: Opcode decode (1 cycle)
            // ------------------------------------------------
            DECODE: begin
                if (is_ident) begin
                    if (is_ident_valid_cns) begin
                        state_d         = DATA_XFER;
                        beat_count_load = 1'b1;
                    end else begin
                        state_d = CPL_OUT;
                    end
                end else if (is_create_cq | is_create_sq) begin
                    // Validate, then go to CPL_OUT
                    state_d = CPL_OUT;
                end else begin
                    // Unknown opcode → error
                    state_d = CPL_OUT;
                end
            end

            // ------------------------------------------------
            // DATA_XFER: 512 beats of Identify data output
            // ------------------------------------------------
            DATA_XFER: begin
                if (data_xfer_done) begin
                    state_d = CPL_OUT;
                end else if (data_xfer_active) begin
                    beat_count_inc = 1'b1;
                end
            end

            // ------------------------------------------------
            // CPL_OUT: Output completion, wait for accept
            // ------------------------------------------------
            CPL_OUT: begin
                if (cpl_ready_i) begin
                    state_d = IDLE;
                end
            end

        endcase
    end

    // ======================================================================
    // FSM: Sequential process (all registers reset per P3)
    // ======================================================================
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q       <= IDLE;
            opcode_q      <= 8'd0;
            cid_q         <= 16'd0;
            nsid_q        <= 32'd0;
            prp1_q        <= 64'd0;
            prp2_q        <= 64'd0;
            cdw10_q       <= 32'd0;
            cdw11_q       <= 32'd0;
            sqid_q        <= 8'd0;
            beat_count_q  <= 9'd0;
            cpl_status_q  <= 16'd0;
            cpl_cid_q     <= 16'd0;
            cpl_sqid_q    <= 8'd0;
            cpl_has_data_q <= 1'b0;
        end else begin
            state_q <= state_d;

            // ----------------------------------------------------------
            // Command field capture: latch all fields when accepted
            // ----------------------------------------------------------
            if (state_q == IDLE & cmd_valid_i & cmd_ready_o) begin
                opcode_q <= cmd_opcode_i;
                cid_q    <= cmd_cid_i;
                nsid_q   <= cmd_nsid_i;
                prp1_q   <= cmd_prp1_i;
                prp2_q   <= cmd_prp2_i;
                cdw10_q  <= cmd_cdw10_i;
                cdw11_q  <= cmd_cdw11_i;
                sqid_q   <= cmd_sqid_i;
            end

            // ----------------------------------------------------------
            // Beat counter: load at start of DATA_XFER, inc on handshake
            // ----------------------------------------------------------
            if (beat_count_load) begin
                beat_count_q <= 9'd0;
            end else if (beat_count_inc) begin
                beat_count_q <= beat_count_q + 9'd1;
            end

            // ----------------------------------------------------------
            // Completion field capture: latched in DECODE state
            // ----------------------------------------------------------
            if (state_q == DECODE) begin
                cpl_cid_q     <= cid_q;
                cpl_sqid_q    <= sqid_q;
                cpl_has_data_q <= is_ident & is_ident_valid_cns;

                // Status code decode
                if (is_ident) begin
                    if (is_ident_valid_cns) begin
                        cpl_status_q <= STATUS_SUCCESS;
                    end else begin
                        cpl_status_q <= STATUS_INVALID_FIELD;
                    end
                end else if (is_create_cq | is_create_sq) begin
                    if (!create_qid_ok) begin
                        cpl_status_q <= STATUS_INVALID_QID;
                    end else if (!create_qsize_ok) begin
                        cpl_status_q <= STATUS_INVALID_QSIZE;
                    end else if (is_create_sq & !create_cqid_ok) begin
                        cpl_status_q <= STATUS_INVALID_CREATE;
                    end else begin
                        cpl_status_q <= STATUS_SUCCESS;
                    end
                end else begin
                    cpl_status_q <= STATUS_INVALID_OP;
                end
            end

        end
    end

    // ======================================================================
    // Identify Controller Data Generation
    //
    // Returns the 64-bit data word for a given beat index (0..511).
    // Based on NVMe Identify Controller data structure (NVMe Base Spec 1.4c
    // Figure 169) with only key fields populated; all others return 0.
    //
    // Key field offsets:
    //   0x000      VID=0xCA5E (2 bytes) + reserved (2 bytes)
    //   0x004-0x017 SN="NVMe-SSD-00001" padded to 20 with spaces
    //   0x018-0x03F MN="Digital Front-End NVMe Ctrl" padded to 40 with spaces
    //   0x040-0x047 FR="v1.0" padded to 8 with spaces
    //   0x100-0x101 SQES=0x40(64=2^6) + CQES=0x10(16=2^4)
    //   0x200-0x203 NN=1 (Number of Namespaces)
    //
    // Data bytes within each 64-bit word are stored little-endian:
    //   data[7:0]   = byte at PRP1 + beat*8 + 0
    //   data[15:8]  = byte at PRP1 + beat*8 + 1
    //   ...
    //   data[63:56] = byte at PRP1 + beat*8 + 7
    // ======================================================================
    function [63:0] ident_ctrl_data;
        input [8:0] beat;
        begin
            case (beat)
                // Beat 0 (offset 0x00): VID=0xCA5E at bytes 0-1, reserved at 2-3,
                //                        SN[0:3]="NVMe" at bytes 4-7
                9'd0:   ident_ctrl_data = 64'h654D564E_0000CA5E;

                // Beat 1 (offset 0x08): SN[4:11]="-SSD-000"
                9'd1:   ident_ctrl_data = 64'h3030302D_4453532D;

                // Beat 2 (offset 0x10): SN[12:19]="01      " (padded with spaces)
                9'd2:   ident_ctrl_data = 64'h20202020_20203130;

                // Beat 3 (offset 0x18): MN[0:7]="Digital "
                9'd3:   ident_ctrl_data = 64'h206C6174_69676944;

                // Beat 4 (offset 0x20): MN[8:15]="Front-En"
                9'd4:   ident_ctrl_data = 64'h6E452D74_6E6F7246;

                // Beat 5 (offset 0x28): MN[16:23]="d NVMe C"
                9'd5:   ident_ctrl_data = 64'h4320654D_564E2064;

                // Beat 6 (offset 0x30): MN[24:26]="trl" + 5 pad spaces
                9'd6:   ident_ctrl_data = 64'h20202020_206C7274;

                // Beat 7 (offset 0x38): MN padding remaining 8 spaces
                9'd7:   ident_ctrl_data = 64'h20202020_20202020;

                // Beat 8 (offset 0x40): FR="v1.0" + 4 pad spaces
                9'd8:   ident_ctrl_data = 64'h20202020_302E3176;

                // Beat 32 (offset 0x100): SQES=0x40, CQES=0x10
                9'd32:  ident_ctrl_data = 64'h0000_0000_0000_1040;

                // Beat 64 (offset 0x200): NN=1 (Number of Namespaces)
                9'd64:  ident_ctrl_data = 64'h0000_0000_0000_0001;

                default: ident_ctrl_data = 64'd0;
            endcase
        end
    endfunction

    // ======================================================================
    // Identify Namespace Data Generation
    //
    // Minimal valid namespace data (NVMe Base Spec 1.4c Figure 176).
    // Returns 4096 bytes (512 beats). Key fields:
    //   0x000-0x007 NSZE=1 (Namespace Size, 1 block)
    //   0x008-0x00F NCAP=1 (Namespace Capacity)
    //   All other fields=0
    // ======================================================================
    function [63:0] ident_ns_data;
        input [8:0] beat;
        begin
            case (beat)
                9'd0:   ident_ns_data = 64'd1;  // NSZE = 1
                9'd1:   ident_ns_data = 64'd1;  // NCAP = 1
                default: ident_ns_data = 64'd0;
            endcase
        end
    endfunction

    // ======================================================================
    // Output assignments (single-bit FSM control where applicable)
    // ======================================================================

    // -----------------------------------------------
    // cmd_ready: accept when idle AND CQ post is ready
    // -----------------------------------------------
    assign cmd_ready_o = (state_q == IDLE) & cpl_ready_i;

    // -----------------------------------------------
    // Data write interface (Identify data output)
    // -----------------------------------------------
    assign cq_data_wr_o     = (state_q == DATA_XFER);
    assign cq_data_valid_o  = (state_q == DATA_XFER);
    assign cq_data_last_o   = (state_q == DATA_XFER)
                           & (beat_count_q == IDENT_BEAT_MAX);
    assign cq_data_addr_o   = prp1_q + {beat_count_q, 3'd0};  // beat * 8

    // Data word: select between Controller and Namespace data
    assign cq_data_o        = (state_q == DATA_XFER)
                            ? ((cdw10_q[7:0] == CNS_CONTROLLER)
                               ? ident_ctrl_data(beat_count_q)
                               : ident_ns_data(beat_count_q))
                            : 64'd0;

    // -----------------------------------------------
    // Completion interface (to CQ post engine)
    // -----------------------------------------------
    assign cpl_valid_o   = (state_q == CPL_OUT);
    assign cpl_sqid_o    = cpl_sqid_q;
    assign cpl_sqhd_o    = 16'd0;   // Externally connected from sq_fetch head_update
    assign cpl_cid_o     = cpl_cid_q;
    assign cpl_status_o  = cpl_status_q;
    assign cpl_has_data_o = cpl_has_data_q;

    // -----------------------------------------------
    // Queue allocation (pulse during DECODE for valid creates)
    // -----------------------------------------------
    assign queue_alloc_o = (state_q == DECODE)
                         & (is_create_cq | is_create_sq)
                         & create_qid_ok & create_qsize_ok
                         & (!is_create_sq | create_cqid_ok);
    assign queue_id_o    = cdw10_q[ 7:0];    // QID[7:0]
    assign queue_depth_o = cdw10_q[31:16] + 16'd1;  // QSIZE + 1 (1-based)
    assign queue_is_sq_o = is_create_sq;
    assign queue_cqid_o  = cdw11_q[15:4];    // CQID for SQ creates

endmodule

`default_nettype wire
