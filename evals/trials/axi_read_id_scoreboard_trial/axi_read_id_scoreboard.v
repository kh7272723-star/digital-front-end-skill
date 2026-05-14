module axi_read_id_scoreboard #(
    parameter ID_W = 2,
    parameter LEN_W = 8,
    parameter COUNT_W = 9
) (
    input  wire                 clk_i,
    input  wire                 rst_i,

    input  wire                 cmd_valid_i,
    output wire                 cmd_ready_o,
    input  wire [ID_W-1:0]      cmd_id_i,
    input  wire [LEN_W-1:0]     cmd_arlen_i,

    input  wire                 m_rvalid_i,
    output wire                 m_rready_o,
    input  wire [ID_W-1:0]      m_rid_i,
    input  wire                 m_rlast_i,
    input  wire [1:0]           m_rresp_i,

    output reg                  done_valid_o,
    input  wire                 done_ready_i,
    output reg  [ID_W-1:0]      done_id_o,
    output reg                  done_error_o,
    output wire [3:0]           active_o
);

    localparam RESP_OKAY = 2'b00;

    reg [3:0] active_q;
    reg [COUNT_W-1:0] beats_rem_q [0:3];
    reg error_q [0:3];

    wire cmd_id_active;
    wire r_id_active;
    wire accept_cmd;
    wire accept_r;
    wire accept_done;
    wire expected_last;
    wire beat_error;
    wire error_after_edge;

    assign cmd_id_active = active_q[cmd_id_i];
    assign r_id_active = active_q[m_rid_i];
    assign cmd_ready_o = (!done_valid_o) && (!cmd_id_active);
    assign accept_cmd = cmd_valid_i && cmd_ready_o;

    assign m_rready_o = (!done_valid_o) && r_id_active;
    assign accept_r = m_rvalid_i && m_rready_o;
    assign accept_done = done_valid_o && done_ready_i;
    assign expected_last = (beats_rem_q[m_rid_i] == {{(COUNT_W-1){1'b0}}, 1'b1});
    assign beat_error = (m_rresp_i != RESP_OKAY) || (m_rlast_i != expected_last);
    assign error_after_edge = error_q[m_rid_i] || (accept_r && beat_error);
    assign active_o = active_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            active_q <= 4'b0000;
            beats_rem_q[0] <= {COUNT_W{1'b0}};
            beats_rem_q[1] <= {COUNT_W{1'b0}};
            beats_rem_q[2] <= {COUNT_W{1'b0}};
            beats_rem_q[3] <= {COUNT_W{1'b0}};
            error_q[0] <= 1'b0;
            error_q[1] <= 1'b0;
            error_q[2] <= 1'b0;
            error_q[3] <= 1'b0;
            done_valid_o <= 1'b0;
            done_id_o <= {ID_W{1'b0}};
            done_error_o <= 1'b0;
        end else begin
            if (accept_done) begin
                done_valid_o <= 1'b0;
            end

            if (accept_cmd) begin
                active_q[cmd_id_i] <= 1'b1;
                beats_rem_q[cmd_id_i] <= {{(COUNT_W-LEN_W){1'b0}}, cmd_arlen_i} +
                                          {{(COUNT_W-1){1'b0}}, 1'b1};
                error_q[cmd_id_i] <= 1'b0;
            end

            if (accept_r) begin
                error_q[m_rid_i] <= error_after_edge;
                beats_rem_q[m_rid_i] <= beats_rem_q[m_rid_i] -
                                        {{(COUNT_W-1){1'b0}}, 1'b1};
                if (expected_last) begin
                    active_q[m_rid_i] <= 1'b0;
                    done_valid_o <= 1'b1;
                    done_id_o <= m_rid_i;
                    done_error_o <= error_after_edge;
                end
            end
        end
    end

endmodule
