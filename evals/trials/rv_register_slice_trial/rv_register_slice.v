// One-entry ready/valid register slice
// Reference: references/handshake-examples.md pattern 1
// One-cycle latency, payload holds under backpressure
// ready_o = !valid_o || accept_output

module rv_register_slice #(
    parameter DATA_W = 8
) (
    input  wire              clk_i,
    input  wire              rst_i,
    input  wire              valid_i,
    output wire              ready_o,
    input  wire [DATA_W-1:0] data_i,
    output reg               valid_o,
    input  wire              ready_i,
    output reg  [DATA_W-1:0] data_o
);

    wire accept_input;
    wire accept_output;

    assign accept_output = valid_o && ready_i;
    assign ready_o       = !valid_o || accept_output;
    assign accept_input  = valid_i && ready_o;

    always @(posedge clk_i) begin
        if (rst_i) begin
            valid_o <= 1'b0;
            data_o  <= {DATA_W{1'b0}};
        end else if (ready_o) begin
            valid_o <= valid_i;
            if (accept_input)
                data_o <= data_i;
        end
    end

endmodule
