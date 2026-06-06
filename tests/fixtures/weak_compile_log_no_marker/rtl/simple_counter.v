`default_nettype none

module simple_counter (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        inc_i,
    input  wire        clr_i,
    output reg  [7:0]  count_o
);

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            count_o <= 8'd0;
        end else if (clr_i) begin
            count_o <= 8'd0;
        end else if (inc_i) begin
            count_o <= count_o + 8'd1;
        end
    end

endmodule
