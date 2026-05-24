module rv_pipeline_stage #(
    parameter DATA_W = 8
) (
    input  wire              clk_i,
    input  wire              rst_i,
    input  wire              flush_i,
    input  wire              stall_i,
    input  wire              valid_i,
    input  wire [DATA_W-1:0] data_i,
    output reg               valid_o,
    output reg  [DATA_W-1:0] data_o
);

    wire accept_input;
    wire accept_output;

    assign accept_output = valid_o && !stall_i;
    assign accept_input  = valid_i && (!valid_o || !stall_i);

    always @(posedge clk_i) begin
        if (rst_i) begin
            valid_o <= 1'b0;
            data_o  <= {DATA_W{1'b0}};
        end else if (flush_i) begin
            valid_o <= 1'b0;
            data_o  <= {DATA_W{1'b0}};
        end else if (!stall_i) begin
            valid_o <= valid_i;
            data_o  <= data_i;
        end
    end

endmodule
