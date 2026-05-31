`default_nettype none

// ============================================================================
// fork_join_pipeline — Split-Path Pipeline with Completion Join
// Validates Split-Merge (§4) + Feedback Completion (§2) pipeline patterns.
//
// FSM-free design: splitter feeds 2-stage pipeline continuously.
// Joiner sets pkt_done (sticky level flag) when TLAST exits pipeline
// AND stats alignment delay expires. Cleared on next packet start.
// ============================================================================

module fork_join_pipeline #(
    parameter DATA_WIDTH      = 8,
    parameter PIPELINE_STAGES = 2
) (
    input  wire                  clk_i,
    input  wire                  rst_ni,
    input  wire                  s_axis_tvalid_i,
    output wire                  s_axis_tready_o,
    input  wire [DATA_WIDTH-1:0] s_axis_tdata_i,
    input  wire                  s_axis_tlast_i,
    output wire                  m_axis_tvalid_o,
    input  wire                  m_axis_tready_i,
    output wire [DATA_WIDTH-1:0] m_axis_tdata_o,
    output wire                  m_axis_tlast_o,
    output reg                   pkt_done_o,
    output wire [7:0]            beat_count_o
);

    // Pipeline registers (2-stage feed-forward)
    reg                     s0_valid_q;
    reg [DATA_WIDTH-1:0]    s0_data_q;
    reg                     s0_tlast_q;
    reg                     s1_valid_q;
    reg [DATA_WIDTH-1:0]    s1_data_q;
    reg                     s1_tlast_q;

    // Stats path
    reg [7:0]               beat_cnt_q;
    reg [7:0]               final_beats_q;

    // Completion tracking (FSM-free)
    reg                     pkt_in_flight_q;  // true while packet is in pipeline

    // Splitter: accept whenever stage 0 is empty
    assign s_axis_tready_o = !s0_valid_q;
    wire split_accept = s_axis_tvalid_i && s_axis_tready_o;

    // Stage 0 → Stage 1 data movement
    wire s1_not_stalled = m_axis_tready_i;
    wire s0_to_s1 = s0_valid_q && s1_not_stalled;

    // Stage 0: capture new data when empty, or when data moves to s1
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            s0_valid_q <= 1'b0;
            s0_data_q  <= {DATA_WIDTH{1'b0}};
            s0_tlast_q <= 1'b0;
        end else if (s0_to_s1 || !s0_valid_q) begin
            s0_valid_q <= split_accept;
            s0_data_q  <= s_axis_tdata_i;
            s0_tlast_q <= s_axis_tlast_i;
        end
    end

    // Stage 1: capture from s0 when not stalled (hold when stalled)
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            s1_valid_q <= 1'b0;
            s1_data_q  <= {DATA_WIDTH{1'b0}};
            s1_tlast_q <= 1'b0;
        end else if (s1_not_stalled) begin
            s1_valid_q <= s0_valid_q;
            s1_data_q  <= s0_data_q;
            s1_tlast_q <= s0_tlast_q;
        end
    end

    assign m_axis_tvalid_o = s1_valid_q;
    assign m_axis_tdata_o  = s1_data_q;
    assign m_axis_tlast_o  = s1_tlast_q;
    assign beat_count_o    = final_beats_q;

    // Joiner: pipeline TLAST output with stats aligned
    wire pipe_tlast_out = s1_valid_q && s1_tlast_q && m_axis_tready_i;

    // Completion tracking: set/clear pkt_done and pkt_in_flight
    // Joiner fires when pipeline outputs TLAST — beat_cnt is naturally
    // aligned because it accumulates on input acceptance events.
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pkt_in_flight_q <= 1'b0;
            pkt_done_o      <= 1'b0;
            beat_cnt_q      <= 8'd0;  // redundant but safe
            final_beats_q   <= 8'd0;
        end else begin
            // Start tracking when first beat enters pipeline
            if (split_accept && !pkt_in_flight_q) begin
                pkt_in_flight_q <= 1'b1;
                pkt_done_o      <= 1'b0;   // clear done from previous packet
                beat_cnt_q      <= 8'd1;
                if (s_axis_tlast_i)
                    final_beats_q <= 8'd1;  // single-beat packet
            end else if (split_accept && pkt_in_flight_q) begin
                beat_cnt_q      <= beat_cnt_q + 8'd1;
                if (s_axis_tlast_i)
                    final_beats_q <= beat_cnt_q + 8'd1;
            end

            // Complete when TLAST exits pipeline AND stats aligned
            if (pkt_in_flight_q && pipe_tlast_out) begin
                pkt_in_flight_q <= 1'b0;
                pkt_done_o      <= 1'b1;   // sticky level flag
            end
        end
    end

endmodule

`default_nettype wire
