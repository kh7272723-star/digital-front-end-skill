module axis_two_entry_buffer #(
    parameter DATA_W = 16,
    parameter KEEP_W = 2,
    parameter USER_W = 4
) (
    input  wire                 clk_i,
    input  wire                 rst_i,

    input  wire                 tvalid_i,
    output wire                 tready_o,
    input  wire [DATA_W-1:0]    tdata_i,
    input  wire [KEEP_W-1:0]    tkeep_i,
    input  wire                 tlast_i,
    input  wire [USER_W-1:0]    tuser_i,

    output wire                 tvalid_o,
    input  wire                 tready_i,
    output wire [DATA_W-1:0]    tdata_o,
    output wire [KEEP_W-1:0]    tkeep_o,
    output wire                 tlast_o,
    output wire [USER_W-1:0]    tuser_o
);

    reg [DATA_W-1:0] data_q [0:1];
    reg [KEEP_W-1:0] keep_q [0:1];
    reg last_q [0:1];
    reg [USER_W-1:0] user_q [0:1];

    reg rd_ptr_q;
    reg wr_ptr_q;
    reg [1:0] count_q;

    wire accept_input;
    wire accept_output;

    assign tready_o = (count_q != 2'd2);
    assign tvalid_o = (count_q != 2'd0);

    assign accept_input = tvalid_i && tready_o;
    assign accept_output = tvalid_o && tready_i;

    assign tdata_o = data_q[rd_ptr_q];
    assign tkeep_o = keep_q[rd_ptr_q];
    assign tlast_o = last_q[rd_ptr_q];
    assign tuser_o = user_q[rd_ptr_q];

    always @(posedge clk_i) begin
        if (rst_i) begin
            rd_ptr_q <= 1'b0;
            wr_ptr_q <= 1'b0;
            count_q <= 2'd0;
            data_q[0] <= {DATA_W{1'b0}};
            data_q[1] <= {DATA_W{1'b0}};
            keep_q[0] <= {KEEP_W{1'b0}};
            keep_q[1] <= {KEEP_W{1'b0}};
            last_q[0] <= 1'b0;
            last_q[1] <= 1'b0;
            user_q[0] <= {USER_W{1'b0}};
            user_q[1] <= {USER_W{1'b0}};
        end else begin
            if (accept_input) begin
                data_q[wr_ptr_q] <= tdata_i;
                keep_q[wr_ptr_q] <= tkeep_i;
                last_q[wr_ptr_q] <= tlast_i;
                user_q[wr_ptr_q] <= tuser_i;
                wr_ptr_q <= wr_ptr_q + 1'b1;
            end

            if (accept_output) begin
                rd_ptr_q <= rd_ptr_q + 1'b1;
            end

            case ({accept_input, accept_output})
                2'b10: count_q <= count_q + 2'd1;
                2'b01: count_q <= count_q - 2'd1;
                default: count_q <= count_q;
            endcase
        end
    end

endmodule
