`default_nettype none

// CRC pipeline wrapper with ready/valid handshake
// Source: skill reference references/patterns/crc-examples.md
// Captures CRC on last_i assertion, holds until consumed

module crc_pipeline #(
  parameter DATA_W = 32,
  parameter CRC_W  = 32
) (
  input  wire                clk,
  input  wire                rst,

  input  wire                valid_i,
  input  wire [DATA_W-1:0]   data_i,
  input  wire                last_i,
  output wire                ready_o,

  output wire                valid_o,
  output wire [CRC_W-1:0]    crc_o,
  input  wire                ready_i
);

  wire crc_ready;
  assign crc_ready = !valid_o || ready_i;

  wire accept_input = valid_i && crc_ready;

  wire crc_valid;
  wire [CRC_W-1:0] crc_val;

  crc_parallel #(
    .DATA_W(DATA_W),
    .CRC_W(CRC_W)
  ) u_crc (
    .clk         (clk),
    .rst         (rst),
    .valid_i     (accept_input),
    .data_i      (data_i),
    .flush_i     (last_i && accept_input),
    .crc_o       (crc_val),
    .crc_valid_o (crc_valid)
  );

  reg                valid_r;
  reg  [CRC_W-1:0]   crc_r;

  always @(posedge clk) begin
    if (rst) begin
      valid_r <= 1'b0;
    end else if (last_i && accept_input) begin
      crc_r   <= crc_val;
      valid_r <= 1'b1;
    end else if (ready_i) begin
      valid_r <= 1'b0;
    end
  end

  assign valid_o = valid_r;
  assign crc_o   = crc_r;
  assign ready_o = crc_ready;

endmodule

`default_nettype wire
