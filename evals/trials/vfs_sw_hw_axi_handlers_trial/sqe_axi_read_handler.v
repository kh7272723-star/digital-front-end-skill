module sqe_axi_read_handler #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter LEN_W = 8,
    parameter ENTRY_COUNT_W = 3,
    parameter BEAT_COUNT_W = 9,
    parameter ENTRY_BEATS = 2
) (
    input  wire                       clk_i,
    input  wire                       rst_i,

    input  wire                       cmd_valid_i,
    output wire                       cmd_ready_o,
    input  wire [ADDR_W-1:0]          cmd_addr_i,
    input  wire [ENTRY_COUNT_W-1:0]   cmd_entry_count_i,

    output wire                       m_arvalid_o,
    input  wire                       m_arready_i,
    output wire [ADDR_W-1:0]          m_araddr_o,
    output wire [LEN_W-1:0]           m_arlen_o,

    input  wire                       m_rvalid_i,
    output wire                       m_rready_o,
    input  wire [DATA_W-1:0]          m_rdata_i,
    input  wire                       m_rlast_i,
    input  wire [1:0]                 m_rresp_i,

    output wire                       sqe_valid_o,
    input  wire                       sqe_ready_i,
    output wire [DATA_W-1:0]          sqe_data_o,
    output wire                       sqe_entry_last_o,

    output wire                       done_valid_o,
    input  wire                       done_ready_i,
    output wire                       error_o,
    output wire                       busy_o,
    output wire [BEAT_COUNT_W-1:0]    beats_rem_o
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_AR = 2'd1;
    localparam [1:0] S_R = 2'd2;
    localparam [1:0] S_DONE = 2'd3;

    localparam RESP_OKAY = 2'b00;
    localparam [BEAT_COUNT_W-1:0] ONE_BEAT = {{(BEAT_COUNT_W-1){1'b0}}, 1'b1};
    localparam [BEAT_COUNT_W-1:0] ENTRY_BEATS_COUNT = ENTRY_BEATS;

    reg [1:0] state_q;
    reg [1:0] state_d;

    reg [ADDR_W-1:0] araddr_q;
    reg [ADDR_W-1:0] araddr_d;
    reg [LEN_W-1:0] arlen_q;
    reg [LEN_W-1:0] arlen_d;
    reg [BEAT_COUNT_W-1:0] beats_rem_q;
    reg [BEAT_COUNT_W-1:0] beats_rem_d;
    reg [BEAT_COUNT_W-1:0] entry_beat_idx_q;
    reg [BEAT_COUNT_W-1:0] entry_beat_idx_d;
    reg error_q;
    reg error_d;

    wire [BEAT_COUNT_W-1:0] cmd_beats;
    wire accept_cmd;
    wire accept_ar;
    wire accept_r;
    wire accept_done;
    wire expected_last;
    wire entry_last;
    wire beat_error;

    assign cmd_beats = cmd_entry_count_i * ENTRY_BEATS;
    assign cmd_ready_o = (state_q == S_IDLE);
    assign accept_cmd = cmd_valid_i && cmd_ready_o;

    assign m_arvalid_o = (state_q == S_AR);
    assign m_araddr_o = araddr_q;
    assign m_arlen_o = arlen_q;
    assign accept_ar = m_arvalid_o && m_arready_i;

    assign sqe_valid_o = (state_q == S_R) && m_rvalid_i;
    assign sqe_data_o = m_rdata_i;
    assign entry_last = (entry_beat_idx_q == (ENTRY_BEATS_COUNT - ONE_BEAT));
    assign sqe_entry_last_o = (state_q == S_R) && entry_last;
    assign m_rready_o = (state_q == S_R) && sqe_ready_i;
    assign accept_r = m_rvalid_i && m_rready_o;

    assign expected_last = (beats_rem_q == ONE_BEAT);
    assign beat_error = (m_rresp_i != RESP_OKAY) || (m_rlast_i != expected_last);
    assign accept_done = done_valid_o && done_ready_i;

    assign done_valid_o = (state_q == S_DONE);
    assign error_o = (state_q == S_DONE) ? error_q : 1'b0;
    assign busy_o = (state_q == S_AR) || (state_q == S_R);
    assign beats_rem_o = beats_rem_q;

    always @(*) begin
        state_d = state_q;
        araddr_d = araddr_q;
        arlen_d = arlen_q;
        beats_rem_d = beats_rem_q;
        entry_beat_idx_d = entry_beat_idx_q;
        error_d = error_q;

        case (state_q)
            S_IDLE: begin
                error_d = 1'b0;
                if (accept_cmd) begin
                    if (cmd_beats == {BEAT_COUNT_W{1'b0}}) begin
                        error_d = 1'b1;
                        state_d = S_DONE;
                    end else begin
                        araddr_d = cmd_addr_i;
                        arlen_d = cmd_beats[LEN_W-1:0] - {{(LEN_W-1){1'b0}}, 1'b1};
                        beats_rem_d = cmd_beats;
                        entry_beat_idx_d = {BEAT_COUNT_W{1'b0}};
                        error_d = 1'b0;
                        state_d = S_AR;
                    end
                end
            end
            S_AR: begin
                if (accept_ar) begin
                    state_d = S_R;
                end
            end
            S_R: begin
                if (accept_r) begin
                    error_d = error_q || beat_error;
                    beats_rem_d = beats_rem_q - ONE_BEAT;
                    if (entry_last) begin
                        entry_beat_idx_d = {BEAT_COUNT_W{1'b0}};
                    end else begin
                        entry_beat_idx_d = entry_beat_idx_q + ONE_BEAT;
                    end

                    if (expected_last) begin
                        state_d = S_DONE;
                    end
                end
            end
            S_DONE: begin
                if (accept_done) begin
                    state_d = S_IDLE;
                end
            end
            default: begin
                state_d = S_IDLE;
            end
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= S_IDLE;
            araddr_q <= {ADDR_W{1'b0}};
            arlen_q <= {LEN_W{1'b0}};
            beats_rem_q <= {BEAT_COUNT_W{1'b0}};
            entry_beat_idx_q <= {BEAT_COUNT_W{1'b0}};
            error_q <= 1'b0;
        end else begin
            state_q <= state_d;
            araddr_q <= araddr_d;
            arlen_q <= arlen_d;
            beats_rem_q <= beats_rem_d;
            entry_beat_idx_q <= entry_beat_idx_d;
            error_q <= error_d;
        end
    end

endmodule
