`default_nettype none

// ============================================================================
// Module: nvme_sq_fetch
//
// NVMe Submission Queue Fetch Engine.
// Fetches 64-byte Submission Queue Entries (SQE) from host memory via 8-beat
// AXI read bursts, assembles them into a 512-bit buffer, parses the command
// fields, and outputs structured commands to the admin executor.
//
// FSM: IDLE -> AR_REQ -> R_BEAT (x8) -> PARSE -> CMD_OUT -> UPDATE_HEAD
//   - IDLE:        Wait for credits_q > 0 (commands pending to fetch)
//   - AR_REQ:      Issue AXI read address (sq_base + head*64, 8-beat burst)
//   - R_BEAT:      Accumulate 8 x 64-bit data beats into fetch_buf
//   - PARSE:       Combinational extraction of all command fields (1 cycle)
//   - CMD_OUT:     Present parsed command, wait for cmd_ready_i
//   - UPDATE_HEAD: Advance head pointer, decrement credits_q
//
// SQE Byte Layout (NVMe Base Spec 1.4c):
//   Bytes  0-3  (bits 31:0):     CDW0 -> opcode[7:0], cid[31:16]
//   Bytes  4-7  (bits 63:32):    NSID
//   Bytes 24-31 (bits 255:192):  PRP1
//   Bytes 32-39 (bits 319:256):  PRP2
//   Bytes 40-43 (bits 351:320):  CDW10
//   Bytes 44-47 (bits 383:352):  CDW11
//
// References:
//   - NVMe Base Spec 1.4c, Figure 41: Submission Queue Entry
//   - nvme-guidelines.md Section 3: SQE Format, Section 8: Memory Interface
//   - system-contract.md Module 2: nvme_sq_fetch
// ============================================================================

module nvme_sq_fetch (
    input  wire         clk_i,
    input  wire         rst_ni,

    // -------------------------------------
    // Queue Configuration
    // -------------------------------------
    input  wire [63:0]  sq_base_i,          // SQ physical base address
    input  wire [15:0]  sq_depth_i,         // SQ entries (1-based, e.g. 256)
    input  wire [ 7:0]  sq_id_i,            // This SQ's ID (0=admin, 1+=I/O)
    input  wire [ 7:0]  cq_id_i,            // Associated CQ ID (for routing)

    // -------------------------------------
    // Doorbell Credits
    // -------------------------------------
    input  wire [15:0]  credits_i,          // New credits from doorbell monitor
    input  wire         credits_valid_i,    // Pulse: credits_i is valid

    // -------------------------------------
    // Parsed Command Output (to admin executor)
    // -------------------------------------
    output wire         cmd_valid_o,
    input  wire         cmd_ready_i,
    output wire [ 7:0]  cmd_opcode_o,
    output wire [15:0]  cmd_cid_o,
    output wire [31:0]  cmd_nsid_o,
    output wire [63:0]  cmd_prp1_o,
    output wire [63:0]  cmd_prp2_o,
    output wire [31:0]  cmd_cdw10_o,
    output wire [31:0]  cmd_cdw11_o,
    output wire [ 7:0]  cmd_sqid_o,

    // -------------------------------------
    // AXI Read Address (to AXI adapter)
    // -------------------------------------
    output wire         axi_ar_valid_o,
    input  wire         axi_ar_ready_i,
    output wire [63:0]  axi_ar_addr_o,
    output wire [ 7:0]  axi_ar_len_o,
    output wire [ 2:0]  axi_ar_size_o,

    // -------------------------------------
    // AXI Read Data (from AXI adapter)
    // -------------------------------------
    input  wire         axi_r_valid_i,
    output wire         axi_r_ready_o,
    input  wire [63:0]  axi_r_data_i,
    input  wire         axi_r_last_i,

    // -------------------------------------
    // Head Tracking (to doorbell / credit mgmt)
    // -------------------------------------
    output wire [15:0]  head_update_o,
    output wire         head_update_valid_o
);

    // ----------------------------------------------------------
    // FSM State Encoding (6 states, two-process per skill rules)
    // ----------------------------------------------------------
    localparam [2:0] IDLE        = 3'd0;
    localparam [2:0] AR_REQ      = 3'd1;
    localparam [2:0] R_BEAT      = 3'd2;
    localparam [2:0] PARSE       = 3'd3;
    localparam [2:0] CMD_OUT     = 3'd4;
    localparam [2:0] UPDATE_HEAD = 3'd5;

    // ----------------------------------------------------------
    // Registered State (_q suffix per skill rules)
    // ----------------------------------------------------------
    reg [2:0]  state_q;
    reg [2:0]  state_d;

    reg [15:0] head_q;          // Current SQ head pointer
    reg [15:0] head_d;

    reg [15:0] credits_q;       // Accumulated fetch credits (tail - head)
    reg [15:0] credits_d;

    reg [2:0]  beat_cnt_q;      // Beat counter (0-7), reset on AR_REQ accept
    reg [2:0]  beat_cnt_d;

    reg [511:0] fetch_buf;      // 8 x 64-bit assembled SQE buffer

    // ----------------------------------------------------------
    // Wires
    // ----------------------------------------------------------
    wire        wrap;           // head_q at last slot of SQ (wraps to 0)
    wire [63:0] fetch_addr;     // sq_base + head * 64

    // Single-bit FSM control outputs (assigned outside sequential block)
    wire        fsm_ar_valid;
    wire        fsm_r_ready;
    wire        fsm_cmd_valid;
    wire        fsm_head_update_valid;

    // ----------------------------------------------------------
    // Combinational helpers
    // ----------------------------------------------------------
    assign wrap       = (head_q == sq_depth_i - 16'd1);
    assign fetch_addr = sq_base_i + {head_q, 6'd0};   // head_q << 6

    // ----------------------------------------------------------
    // FSM: Next-state logic (combinational process)
    // ----------------------------------------------------------
    always @(*) begin
        state_d    = state_q;
        head_d     = head_q;
        credits_d  = credits_q;
        beat_cnt_d = beat_cnt_q;

        case (state_q)

            // ------------------------------------------------
            // IDLE: Wait for pending credits
            // ------------------------------------------------
            IDLE: begin
                if (credits_q > 16'd0) begin
                    state_d = AR_REQ;
                end
            end

            // ------------------------------------------------
            // AR_REQ: Issue AXI read address
            // ------------------------------------------------
            AR_REQ: begin
                if (axi_ar_ready_i) begin
                    state_d    = R_BEAT;
                    beat_cnt_d = 3'd0;
                end
            end

            // ------------------------------------------------
            // R_BEAT: Accumulate 8 x 64-bit data beats
            // ------------------------------------------------
            R_BEAT: begin
                if (axi_r_valid_i) begin
                    if (axi_r_last_i) begin
                        state_d = PARSE;
                    end else begin
                        state_d    = R_BEAT;
                        beat_cnt_d = beat_cnt_q + 3'd1;
                    end
                end
            end

            // ------------------------------------------------
            // PARSE: Combinational extraction (1 cycle)
            // ------------------------------------------------
            PARSE: begin
                state_d = CMD_OUT;
            end

            // ------------------------------------------------
            // CMD_OUT: Present parsed command, wait for accept
            // ------------------------------------------------
            CMD_OUT: begin
                if (cmd_ready_i) begin
                    state_d = UPDATE_HEAD;
                end
            end

            // ------------------------------------------------
            // UPDATE_HEAD: Advance head, decrement credits
            // ------------------------------------------------
            UPDATE_HEAD: begin
                head_d    = wrap ? 16'd0 : head_q + 16'd1;
                credits_d = credits_q - 16'd1;
                // After decrement, if credits still > 0, start next fetch
                state_d   = (credits_q > 16'd1) ? AR_REQ : IDLE;
            end

        endcase
    end

    // ----------------------------------------------------------
    // FSM: Sequential process (all registers reset per P3)
    // ----------------------------------------------------------
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q    <= IDLE;
            head_q     <= 16'd0;
            credits_q  <= 16'd0;
            beat_cnt_q <= 3'd0;
            // fetch_buf is data storage — no reset needed
        end else begin
            state_q    <= state_d;
            head_q     <= head_d;
            beat_cnt_q <= beat_cnt_d;

            // ----------------------------------------------------------
            // Credits accounting:
            //   - Increment on doorbell credit pulse (credits_valid_i)
            //   - Decrement on UPDATE_HEAD (credit consumed by fetch)
            //   - Both can happen in same cycle — handle with priority
            // ----------------------------------------------------------
            if (credits_valid_i && (state_q == UPDATE_HEAD)) begin
                credits_q <= credits_q + credits_i - 16'd1;
            end else if (credits_valid_i) begin
                credits_q <= credits_q + credits_i;
            end else begin
                credits_q <= credits_d;   // from FSM (decrement in UPDATE_HEAD)
            end

            // ----------------------------------------------------------
            // Fetch buffer: accumulate beat data into indexed slot
            // Uses indexed part-select: fetch_buf[beat*64 +: 64]
            // ----------------------------------------------------------
            if (state_q == R_BEAT && axi_r_valid_i) begin
                fetch_buf[beat_cnt_q*64 +: 64] <= axi_r_data_i;
            end

        end
    end

    // ----------------------------------------------------------
    // Control outputs (single-bit FSM outputs per skill rules)
    // ----------------------------------------------------------

    // AXI Read Address
    assign fsm_ar_valid   = (state_q == AR_REQ);
    assign axi_ar_valid_o = fsm_ar_valid;
    assign axi_ar_addr_o  = fetch_addr;
    assign axi_ar_len_o   = 8'd7;      // 8 beats - 1
    assign axi_ar_size_o  = 3'd3;      // 8 bytes per beat

    // AXI Read Data
    assign fsm_r_ready    = (state_q == R_BEAT);
    assign axi_r_ready_o  = fsm_r_ready;

    // Command output
    assign fsm_cmd_valid  = (state_q == CMD_OUT);
    assign cmd_valid_o    = fsm_cmd_valid;

    // Head tracking
    assign fsm_head_update_valid = (state_q == UPDATE_HEAD);
    assign head_update_valid_o   = fsm_head_update_valid;
    // Updated head value (combinationally: the value being assigned to head_q)
    assign head_update_o         = wrap ? 16'd0 : head_q + 16'd1;

    // SQ ID echo for command routing
    assign cmd_sqid_o     = sq_id_i;

    // ----------------------------------------------------------
    // Command field extraction (combinational from fetch_buf)
    //
    // SQE byte layout (little-endian, byte 0 = LSB of fetch_buf[63:0]):
    //   CDW0[7:0]   = OPC   at bytes 0-3, bits [7:0]
    //   CDW0[31:16] = CID   at bytes 0-3, bits [31:16]
    //   DW1         = NSID  at bytes 4-7
    //   DW6-7       = PRP1  at bytes 24-31
    //   DW8-9       = PRP2  at bytes 32-39
    //   DW10        = CDW10 at bytes 40-43
    //   DW11        = CDW11 at bytes 44-47
    // ----------------------------------------------------------
    assign cmd_opcode_o = fetch_buf[7:0];
    assign cmd_cid_o    = fetch_buf[31:16];
    assign cmd_nsid_o   = fetch_buf[63:32];
    assign cmd_prp1_o   = fetch_buf[255:192];
    assign cmd_prp2_o   = fetch_buf[319:256];
    assign cmd_cdw10_o  = fetch_buf[351:320];
    assign cmd_cdw11_o  = fetch_buf[383:352];

endmodule

`default_nettype wire
