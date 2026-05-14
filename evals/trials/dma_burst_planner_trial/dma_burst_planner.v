module dma_burst_planner #(
    parameter ADDR_W = 32,
    parameter LEN_W = 8,
    parameter COUNT_W = 16
) (
    input  wire                 clk_i,
    input  wire                 rst_i,

    input  wire                 desc_valid_i,
    output wire                 desc_ready_o,
    input  wire [ADDR_W-1:0]    desc_src_addr_i,
    input  wire [ADDR_W-1:0]    desc_dst_addr_i,
    input  wire [COUNT_W-1:0]   desc_byte_count_i,

    output reg                  rd_cmd_valid_o,
    input  wire                 rd_cmd_ready_i,
    output reg  [ADDR_W-1:0]    rd_cmd_addr_o,
    output reg  [LEN_W-1:0]     rd_cmd_len_o,

    output reg                  wr_cmd_valid_o,
    input  wire                 wr_cmd_ready_i,
    output reg  [ADDR_W-1:0]    wr_cmd_addr_o,
    output reg  [LEN_W-1:0]     wr_cmd_len_o,

    output reg                  done_valid_o,
    input  wire                 done_ready_i,
    output reg                  error_o,
    output reg  [COUNT_W-1:0]   expected_b_count_o,
    output wire                 busy_o
);

    localparam [COUNT_W-1:0] BYTES_PER_BEAT = 16'd4;
    localparam [COUNT_W-1:0] MAX_BURST_BEATS = 16'd4;

    reg active_q;
    reg [ADDR_W-1:0] src_addr_q;
    reg [ADDR_W-1:0] dst_addr_q;
    reg [COUNT_W-1:0] beats_rem_q;
    reg [COUNT_W-1:0] next_burst_beats_q;

    wire accept_desc;
    wire accept_rd_cmd;
    wire accept_wr_cmd;
    wire accept_done;
    wire desc_aligned;
    wire desc_valid_shape;
    wire both_cmds_accepted;

    assign desc_ready_o = (!active_q) && (!done_valid_o);
    assign accept_desc = desc_valid_i && desc_ready_o;
    assign accept_rd_cmd = rd_cmd_valid_o && rd_cmd_ready_i;
    assign accept_wr_cmd = wr_cmd_valid_o && wr_cmd_ready_i;
    assign accept_done = done_valid_o && done_ready_i;
    assign desc_aligned = (desc_src_addr_i[1:0] == 2'b00) &&
                          (desc_dst_addr_i[1:0] == 2'b00) &&
                          (desc_byte_count_i[1:0] == 2'b00);
    assign desc_valid_shape = desc_aligned && (desc_byte_count_i != {COUNT_W{1'b0}});
    assign both_cmds_accepted = accept_rd_cmd && accept_wr_cmd;
    assign busy_o = active_q;

    function [COUNT_W-1:0] choose_burst_beats;
        input [COUNT_W-1:0] beats_left;
        begin
            if (beats_left > MAX_BURST_BEATS) begin
                choose_burst_beats = MAX_BURST_BEATS;
            end else begin
                choose_burst_beats = beats_left;
            end
        end
    endfunction

    task load_command_outputs;
        input [ADDR_W-1:0] src_addr;
        input [ADDR_W-1:0] dst_addr;
        input [COUNT_W-1:0] burst_beats;
        begin
            rd_cmd_valid_o <= 1'b1;
            wr_cmd_valid_o <= 1'b1;
            rd_cmd_addr_o <= src_addr;
            wr_cmd_addr_o <= dst_addr;
            rd_cmd_len_o <= burst_beats[LEN_W-1:0] - {{(LEN_W-1){1'b0}}, 1'b1};
            wr_cmd_len_o <= burst_beats[LEN_W-1:0] - {{(LEN_W-1){1'b0}}, 1'b1};
        end
    endtask

    always @(posedge clk_i) begin
        if (rst_i) begin
            active_q <= 1'b0;
            src_addr_q <= {ADDR_W{1'b0}};
            dst_addr_q <= {ADDR_W{1'b0}};
            beats_rem_q <= {COUNT_W{1'b0}};
            next_burst_beats_q <= {COUNT_W{1'b0}};
            rd_cmd_valid_o <= 1'b0;
            wr_cmd_valid_o <= 1'b0;
            rd_cmd_addr_o <= {ADDR_W{1'b0}};
            wr_cmd_addr_o <= {ADDR_W{1'b0}};
            rd_cmd_len_o <= {LEN_W{1'b0}};
            wr_cmd_len_o <= {LEN_W{1'b0}};
            done_valid_o <= 1'b0;
            error_o <= 1'b0;
            expected_b_count_o <= {COUNT_W{1'b0}};
        end else begin
            if (accept_done) begin
                done_valid_o <= 1'b0;
            end

            if (accept_desc) begin
                expected_b_count_o <= {COUNT_W{1'b0}};
                error_o <= !desc_valid_shape;
                if (desc_valid_shape) begin
                    active_q <= 1'b1;
                    src_addr_q <= desc_src_addr_i;
                    dst_addr_q <= desc_dst_addr_i;
                    beats_rem_q <= desc_byte_count_i >> 2;
                    next_burst_beats_q <= choose_burst_beats(desc_byte_count_i >> 2);
                    load_command_outputs(
                        desc_src_addr_i,
                        desc_dst_addr_i,
                        choose_burst_beats(desc_byte_count_i >> 2)
                    );
                end else begin
                    done_valid_o <= 1'b1;
                end
            end else if (active_q && both_cmds_accepted) begin
                expected_b_count_o <= expected_b_count_o + {{(COUNT_W-1){1'b0}}, 1'b1};
                if (beats_rem_q == next_burst_beats_q) begin
                    active_q <= 1'b0;
                    beats_rem_q <= {COUNT_W{1'b0}};
                    rd_cmd_valid_o <= 1'b0;
                    wr_cmd_valid_o <= 1'b0;
                    done_valid_o <= 1'b1;
                    error_o <= 1'b0;
                end else begin
                    src_addr_q <= src_addr_q + (next_burst_beats_q << 2);
                    dst_addr_q <= dst_addr_q + (next_burst_beats_q << 2);
                    beats_rem_q <= beats_rem_q - next_burst_beats_q;
                    next_burst_beats_q <= choose_burst_beats(beats_rem_q - next_burst_beats_q);
                    load_command_outputs(
                        src_addr_q + (next_burst_beats_q << 2),
                        dst_addr_q + (next_burst_beats_q << 2),
                        choose_burst_beats(beats_rem_q - next_burst_beats_q)
                    );
                end
            end
        end
    end

endmodule
