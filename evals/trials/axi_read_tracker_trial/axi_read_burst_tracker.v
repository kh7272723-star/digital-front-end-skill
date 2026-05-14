module axi_read_burst_tracker #(
    parameter LEN_W = 8,
    parameter COUNT_W = 9
) (
    input  wire               clk_i,
    input  wire               rst_i,

    input  wire               cmd_valid_i,
    output wire               cmd_ready_o,
    input  wire [LEN_W-1:0]   cmd_arlen_i,

    output wire               m_arvalid_o,
    input  wire               m_arready_i,
    output wire [LEN_W-1:0]   m_arlen_o,

    input  wire               rdata_ready_i,
    input  wire               m_rvalid_i,
    output wire               m_rready_o,
    input  wire               m_rlast_i,
    input  wire [1:0]         m_rresp_i,

    output reg                done_valid_o,
    input  wire               done_ready_i,
    output reg                error_o,
    output wire               busy_o,
    output wire [COUNT_W-1:0] beats_rem_o
);

    localparam RESP_OKAY = 2'b00;

    reg active_q;
    reg ar_done_q;
    reg [LEN_W-1:0] arlen_q;
    reg [COUNT_W-1:0] beats_rem_q;
    reg error_q;

    wire accept_cmd;
    wire accept_ar;
    wire accept_r;
    wire accept_done;
    wire r_phase_active;
    wire expected_last;
    wire beat_error;
    wire error_after_edge;

    assign cmd_ready_o = (!active_q) && (!done_valid_o);
    assign accept_cmd = cmd_valid_i && cmd_ready_o;

    assign m_arvalid_o = active_q && (!ar_done_q);
    assign m_arlen_o = arlen_q;
    assign accept_ar = m_arvalid_o && m_arready_i;

    assign r_phase_active = active_q && ar_done_q && (beats_rem_q != {COUNT_W{1'b0}});
    assign m_rready_o = r_phase_active && rdata_ready_i && (!done_valid_o);
    assign accept_r = m_rvalid_i && m_rready_o;

    assign expected_last = (beats_rem_q == {{(COUNT_W-1){1'b0}}, 1'b1});
    assign beat_error = (m_rresp_i != RESP_OKAY) || (m_rlast_i != expected_last);
    assign error_after_edge = error_q || (accept_r && beat_error);

    assign accept_done = done_valid_o && done_ready_i;
    assign busy_o = active_q;
    assign beats_rem_o = beats_rem_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            active_q <= 1'b0;
            ar_done_q <= 1'b0;
            arlen_q <= {LEN_W{1'b0}};
            beats_rem_q <= {COUNT_W{1'b0}};
            error_q <= 1'b0;
            done_valid_o <= 1'b0;
            error_o <= 1'b0;
        end else begin
            if (accept_done) begin
                done_valid_o <= 1'b0;
            end

            if (accept_cmd) begin
                active_q <= 1'b1;
                ar_done_q <= 1'b0;
                arlen_q <= cmd_arlen_i;
                beats_rem_q <= {{(COUNT_W-LEN_W){1'b0}}, cmd_arlen_i} +
                               {{(COUNT_W-1){1'b0}}, 1'b1};
                error_q <= 1'b0;
                error_o <= 1'b0;
            end else begin
                if (accept_ar) begin
                    ar_done_q <= 1'b1;
                end

                if (accept_r) begin
                    error_q <= error_after_edge;
                    beats_rem_q <= beats_rem_q - {{(COUNT_W-1){1'b0}}, 1'b1};

                    if (expected_last) begin
                        active_q <= 1'b0;
                        ar_done_q <= 1'b0;
                        done_valid_o <= 1'b1;
                        error_o <= error_after_edge;
                    end
                end
            end
        end
    end

endmodule
