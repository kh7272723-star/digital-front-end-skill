module pipeline_stall_bug #(
  parameter DATA_W = 8
) (
  input  wire              clk_i,
  input  wire              rst_i,
  input  wire              valid_i,
  input  wire [DATA_W-1:0] data_i,
  input  wire              stall_i,
  input  wire              flush_i,
  output reg               valid_o,
  output reg  [DATA_W-1:0] data_o
);

always @(posedge clk_i) begin
  if (rst_i) begin
    valid_o <= 1'b0;
    data_o  <= {DATA_W{1'b0}};
  end else if (flush_i) begin
    valid_o <= 1'b0;
  end else begin
    valid_o <= valid_i;
    if (!stall_i)
      data_o <= data_i;
  end
end

endmodule
