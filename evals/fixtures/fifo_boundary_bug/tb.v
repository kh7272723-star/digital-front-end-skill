module tb_fifo_boundary_bug;
  reg        clk_i;
  reg        rst_i;
  reg        wr_en_i;
  reg  [7:0] wdata_i;
  reg        rd_en_i;
  wire [7:0] rdata_o;
  wire       full_o;
  wire       empty_o;
  wire [1:0] count_o;

  fifo_boundary_bug dut (
    .clk_i(clk_i),
    .rst_i(rst_i),
    .wr_en_i(wr_en_i),
    .wdata_i(wdata_i),
    .rd_en_i(rd_en_i),
    .rdata_o(rdata_o),
    .full_o(full_o),
    .empty_o(empty_o),
    .count_o(count_o)
  );

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task do_write;
    input [7:0] value;
    begin
      @(negedge clk_i);
      wr_en_i = 1'b1;
      wdata_i = value;
      rd_en_i = 1'b0;
      @(posedge clk_i);
      #1;
      wr_en_i = 1'b0;
    end
  endtask

  initial begin
    rst_i   = 1'b1;
    wr_en_i = 1'b0;
    rd_en_i = 1'b0;
    wdata_i = 8'h00;
    repeat (2) @(posedge clk_i);
    rst_i = 1'b0;

    do_write(8'h11);
    do_write(8'h22);
    if (!full_o)
      $fatal(1, "setup failed");

    @(negedge clk_i);
    wr_en_i = 1'b1;
    wdata_i = 8'h33;
    rd_en_i = 1'b1;
    @(posedge clk_i);
    #1;
    if (count_o !== 2'd1)
      $fatal(1, "EXPECTED_FIFO_BOUNDARY_FAIL conservative full write/read policy was violated");

    $finish;
  end
endmodule
