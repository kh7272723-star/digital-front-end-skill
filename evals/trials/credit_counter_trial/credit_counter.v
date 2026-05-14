module credit_counter #(
    parameter COUNT_W = 3,
    parameter MAX_CREDITS = 4
) (
    input  wire                 clk_i,
    input  wire                 rst_i,
    input  wire                 consume_i,
    input  wire                 return_valid_i,
    input  wire [COUNT_W-1:0]   return_count_i,
    output wire                 credit_available_o,
    output wire [COUNT_W-1:0]   credit_count_o,
    output wire                 underflow_o,
    output wire                 overflow_o
);
    localparam [COUNT_W:0] MAX_CREDITS_EXT = MAX_CREDITS;

    reg [COUNT_W-1:0] credit_count_q;
    reg               underflow_q;
    reg               overflow_q;

    wire consume_do = consume_i && (credit_count_q != {COUNT_W{1'b0}});
    wire [COUNT_W:0] return_ext =
        return_valid_i ? {1'b0, return_count_i} : {COUNT_W+1{1'b0}};
    wire [COUNT_W:0] after_return = {1'b0, credit_count_q} + return_ext;
    wire [COUNT_W:0] next_raw = after_return - {{COUNT_W{1'b0}}, consume_do};
    wire             next_overflow = (next_raw > MAX_CREDITS_EXT);
    wire [COUNT_W-1:0] next_count =
        next_overflow ? MAX_CREDITS_EXT[COUNT_W-1:0] : next_raw[COUNT_W-1:0];

    assign credit_available_o = (credit_count_q != {COUNT_W{1'b0}});
    assign credit_count_o = credit_count_q;
    assign underflow_o = underflow_q;
    assign overflow_o = overflow_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            credit_count_q <= MAX_CREDITS_EXT[COUNT_W-1:0];
            underflow_q <= 1'b0;
            overflow_q <= 1'b0;
        end else begin
            credit_count_q <= next_count;
            if (consume_i && !consume_do) begin
                underflow_q <= 1'b1;
            end
            if (next_overflow) begin
                overflow_q <= 1'b1;
            end
        end
    end
endmodule
