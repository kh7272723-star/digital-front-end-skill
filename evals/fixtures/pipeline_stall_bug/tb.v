module tb_pipeline_stall_bug;
  reg        clk_i;
  reg        rst_i;
  reg        valid_i;
  reg  [7:0] data_i;
  reg        stall_i;
  reg        flush_i;
  wire       valid_o;
  wire [7:0] data_o;

  pipeline_stall_bug dut (
    .clk_i(clk_i),
    .rst_i(rst_i),
    .valid_i(valid_i),
    .data_i(data_i),
    .stall_i(stall_i),
    .flush_i(flush_i),
    .valid_o(valid_o),
    .data_o(data_o)
  );

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    rst_i   = 1'b1;
    valid_i = 1'b0;
    data_i  = 8'h00;
    stall_i = 1'b0;
    flush_i = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_i = 1'b0;

    @(negedge clk_i);
    valid_i = 1'b1;
    data_i  = 8'h5A;
    @(posedge clk_i);
    #1;
    if (!valid_o || data_o !== 8'h5A)
      $fatal(1, "setup failed");

    @(negedge clk_i);
    stall_i = 1'b1;
    valid_i = 1'b0;
    data_i  = 8'hC3;
    @(posedge clk_i);
    #1;
    if (!valid_o || data_o !== 8'h5A)
      $fatal(1, "EXPECTED_PIPELINE_STALL_FAIL valid/data did not freeze together");

    $finish;
  end
endmodule
