module tb_ready_valid_stall_bug;
  reg        clk_i;
  reg        rst_i;
  reg        valid_i;
  wire       ready_o;
  reg  [7:0] data_i;
  wire       valid_o;
  reg        ready_i;
  wire [7:0] data_o;

  rv_register_slice_bug dut (
    .clk_i(clk_i),
    .rst_i(rst_i),
    .valid_i(valid_i),
    .ready_o(ready_o),
    .data_i(data_i),
    .valid_o(valid_o),
    .ready_i(ready_i),
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
    ready_i = 1'b1;
    repeat (2) @(posedge clk_i);
    rst_i = 1'b0;

    @(negedge clk_i);
    valid_i = 1'b1;
    data_i  = 8'hA5;
    ready_i = 1'b1;
    @(posedge clk_i);
    #1;
    if (!valid_o || data_o !== 8'hA5)
      $fatal(1, "setup failed");

    @(negedge clk_i);
    ready_i = 1'b0;
    data_i  = 8'h3C;
    @(posedge clk_i);
    #1;
    if (data_o !== 8'hA5)
      $fatal(1, "EXPECTED_STALL_HOLD_FAIL data_o changed while downstream stalled");

    $finish;
  end
endmodule
