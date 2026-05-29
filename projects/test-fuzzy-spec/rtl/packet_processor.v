`default_nettype none

// Packet Processor Module
//
// AXI-Stream packet processor with CRC-32 checking and 4-channel output routing.
//
// == Packet format ==
//   Beat 0:           Header[31:0]  — header[1:0] selects output channel (0-3)
//   Beats 1 .. N-2:   Payload       — variable length, 32-bit beats
//   Beat N-1 (TLAST): CRC-32       — IEEE 802.3 CRC over header+payload
//
// == Architecture ==
//   Store-and-forward: entire packet buffered in FIFO while CRC is computed.
//   On TLAST: CRC compared. Good → drain FIFO to selected channel. Bad → FIFO flush + error.
//
// == Timing contract ==
//   Clock:         single clock (clk_i)
//   Reset:         synchronous active-high (rst_i)
//   Input:         AXI-Stream ready/valid, DATA_WIDTH bits per beat
//   Output:        4 x AXI-Stream, same width
//   Latency:       N beats receive + 1 CRC cycle + N beats drain = ~2N+1 cycles per packet
//   Stall:         Input stalls when FIFO full; output stalls on channel backpressure
//   Flush:         Bad CRC → FIFO flush (instant pointer reset), next packet accepted immediately
//
// == Assumptions (from underspecified requirements) ==
//   - CRC-32 / IEEE 802.3 (polynomial 0x04C11DB7)
//   - Header = first beat of packet, bits [1:0] = channel
//   - Packet min = 2 beats (8 bytes), max = MAX_PACKET_BEATS beats (4096 bytes default)
//   - All byte lanes valid (TKEEP = all-1s for valid beats)
//   - Channel values 0-3 map directly to 4 output ports
//   - Bad CRC: packet dropped, no forwarding
//
// == Features added ==
//   - Bad CRC counter (32-bit)
//   - Good packet counter (32-bit)
//   - Per-channel packet counters (32-bit each)
//   - Overflow detection (FIFO full during reception = assert overflow)

module packet_processor #(
    parameter DATA_WIDTH       = 32,
    parameter TKEEP_WIDTH      = DATA_WIDTH / 8,
    parameter NUM_CHANNELS     = 4,
    parameter MAX_PACKET_BEATS = 256,   // max beats per packet (1024 bytes at 32b)
    parameter CRC_POLYNOMIAL   = 32'h04C11DB7
) (
    input  wire                    clk_i,
    input  wire                    rst_i,

    // === Input AXI-Stream ===
    input  wire                    s_axis_tvalid_i,
    output wire                    s_axis_tready_o,
    input  wire [DATA_WIDTH-1:0]   s_axis_tdata_i,
    input  wire [TKEEP_WIDTH-1:0]  s_axis_tkeep_i,
    input  wire                    s_axis_tlast_i,

    // === Output AXI-Stream channels 0-3 ===
    output reg                     m_axis_tvalid_o_0,
    input  wire                    m_axis_tready_i_0,
    output reg  [DATA_WIDTH-1:0]   m_axis_tdata_o_0,
    output reg  [TKEEP_WIDTH-1:0]  m_axis_tkeep_o_0,
    output reg                     m_axis_tlast_o_0,

    output reg                     m_axis_tvalid_o_1,
    input  wire                    m_axis_tready_i_1,
    output reg  [DATA_WIDTH-1:0]   m_axis_tdata_o_1,
    output reg  [TKEEP_WIDTH-1:0]  m_axis_tkeep_o_1,
    output reg                     m_axis_tlast_o_1,

    output reg                     m_axis_tvalid_o_2,
    input  wire                    m_axis_tready_i_2,
    output reg  [DATA_WIDTH-1:0]   m_axis_tdata_o_2,
    output reg  [TKEEP_WIDTH-1:0]  m_axis_tkeep_o_2,
    output reg                     m_axis_tlast_o_2,

    output reg                     m_axis_tvalid_o_3,
    input  wire                    m_axis_tready_i_3,
    output reg  [DATA_WIDTH-1:0]   m_axis_tdata_o_3,
    output reg  [TKEEP_WIDTH-1:0]  m_axis_tkeep_o_3,
    output reg                     m_axis_tlast_o_3,

    // === Status ===
    output wire                    bad_crc_o,     // pulse: bad CRC detected
    output wire                    overflow_o,    // pulse: FIFO overflow during receive
    output wire [31:0]             good_pkt_cnt_o,
    output wire [31:0]             bad_pkt_cnt_o,
    output wire [31:0]             ch_pkt_cnt_o_0,
    output wire [31:0]             ch_pkt_cnt_o_1,
    output wire [31:0]             ch_pkt_cnt_o_2,
    output wire [31:0]             ch_pkt_cnt_o_3
);

    // =========================================================================
    // Local parameters
    // =========================================================================
    localparam ADDR_W   = $clog2(MAX_PACKET_BEATS);
    localparam FIFO_DW  = DATA_WIDTH + TKEEP_WIDTH + 1;  // {tlast, tkeep, tdata}
    localparam TDATA_LS = 0;
    localparam TKEEP_LS = DATA_WIDTH;
    localparam TLAST_P  = DATA_WIDTH + TKEEP_WIDTH;

    // FSM states (binary encoding, 5 states → 3 bits)
    localparam ST_IDLE  = 3'd0;
    localparam ST_RECV  = 3'd1;
    localparam ST_CHK   = 3'd2;
    localparam ST_DRAIN = 3'd3;
    localparam ST_DROP  = 3'd4;

    // =========================================================================
    // Wires
    // =========================================================================

    // FIFO signals
    wire [FIFO_DW-1:0] fifo_wdata;
    wire                fifo_wr_en;
    wire                fifo_full;
    wire [FIFO_DW-1:0] fifo_rdata;
    wire                fifo_rd_en;
    wire                fifo_empty;
    wire                fifo_flush;
    wire [ADDR_W:0]     fifo_count;

    // CRC pipeline signals
    wire                crc_valid;
    wire [31:0]         crc_value;
    wire                crc_accept_all;

    // Input handshake
    wire                accept_input;

    // Output drain signals
    wire                drain_active;
    wire                drain_accept;
    wire                drain_do;
    wire                drain_done;

    // CRC comparison
    reg  [31:0]         rcvd_crc_q;
    wire                crc_match;

    // =========================================================================
    // Input acceptance
    // =========================================================================

    // Accept input when in a receiving state and FIFO has space
    assign accept_input = s_axis_tvalid_i && s_axis_tready_o;
    assign s_axis_tready_o = (state_q == ST_IDLE || state_q == ST_RECV)
                              && (fifo_count < MAX_PACKET_BEATS[ADDR_W:0]);

    // =========================================================================
    // FIFO write data (includes tlast, tkeep, tdata)
    // =========================================================================

    assign fifo_wdata = {s_axis_tlast_i, s_axis_tkeep_i, s_axis_tdata_i};
    assign fifo_wr_en = accept_input;

    // =========================================================================
    // FSM: state register + next state combinational (two-process)
    // =========================================================================

    reg [2:0] state_q;
    reg [2:0] state_d;

    // Single-bit enables (FSM outputs)
    reg capture_hdr;
    reg save_rcvd_crc;
    reg start_drain;
    reg do_flush;
    reg pulse_bad_crc;
    reg pulse_overflow;
    reg inc_good;
    reg inc_bad;

    // State register
    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= ST_IDLE;
        end else begin
            state_q <= state_d;
        end
        end

    // FSM combinational
    always @(*) begin
        // Defaults
        state_d        = state_q;
        capture_hdr    = 1'b0;
        save_rcvd_crc  = 1'b0;
        start_drain    = 1'b0;
        do_flush       = 1'b0;
        pulse_bad_crc  = 1'b0;
        pulse_overflow = 1'b0;
        inc_good       = 1'b0;
        inc_bad        = 1'b0;

        case (state_q)
            ST_IDLE: begin
                if (s_axis_tvalid_i && s_axis_tready_o) begin
                    capture_hdr = 1'b1;
                    state_d     = ST_RECV;
                end
            end

            ST_RECV: begin
                if (s_axis_tvalid_i && s_axis_tready_o) begin
                    if (s_axis_tlast_i) begin
                        save_rcvd_crc = 1'b1;
                        state_d       = ST_CHK;
                    end
                end
                // Overflow detection: if FIFO full while still receiving
                if (fifo_full && s_axis_tvalid_i) begin
                    pulse_overflow = 1'b1;
                end
            end

            ST_CHK: begin
                if (crc_valid) begin
                    if (crc_match) begin
                        inc_good    = 1'b1;
                        start_drain = 1'b1;
                        state_d     = ST_DRAIN;
                    end else begin
                        inc_bad      = 1'b1;
                        pulse_bad_crc = 1'b1;
                        do_flush     = 1'b1;
                        state_d      = ST_DROP;
                    end
                end else begin
                    // CRC not ready yet (shouldn't happen — CRC valid 1 cycle after TLAST)
                    state_d = ST_CHK;
                end
            end

            ST_DRAIN: begin
                // drain_do && out_tlast means last beat accepted
                // drain_active is the registered activity signal
                if (drain_done) begin
                    state_d = ST_IDLE;
                end
            end

            ST_DROP: begin
                // Flush is instant (resets FIFO pointers)
                state_d = ST_IDLE;
            end

            default: state_d = ST_IDLE;
        endcase
    end

    // =========================================================================
    // CRC pipeline instance (from skill reference)
    // =========================================================================

    assign crc_accept_all = 1'b1;

    crc_pipeline #(
        .DATA_W(DATA_WIDTH),
        .CRC_W (32)
    ) u_crc (
        .clk     (clk_i),
        .rst     (rst_i),
        .valid_i (accept_input),
        .data_i  (s_axis_tdata_i),
        .last_i  (s_axis_tlast_i),
        .ready_o (),
        .valid_o (crc_valid),
        .crc_o   (crc_value),
        .ready_i (crc_accept_all)
    );

    // =========================================================================
    // Packet buffer FIFO (FWFT, with flush)
    // =========================================================================

    sync_fwft_fifo #(
        .DATA_WIDTH(FIFO_DW),
        .DEPTH     (MAX_PACKET_BEATS)
    ) u_pkt_fifo (
        .clk_i   (clk_i),
        .rst_i   (rst_i),
        .wr_en_i (fifo_wr_en),
        .wdata_i (fifo_wdata),
        .full_o  (fifo_full),
        .rdata_o (fifo_rdata),
        .rd_en_i (fifo_rd_en),
        .empty_o (fifo_empty),
        .flush_i (fifo_flush),
        .count_o (fifo_count)
    );

    assign fifo_flush = do_flush;

    // =========================================================================
    // Datapath registers (updated by single-bit FSM enables)
    // =========================================================================

    // Channel select from header
    reg [1:0] channel_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            channel_q <= 2'd0;
        end else if (capture_hdr) begin
            channel_q <= s_axis_tdata_i[1:0];  // header[1:0] = output channel
        end
    end

    // Received CRC (captured on TLAST)
    always @(posedge clk_i) begin
        if (rst_i) begin
            rcvd_crc_q <= 32'd0;
        end else if (save_rcvd_crc) begin
            rcvd_crc_q <= s_axis_tdata_i;  // last beat = received CRC
        end
    end

    // CRC comparison (combinational)
    assign crc_match = (rcvd_crc_q == crc_value);

    // Drain active: set by FSM, cleared when last beat drains
    reg drain_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            drain_q <= 1'b0;
        end else if (start_drain) begin
            drain_q <= 1'b1;
        end else if (drain_do && out_tlast) begin
            drain_q <= 1'b0;
        end
    end

    assign drain_active = drain_q;

    // =========================================================================
    // Output FIFO read and channel demux
    // =========================================================================

    wire out_tlast = fifo_rdata[TLAST_P];
    wire [TKEEP_WIDTH-1:0] out_tkeep = fifo_rdata[TKEEP_LS +: TKEEP_WIDTH];
    wire [DATA_WIDTH-1:0]  out_tdata = fifo_rdata[TDATA_LS +: DATA_WIDTH];

    // Per-channel ready signals
    wire [3:0] ch_ready;
    assign ch_ready[0] = m_axis_tready_i_0;
    assign ch_ready[1] = m_axis_tready_i_1;
    assign ch_ready[2] = m_axis_tready_i_2;
    assign ch_ready[3] = m_axis_tready_i_3;

    // Selected channel ready
    wire sel_ch_ready;
    assign sel_ch_ready = (channel_q == 2'd0) ? ch_ready[0] :
                          (channel_q == 2'd1) ? ch_ready[1] :
                          (channel_q == 2'd2) ? ch_ready[2] :
                          ch_ready[3];

    // Drain transfer: FIFO read happens when drain active and selected channel accepts
    // TVALID is asserted to the selected channel (per_ch_valid in output mux below)
    assign drain_accept = drain_active && sel_ch_ready;
    assign drain_do     = drain_accept && !fifo_empty;

    assign fifo_rd_en   = drain_do;

    // Drain done: last beat consumed and FIFO is now empty
    // We detect this by: last beat was accepted (drain_do && out_tlast)
    // In the same cycle, state_d transitions to IDLE
    assign drain_done = drain_do && out_tlast;

    // =========================================================================
    // Output mux: drive the selected channel's AXI-Stream signals
    // =========================================================================

    // Per-channel valid signals
    wire [3:0] per_ch_valid;
    assign per_ch_valid[0] = drain_active && (channel_q == 2'd0);
    assign per_ch_valid[1] = drain_active && (channel_q == 2'd1);
    assign per_ch_valid[2] = drain_active && (channel_q == 2'd2);
    assign per_ch_valid[3] = drain_active && (channel_q == 2'd3);

    always @(*) begin
        // Default: all outputs low
        m_axis_tvalid_o_0 = 1'b0; m_axis_tdata_o_0 = {DATA_WIDTH{1'b0}};
        m_axis_tkeep_o_0  = {TKEEP_WIDTH{1'b0}}; m_axis_tlast_o_0 = 1'b0;
        m_axis_tvalid_o_1 = 1'b0; m_axis_tdata_o_1 = {DATA_WIDTH{1'b0}};
        m_axis_tkeep_o_1  = {TKEEP_WIDTH{1'b0}}; m_axis_tlast_o_1 = 1'b0;
        m_axis_tvalid_o_2 = 1'b0; m_axis_tdata_o_2 = {DATA_WIDTH{1'b0}};
        m_axis_tkeep_o_2  = {TKEEP_WIDTH{1'b0}}; m_axis_tlast_o_2 = 1'b0;
        m_axis_tvalid_o_3 = 1'b0; m_axis_tdata_o_3 = {DATA_WIDTH{1'b0}};
        m_axis_tkeep_o_3  = {TKEEP_WIDTH{1'b0}}; m_axis_tlast_o_3 = 1'b0;

        if (drain_active) begin
            // Data is common to the selected channel
            case (channel_q)
                2'd0: begin
                    m_axis_tvalid_o_0 = 1'b1;
                    m_axis_tdata_o_0  = out_tdata;
                    m_axis_tkeep_o_0  = out_tkeep;
                    m_axis_tlast_o_0  = out_tlast;
                end
                2'd1: begin
                    m_axis_tvalid_o_1 = 1'b1;
                    m_axis_tdata_o_1  = out_tdata;
                    m_axis_tkeep_o_1  = out_tkeep;
                    m_axis_tlast_o_1  = out_tlast;
                end
                2'd2: begin
                    m_axis_tvalid_o_2 = 1'b1;
                    m_axis_tdata_o_2  = out_tdata;
                    m_axis_tkeep_o_2  = out_tkeep;
                    m_axis_tlast_o_2  = out_tlast;
                end
                2'd3: begin
                    m_axis_tvalid_o_3 = 1'b1;
                    m_axis_tdata_o_3  = out_tdata;
                    m_axis_tkeep_o_3  = out_tkeep;
                    m_axis_tlast_o_3  = out_tlast;
                end
                default: begin
                    // Invalid channel — drive nothing (defaults are 0)
                end
            endcase
        end
    end

    // =========================================================================
    // Status outputs: error pulses and counters
    // =========================================================================

    reg bad_crc_pulse_q;
    reg overflow_pulse_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            bad_crc_pulse_q <= 1'b0;
        end else begin
            bad_crc_pulse_q <= pulse_bad_crc;
        end
    end
    assign bad_crc_o = bad_crc_pulse_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            overflow_pulse_q <= 1'b0;
        end else begin
            overflow_pulse_q <= pulse_overflow;
        end
    end
    assign overflow_o = overflow_pulse_q;

    // Good packet counter
    reg [31:0] good_cnt_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            good_cnt_q <= 32'd0;
        end else if (inc_good) begin
            good_cnt_q <= good_cnt_q + 32'd1;
        end
    end
    assign good_pkt_cnt_o = good_cnt_q;

    // Bad packet counter
    reg [31:0] bad_cnt_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            bad_cnt_q <= 32'd0;
        end else if (inc_bad) begin
            bad_cnt_q <= bad_cnt_q + 32'd1;
        end
    end
    assign bad_pkt_cnt_o = bad_cnt_q;

    // Per-channel counters
    reg [31:0] ch_cnt_q_0;
    reg [31:0] ch_cnt_q_1;
    reg [31:0] ch_cnt_q_2;
    reg [31:0] ch_cnt_q_3;

    always @(posedge clk_i) begin
        if (rst_i) begin
            ch_cnt_q_0 <= 32'd0;
        end else if (inc_good && channel_q == 2'd0) begin
            ch_cnt_q_0 <= ch_cnt_q_0 + 32'd1;
        end
    end
    assign ch_pkt_cnt_o_0 = ch_cnt_q_0;

    always @(posedge clk_i) begin
        if (rst_i) begin
            ch_cnt_q_1 <= 32'd0;
        end else if (inc_good && channel_q == 2'd1) begin
            ch_cnt_q_1 <= ch_cnt_q_1 + 32'd1;
        end
    end
    assign ch_pkt_cnt_o_1 = ch_cnt_q_1;

    always @(posedge clk_i) begin
        if (rst_i) begin
            ch_cnt_q_2 <= 32'd0;
        end else if (inc_good && channel_q == 2'd2) begin
            ch_cnt_q_2 <= ch_cnt_q_2 + 32'd1;
        end
    end
    assign ch_pkt_cnt_o_2 = ch_cnt_q_2;

    always @(posedge clk_i) begin
        if (rst_i) begin
            ch_cnt_q_3 <= 32'd0;
        end else if (inc_good && channel_q == 2'd3) begin
            ch_cnt_q_3 <= ch_cnt_q_3 + 32'd1;
        end
    end
    assign ch_pkt_cnt_o_3 = ch_cnt_q_3;

endmodule

`default_nettype wire
