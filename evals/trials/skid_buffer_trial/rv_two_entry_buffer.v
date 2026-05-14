module rv_two_entry_buffer #(
  parameter DATA_W = 8
) (
  input  wire              clk_i,
  input  wire              rst_i,
  input  wire              valid_i,
  output wire              ready_o,
  input  wire [DATA_W-1:0] data_i,
  output wire              valid_o,
  input  wire              ready_i,
  output wire [DATA_W-1:0] data_o
);

reg [1:0]        count_q;
reg [DATA_W-1:0] data0_q;
reg [DATA_W-1:0] data1_q;

wire accept_input;
wire accept_output;

assign valid_o       = (count_q != 2'd0);
assign data_o        = data0_q;
assign accept_output = valid_o && ready_i;
assign ready_o       = (count_q != 2'd2) || accept_output;
assign accept_input  = valid_i && ready_o;

always @(posedge clk_i) begin
  if (rst_i) begin
    count_q <= 2'd0;
    data0_q <= {DATA_W{1'b0}};
    data1_q <= {DATA_W{1'b0}};
  end else begin
    case ({accept_input, accept_output})
      2'b00: begin
        count_q <= count_q;
      end
      2'b01: begin
        if (count_q == 2'd2) begin
          data0_q <= data1_q;
          count_q <= 2'd1;
        end else begin
          count_q <= 2'd0;
        end
      end
      2'b10: begin
        if (count_q == 2'd0) begin
          data0_q <= data_i;
          count_q <= 2'd1;
        end else begin
          data1_q <= data_i;
          count_q <= 2'd2;
        end
      end
      2'b11: begin
        if (count_q == 2'd1) begin
          data0_q <= data_i;
          count_q <= 2'd1;
        end else begin
          data0_q <= data1_q;
          data1_q <= data_i;
          count_q <= 2'd2;
        end
      end
    endcase
  end
end

endmodule
