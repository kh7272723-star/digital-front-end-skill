`default_nettype none

// DMA burst planner: descriptor → paired read/write burst commands.
// Simplified: single descriptor, aligned transfers, no 4KB splitting.
module burst_planner #(
    parameter ADDR_W       = 32,
    parameter LEN_W        = 8,
    parameter COUNT_W      = 16,
    parameter MAX_BURST    = 4,
    parameter BYTES_PER_BEAT = 4
)(
    input  wire               clk_i,
    input  wire               rst_i,
    // Descriptor
    input  wire               desc_valid_i,
    output reg                desc_ready_o,
    input  wire [ADDR_W-1:0]  desc_src_addr_i,
    input  wire [ADDR_W-1:0]  desc_dst_addr_i,
    input  wire [COUNT_W-1:0] desc_byte_count_i,
    // Read command
    output reg                rd_cmd_valid_o,
    input  wire               rd_cmd_ready_i,
    output reg  [ADDR_W-1:0]  rd_cmd_addr_o,
    output reg  [LEN_W-1:0]   rd_cmd_len_o,
    // Write command
    output reg                wr_cmd_valid_o,
    input  wire               wr_cmd_ready_i,
    output reg  [ADDR_W-1:0]  wr_cmd_addr_o,
    output reg  [LEN_W-1:0]   wr_cmd_len_o,
    // Completion
    output reg                done_valid_o,
    input  wire               done_ready_i,
    output reg                error_o,
    output reg  [COUNT_W-1:0] b_count_o,
    output reg                busy_o
);

    // State
    localparam S_IDLE    = 2'd0;
    localparam S_ACTIVE  = 2'd1;
    localparam S_DONE    = 2'd2;

    reg [1:0]        state_q, state_d;
    reg [ADDR_W-1:0] src_addr_q, src_addr_d;
    reg [ADDR_W-1:0] dst_addr_q, dst_addr_d;
    reg [COUNT_W-1:0] beats_rem_q, beats_rem_d;
    reg [COUNT_W-1:0] b_count_q, b_count_d;
    reg               error_q, error_d;

    // State register
    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q     <= S_IDLE;
            src_addr_q  <= {ADDR_W{1'b0}};
            dst_addr_q  <= {ADDR_W{1'b0}};
            beats_rem_q <= {COUNT_W{1'b0}};
            b_count_q   <= {COUNT_W{1'b0}};
            error_q     <= 1'b0;
        end else begin
            state_q     <= state_d;
            src_addr_q  <= src_addr_d;
            dst_addr_q  <= dst_addr_d;
            beats_rem_q <= beats_rem_d;
            b_count_q   <= b_count_d;
            error_q     <= error_d;
        end
    end

    // Choose burst beats
    function [COUNT_W-1:0] choose_burst;
        input [COUNT_W-1:0] rem;
        begin
            if (rem > MAX_BURST)
                choose_burst = MAX_BURST;
            else
                choose_burst = rem;
        end
    endfunction

    // FSM + datapath
    always @(*) begin
        state_d      = state_q;
        src_addr_d   = src_addr_q;
        dst_addr_d   = dst_addr_q;
        beats_rem_d  = beats_rem_q;
        b_count_d    = b_count_q;
        error_d      = error_q;
        desc_ready_o = 1'b0;
        rd_cmd_valid_o = 1'b0;
        rd_cmd_addr_o  = src_addr_q;
        rd_cmd_len_o   = choose_burst(beats_rem_q) - 1;
        wr_cmd_valid_o = 1'b0;
        wr_cmd_addr_o  = dst_addr_q;
        wr_cmd_len_o   = choose_burst(beats_rem_q) - 1;
        done_valid_o   = 1'b0;
        error_o        = error_q;
        b_count_o      = b_count_q;
        busy_o         = (state_q != S_IDLE);

        case (state_q)
            S_IDLE: begin
                desc_ready_o = 1'b1;
                if (desc_valid_i) begin
                    // Validate alignment
                    if (desc_byte_count_i == 0 ||
                        desc_src_addr_i[1:0] != 2'b00 ||
                        desc_dst_addr_i[1:0] != 2'b00 ||
                        desc_byte_count_i[1:0] != 2'b00) begin
                        state_d     = S_DONE;
                        error_d     = 1'b1;
                        b_count_d   = {COUNT_W{1'b0}};
                    end else begin
                        state_d     = S_ACTIVE;
                        src_addr_d  = desc_src_addr_i;
                        dst_addr_d  = desc_dst_addr_i;
                        beats_rem_d = desc_byte_count_i >> 2; // bytes to beats
                        b_count_d   = {COUNT_W{1'b0}};
                        error_d     = 1'b0;
                    end
                end
            end

            S_ACTIVE: begin
                rd_cmd_valid_o = 1'b1;
                wr_cmd_valid_o = 1'b1;
                rd_cmd_len_o   = choose_burst(beats_rem_q) - 1;
                wr_cmd_len_o   = choose_burst(beats_rem_q) - 1;

                if (rd_cmd_ready_i && wr_cmd_ready_i) begin
                    // Both commands accepted
                    b_count_d = b_count_q + 1;
                    src_addr_d = src_addr_q + choose_burst(beats_rem_q) * BYTES_PER_BEAT;
                    dst_addr_d = dst_addr_q + choose_burst(beats_rem_q) * BYTES_PER_BEAT;
                    beats_rem_d = beats_rem_q - choose_burst(beats_rem_q);
                    if (beats_rem_q == choose_burst(beats_rem_q)) begin
                        // Last burst
                        state_d = S_DONE;
                    end
                end
            end

            S_DONE: begin
                done_valid_o = 1'b1;
                error_o      = error_q;
                b_count_o    = b_count_q;
                if (done_ready_i) begin
                    state_d = S_IDLE;
                end
            end

            default: state_d = S_IDLE;
        endcase
    end

endmodule
`default_nettype wire
