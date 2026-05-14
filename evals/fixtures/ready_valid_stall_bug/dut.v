module rv_register_slice_bug #(
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

assign ready_o = !valid_o || ready_i;

always @(posedge clk_i) begin
  if (rst_i) begin
    valid_o <= 1'b0;
    data_o  <= {DATA_W{1'b0}};
  end else begin
    if (valid_i) begin
      valid_o <= 1'b1;
      data_o  <= data_i;
    end else if (ready_i) begin
      valid_o <= 1'b0;
    end
  end
end

endmodule
