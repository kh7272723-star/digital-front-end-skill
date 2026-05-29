`default_nettype none

// AXI-Stream serializer: 192-bit block -> 6 x 32-bit AXI-Stream beats.
//
// Clock domain: sys_clk (100MHz)
// Reset: sys_rst_i (active-high, synchronized)
//
// Reads 192-bit words from async FIFO (FWFT output) and serializes
// each word into 6 AXI-Stream beats of 32-bit TDATA each.
// TLAST is asserted on the 6th beat (beat index 5).
//
// ARCHITECTURE: The serializer uses a 192-bit data buffer that
// captures the FIFO output word on LOAD. All 6 beats are read
// from this buffer, NOT directly from the FIFO output. This
// eliminates timing dependencies between FIFO advancement and
// beat serialization.
//
// Flow (1 bubble cycle between words):
//   IDLE -> LOAD(capture + consume FIFO) -> SEND(beats 0..5) -> IDLE(bubble) -> ...
//
// The FIFO is consumed (rd_en=1) on the same cycle as buffer load.
// By the time the serializer finishes the last beat and returns to
// IDLE, the FIFO has already advanced to the next word (or reports empty).
//
// Module decomposition (SM1 pattern):
//   FSM combinational block -> single-bit enables only
//   Datapath registers -> synchronous blocks gated by enables

module axis_serializer (
    input  wire         sys_clk_i,
    input  wire         sys_rst_i,
    // From async FIFO (FWFT)
    input  wire [191:0] fifo_data_i,
    input  wire         fifo_empty_i,
    output wire         fifo_rd_en_o,
    // AXI-Stream master output
    output wire         m_axis_tvalid_o,
    input  wire         m_axis_tready_i,
    output wire [31:0]  m_axis_tdata_o,
    output wire         m_axis_tlast_o
);

    // -----------------------------------------------------------
    // FSM state encoding
    // -----------------------------------------------------------
    localparam IDLE = 2'd0;
    localparam SEND = 2'd1;

    // -----------------------------------------------------------
    // State and datapath registers
    // -----------------------------------------------------------
    reg        state_q;
    reg [2:0]  beat_q;          // 0..5
    reg        tvalid_q;
    reg [31:0] tdata_q;
    reg        fifo_rd_en_q;
    reg [191:0] data_buf_q;     // holds the current word for serialization

    // Single-bit enables from FSM
    reg        load_word;       // capture buffer, start TVALID, reset beat
    reg        advance;         // advance beat counter, update tdata

    // accept_output: beat consumed by downstream
    wire       accept_output = tvalid_q && m_axis_tready_i;

    // -----------------------------------------------------------
    // FSM combinational block
    // Per SM1: only single-bit enables, no multi-bit _d assignments
    // -----------------------------------------------------------
    reg state_d;
    reg load_word_r;
    reg advance_r;

    always @(*) begin
        state_d    = state_q;
        load_word_r = 1'b0;
        advance_r  = 1'b0;

        case (state_q)
            IDLE: begin
                if (!fifo_empty_i) begin
                    load_word_r = 1'b1;   // capture buffer, start sending
                    state_d     = SEND;
                end
            end

            SEND: begin
                if (accept_output) begin
                    if (beat_q == 3'd5) begin
                        // Last beat consumed: go to IDLE (bubble cycle)
                        state_d = IDLE;
                        // TVALID drops, letting FIFO output settle
                    end else begin
                        advance_r = 1'b1;  // increment beat
                    end
                end
            end

            default: state_d = IDLE;
        endcase
    end

    assign load_word = load_word_r;
    assign advance   = advance_r;

    // -----------------------------------------------------------
    // State register
    // -----------------------------------------------------------
    always @(posedge sys_clk_i) begin
        if (sys_rst_i)
            state_q <= IDLE;
        else
            state_q <= state_d;
    end

    // -----------------------------------------------------------
    // Data buffer: captures FIFO output on load_word
    // FIFO is consumed on the SAME cycle (rd_en = load_word)
    // After this, the buffer holds the word for all 6 beats.
    // -----------------------------------------------------------
    always @(posedge sys_clk_i) begin
        if (sys_rst_i) begin
            data_buf_q <= 192'd0;
        end else if (load_word) begin
            // Capture FWFT FIFO output BEFORE FIFO advances
            data_buf_q <= fifo_data_i;
        end
    end

    // -----------------------------------------------------------
    // FIFO read enable: pulse on load_word (consume current entry)
    // -----------------------------------------------------------
    always @(posedge sys_clk_i) begin
        if (sys_rst_i) begin
            fifo_rd_en_q <= 1'b0;
        end else begin
            fifo_rd_en_q <= load_word;  // consume FIFO on same cycle as buffer capture
        end
    end

    assign fifo_rd_en_o = fifo_rd_en_q;

    // -----------------------------------------------------------
    // Beat counter
    // -----------------------------------------------------------
    always @(posedge sys_clk_i) begin
        if (sys_rst_i) begin
            beat_q <= 3'd0;
        end else if (load_word) begin
            beat_q <= 3'd0;
        end else if (advance) begin
            beat_q <= beat_q + 3'd1;
        end
    end

    // -----------------------------------------------------------
    // TVALID register
    // -----------------------------------------------------------
    always @(posedge sys_clk_i) begin
        if (sys_rst_i) begin
            tvalid_q <= 1'b0;
        end else if (load_word) begin
            tvalid_q <= 1'b1;
        end else if (accept_output && (beat_q == 3'd5)) begin
            // Last beat consumed: drop tvalid (bubble before next word)
            tvalid_q <= 1'b0;
        end
    end

    // -----------------------------------------------------------
    // TDATA slice from buffer (combinational mux)
    // Selects 32-bit slice based on current beat.
    // -----------------------------------------------------------
    reg [31:0] tdata_slice;
    always @(*) begin
        case (beat_q)
            3'd0: tdata_slice = data_buf_q[31:0];
            3'd1: tdata_slice = data_buf_q[63:32];
            3'd2: tdata_slice = data_buf_q[95:64];
            3'd3: tdata_slice = data_buf_q[127:96];
            3'd4: tdata_slice = data_buf_q[159:128];
            3'd5: tdata_slice = data_buf_q[191:160];
            default: tdata_slice = 32'd0;
        endcase
    end

    // -----------------------------------------------------------
    // TDATA register (stable under backpressure, H1 compliant)
    // -----------------------------------------------------------
    always @(posedge sys_clk_i) begin
        if (sys_rst_i) begin
            tdata_q <= 32'd0;
        end else if (load_word) begin
            // First beat: capture slice 0 (from FIFO directly, since buffer
            // gets updated NBA and slice mux reads old buffer value)
            tdata_q <= fifo_data_i[31:0];
        end else if (advance) begin
            // Advance to next slice from current buffer
            // beat_q here is the CURRENT value (pre-advance)
            case (beat_q)
                3'd0: tdata_q <= data_buf_q[63:32];
                3'd1: tdata_q <= data_buf_q[95:64];
                3'd2: tdata_q <= data_buf_q[127:96];
                3'd3: tdata_q <= data_buf_q[159:128];
                3'd4: tdata_q <= data_buf_q[191:160];
                default: tdata_q <= 32'd0;
            endcase
        end
    end

    // -----------------------------------------------------------
    // Output assignments
    // -----------------------------------------------------------
    assign m_axis_tvalid_o = tvalid_q;
    assign m_axis_tdata_o  = tdata_q;
    // TLAST: combinational, asserted on beat 5
    assign m_axis_tlast_o  = (state_q == SEND) && (beat_q == 3'd5) && tvalid_q;

endmodule

`default_nettype wire
