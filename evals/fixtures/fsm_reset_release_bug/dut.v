module fsm_reset_release_bug (
  input  wire clk_i,
  input  wire rst_i,
  input  wire start_i,
  input  wire done_i,
  output reg  busy_o,
  output reg  done_o
);

localparam [1:0] IDLE = 2'd0;
localparam [1:0] BUSY = 2'd1;
localparam [1:0] DONE = 2'd2;

reg [1:0] state_q;
reg [1:0] state_d;

always @(*) begin
  state_d = state_q;
  busy_o  = 1'b0;
  done_o  = 1'b0;
  case (state_q)
    IDLE: begin
      if (start_i)
        state_d = BUSY;
    end
    BUSY: begin
      busy_o = 1'b1;
      if (done_i)
        state_d = DONE;
    end
    DONE: begin
      done_o  = 1'b1;
      state_d = IDLE;
    end
    default: begin
      state_d = IDLE;
    end
  endcase
end

always @(posedge clk_i) begin
  if (rst_i)
    state_q <= BUSY;
  else
    state_q <= state_d;
end

endmodule
