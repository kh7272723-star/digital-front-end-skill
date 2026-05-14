module axi_write_burst_tracker #(
    parameter LEN_W = 8,
    parameter COUNT_W = 9
) (
    input  wire               clk_i,
    input  wire               rst_i,

    input  wire               cmd_valid_i,
    output wire               cmd_ready_o,
    input  wire [LEN_W-1:0]   cmd_awlen_i,

    output wire               m_awvalid_o,
    input  wire               m_awready_i,
    output wire [LEN_W-1:0]   m_awlen_o,

    input  wire               wdata_valid_i,
    output wire               wdata_ready_o,
    output wire               m_wvalid_o,
    input  wire               m_wready_i,
    output wire               m_wlast_o,

    input  wire               m_bvalid_i,
    output wire               m_bready_o,
    input  wire [1:0]         m_bresp_i,

    output reg                done_valid_o,
    input  wire               done_ready_i,
    output reg                error_o,
    output wire               busy_o,
    output wire [COUNT_W-1:0] beats_rem_o
);

    localparam RESP_OKAY = 2'b00;

    reg active_q;
    reg aw_done_q;
    reg [LEN_W-1:0] awlen_q;
    reg [COUNT_W-1:0] beats_rem_q;

    wire accept_cmd;
    wire accept_aw;
    wire accept_w;
    wire accept_b;
    wire accept_done;
    wire w_phase_active;

    assign cmd_ready_o = (!active_q) && (!done_valid_o);
    assign accept_cmd = cmd_valid_i && cmd_ready_o;

    assign m_awvalid_o = active_q && (!aw_done_q);
    assign m_awlen_o = awlen_q;
    assign accept_aw = m_awvalid_o && m_awready_i;

    assign w_phase_active = active_q && aw_done_q && (beats_rem_q != {COUNT_W{1'b0}});
    assign m_wvalid_o = w_phase_active && wdata_valid_i;
    assign wdata_ready_o = w_phase_active && m_wready_i;
    assign m_wlast_o = w_phase_active && (beats_rem_q == {{(COUNT_W-1){1'b0}}, 1'b1});
    assign accept_w = m_wvalid_o && m_wready_i;

    assign m_bready_o = active_q && aw_done_q &&
                        (beats_rem_q == {COUNT_W{1'b0}}) && (!done_valid_o);
    assign accept_b = m_bvalid_i && m_bready_o;

    assign accept_done = done_valid_o && done_ready_i;
    assign busy_o = active_q;
    assign beats_rem_o = beats_rem_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            active_q <= 1'b0;
            aw_done_q <= 1'b0;
            awlen_q <= {LEN_W{1'b0}};
            beats_rem_q <= {COUNT_W{1'b0}};
            done_valid_o <= 1'b0;
            error_o <= 1'b0;
        end else begin
            if (accept_done) begin
                done_valid_o <= 1'b0;
            end

            if (accept_cmd) begin
                active_q <= 1'b1;
                aw_done_q <= 1'b0;
                awlen_q <= cmd_awlen_i;
                beats_rem_q <= {{(COUNT_W-LEN_W){1'b0}}, cmd_awlen_i} +
                               {{(COUNT_W-1){1'b0}}, 1'b1};
                error_o <= 1'b0;
            end else begin
                if (accept_aw) begin
                    aw_done_q <= 1'b1;
                end

                if (accept_w) begin
                    beats_rem_q <= beats_rem_q - {{(COUNT_W-1){1'b0}}, 1'b1};
                end

                if (accept_b) begin
                    active_q <= 1'b0;
                    aw_done_q <= 1'b0;
                    done_valid_o <= 1'b1;
                    error_o <= (m_bresp_i != RESP_OKAY);
                end
            end
        end
    end

endmodule
