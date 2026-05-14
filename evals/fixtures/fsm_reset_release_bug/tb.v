module tb_fsm_reset_release_bug;
  reg  clk_i;
  reg  rst_i;
  reg  start_i;
  reg  done_i;
  wire busy_o;
  wire done_o;

  fsm_reset_release_bug dut (
    .clk_i(clk_i),
    .rst_i(rst_i),
    .start_i(start_i),
    .done_i(done_i),
    .busy_o(busy_o),
    .done_o(done_o)
  );

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    rst_i   = 1'b1;
    start_i = 1'b0;
    done_i  = 1'b0;
    repeat (2) @(posedge clk_i);
    #1;
    if (busy_o !== 1'b0 || done_o !== 1'b0)
      $fatal(1, "EXPECTED_FSM_RESET_RELEASE_FAIL reset state is not idle");
    rst_i = 1'b0;
    @(posedge clk_i);
    $finish;
  end
endmodule
