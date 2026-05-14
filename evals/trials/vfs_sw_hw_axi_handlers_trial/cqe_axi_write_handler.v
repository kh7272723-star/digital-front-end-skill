module cqe_axi_write_handler #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter LEN_W = 8
) (
    input  wire                      clk_i,
    input  wire                      rst_i,

    input  wire                      cmd_valid_i,
    output wire                      cmd_ready_o,
    input  wire [ADDR_W-1:0]         cmd_addr_i,
    input  wire [DATA_W-1:0]         cmd_data_i,
    input  wire                      cmd_phase_i,

    output wire                      m_awvalid_o,
    input  wire                      m_awready_i,
    output wire [ADDR_W-1:0]         m_awaddr_o,
    output wire [LEN_W-1:0]          m_awlen_o,

    output wire                      m_wvalid_o,
    input  wire                      m_wready_i,
    output wire [DATA_W-1:0]         m_wdata_o,
    output wire [(DATA_W/8)-1:0]     m_wstrb_o,
    output wire                      m_wlast_o,

    input  wire                      m_bvalid_i,
    output wire                      m_bready_o,
    input  wire [1:0]                m_bresp_i,

    output wire                      done_valid_o,
    input  wire                      done_ready_i,
    output wire                      error_o,
    output wire                      busy_o
);

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_AW = 3'd1;
    localparam [2:0] S_W = 3'd2;
    localparam [2:0] S_B = 3'd3;
    localparam [2:0] S_DONE = 3'd4;

    localparam RESP_OKAY = 2'b00;

    reg [2:0] state_q;
    reg [2:0] state_d;

    reg [ADDR_W-1:0] awaddr_q;
    reg [ADDR_W-1:0] awaddr_d;
    reg [DATA_W-1:0] wdata_q;
    reg [DATA_W-1:0] wdata_d;
    reg error_q;
    reg error_d;

    wire accept_cmd;
    wire accept_aw;
    wire accept_w;
    wire accept_b;
    wire accept_done;

    assign cmd_ready_o = (state_q == S_IDLE);
    assign accept_cmd = cmd_valid_i && cmd_ready_o;

    assign m_awvalid_o = (state_q == S_AW);
    assign m_awaddr_o = awaddr_q;
    assign m_awlen_o = {LEN_W{1'b0}};
    assign accept_aw = m_awvalid_o && m_awready_i;

    assign m_wvalid_o = (state_q == S_W);
    assign m_wdata_o = wdata_q;
    assign m_wstrb_o = {(DATA_W/8){1'b1}};
    assign m_wlast_o = (state_q == S_W);
    assign accept_w = m_wvalid_o && m_wready_i;

    assign m_bready_o = (state_q == S_B);
    assign accept_b = m_bvalid_i && m_bready_o;
    assign done_valid_o = (state_q == S_DONE);
    assign accept_done = done_valid_o && done_ready_i;

    assign error_o = (state_q == S_DONE) ? error_q : 1'b0;
    assign busy_o = (state_q == S_AW) || (state_q == S_W) || (state_q == S_B);

    always @(*) begin
        state_d = state_q;
        awaddr_d = awaddr_q;
        wdata_d = wdata_q;
        error_d = error_q;

        case (state_q)
            S_IDLE: begin
                error_d = 1'b0;
                if (accept_cmd) begin
                    awaddr_d = cmd_addr_i;
                    wdata_d = {cmd_data_i[DATA_W-1:1], cmd_phase_i};
                    state_d = S_AW;
                end
            end
            S_AW: begin
                if (accept_aw) begin
                    state_d = S_W;
                end
            end
            S_W: begin
                if (accept_w) begin
                    state_d = S_B;
                end
            end
            S_B: begin
                if (accept_b) begin
                    error_d = (m_bresp_i != RESP_OKAY);
                    state_d = S_DONE;
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
            awaddr_q <= {ADDR_W{1'b0}};
            wdata_q <= {DATA_W{1'b0}};
            error_q <= 1'b0;
        end else begin
            state_q <= state_d;
            awaddr_q <= awaddr_d;
            wdata_q <= wdata_d;
            error_q <= error_d;
        end
    end

endmodule
