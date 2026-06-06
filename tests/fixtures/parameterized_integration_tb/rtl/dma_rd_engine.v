`default_nettype none

module dma_rd_engine (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        start_i,
    output wire        done_o
);

    reg done_q;
    assign done_o = done_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            done_q <= 1'b0;
        end else if (start_i) begin
            done_q <= 1'b1;
        end else begin
            done_q <= 1'b0;
        end
    end

endmodule
