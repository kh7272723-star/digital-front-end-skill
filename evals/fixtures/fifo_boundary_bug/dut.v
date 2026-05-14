module fifo_boundary_bug #(
  parameter DATA_W = 8,
  parameter ADDR_W = 1,
  parameter DEPTH  = 2
) (
  input  wire              clk_i,
  input  wire              rst_i,
  input  wire              wr_en_i,
  input  wire [DATA_W-1:0] wdata_i,
  input  wire              rd_en_i,
  output reg  [DATA_W-1:0] rdata_o,
  output wire              full_o,
  output wire              empty_o,
  output reg  [ADDR_W:0]   count_o
);

reg [DATA_W-1:0] mem [0:DEPTH-1];
reg [ADDR_W-1:0] wr_ptr_q;
reg [ADDR_W-1:0] rd_ptr_q;

wire wr_do;
wire rd_do;

assign full_o  = (count_o == DEPTH);
assign empty_o = (count_o == 0);
assign wr_do   = wr_en_i && (!full_o || rd_en_i);
assign rd_do   = rd_en_i && !empty_o;

always @(posedge clk_i) begin
  if (rst_i) begin
    wr_ptr_q <= {ADDR_W{1'b0}};
    rd_ptr_q <= {ADDR_W{1'b0}};
    count_o  <= {(ADDR_W+1){1'b0}};
  end else begin
    if (wr_do) begin
      mem[wr_ptr_q] <= wdata_i;
      wr_ptr_q <= wr_ptr_q + 1'b1;
    end
    if (rd_do) begin
      rdata_o <= mem[rd_ptr_q];
      rd_ptr_q <= rd_ptr_q + 1'b1;
    end
    case ({wr_do, rd_do})
      2'b10: count_o <= count_o + 1'b1;
      2'b01: count_o <= count_o - 1'b1;
      default: count_o <= count_o;
    endcase
  end
end

endmodule
