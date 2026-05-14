module tb_rv_two_entry_buffer;
  reg        clk_i;
  reg        rst_i;
  reg        valid_i;
  wire       ready_o;
  reg  [7:0] data_i;
  wire       valid_o;
  reg        ready_i;
  wire [7:0] data_o;

  reg [7:0] model [0:31];
  integer head;
  integer tail;
  integer q_count;

  reg in_xfer;
  reg out_xfer;

  rv_two_entry_buffer dut (
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

  task check_outputs;
    begin
      if (valid_o !== (q_count != 0))
        $fatal(1, "valid_o mismatch q_count=%0d valid_o=%0b", q_count, valid_o);
      if (q_count != 0 && data_o !== model[head])
        $fatal(1, "data_o mismatch expected=%02x actual=%02x", model[head], data_o);
      if (ready_o !== ((q_count != 2) || ((q_count != 0) && ready_i)))
        $fatal(1, "ready_o mismatch q_count=%0d ready_i=%0b ready_o=%0b", q_count, ready_i, ready_o);
    end
  endtask

  task step_cycle;
    input        next_valid;
    input [7:0]  next_data;
    input        next_ready;
    begin
      @(negedge clk_i);
      valid_i = next_valid;
      data_i  = next_data;
      ready_i = next_ready;
      #1;
      in_xfer  = valid_i && ready_o;
      out_xfer = valid_o && ready_i;
      @(posedge clk_i);
      #1;

      if (out_xfer) begin
        if (q_count == 0)
          $fatal(1, "model underflow");
        head = (head + 1) % 32;
        q_count = q_count - 1;
      end
      if (in_xfer) begin
        if (q_count == 2)
          $fatal(1, "model overflow");
        model[tail] = next_data;
        tail = (tail + 1) % 32;
        q_count = q_count + 1;
      end

      check_outputs();
    end
  endtask

  initial begin
    rst_i   = 1'b1;
    valid_i = 1'b0;
    data_i  = 8'h00;
    ready_i = 1'b0;
    head    = 0;
    tail    = 0;
    q_count = 0;

    repeat (3) @(posedge clk_i);
    rst_i = 1'b0;
    #1;
    check_outputs();

    step_cycle(1'b1, 8'h11, 1'b0);
    step_cycle(1'b1, 8'h22, 1'b0);
    step_cycle(1'b1, 8'h33, 1'b0);
    step_cycle(1'b1, 8'h33, 1'b1);
    step_cycle(1'b0, 8'h00, 1'b1);
    step_cycle(1'b0, 8'h00, 1'b1);
    step_cycle(1'b1, 8'h44, 1'b1);
    step_cycle(1'b1, 8'h55, 1'b1);
    step_cycle(1'b0, 8'h00, 1'b1);

    if (q_count != 0)
      $fatal(1, "model did not drain");

    $display("PASS skid buffer");
    $finish;
  end
endmodule
