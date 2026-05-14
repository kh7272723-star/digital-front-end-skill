module multi_bank_scheduler #(
    parameter ADDR_W = 8
) (
    input  wire              clk_i,
    input  wire              rst_i,
    input  wire              req0_valid_i,
    input  wire [ADDR_W-1:0] req0_addr_i,
    output wire              req0_ready_o,
    input  wire              req1_valid_i,
    input  wire [ADDR_W-1:0] req1_addr_i,
    output wire              req1_ready_o,
    output reg  [3:0]        bank_valid_o,
    output reg  [3:0]        bank_req_id_o,
    output wire              conflict_o,
    output wire              rr_owner_o
);
    reg rr_owner_q;

    wire [1:0] req0_bank = req0_addr_i[3:2];
    wire [1:0] req1_bank = req1_addr_i[3:2];
    wire same_bank = req0_valid_i && req1_valid_i && (req0_bank == req1_bank);
    wire grant0 = req0_valid_i && (!same_bank || !rr_owner_q);
    wire grant1 = req1_valid_i && (!same_bank || rr_owner_q);

    assign req0_ready_o = grant0;
    assign req1_ready_o = grant1;
    assign conflict_o = same_bank;
    assign rr_owner_o = rr_owner_q;

    always @* begin
        bank_valid_o = 4'b0000;
        bank_req_id_o = 4'b0000;

        if (grant0) begin
            bank_valid_o[req0_bank] = 1'b1;
            bank_req_id_o[req0_bank] = 1'b0;
        end

        if (grant1) begin
            bank_valid_o[req1_bank] = 1'b1;
            bank_req_id_o[req1_bank] = 1'b1;
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            rr_owner_q <= 1'b0;
        end else if (same_bank) begin
            rr_owner_q <= ~rr_owner_q;
        end
    end
endmodule
