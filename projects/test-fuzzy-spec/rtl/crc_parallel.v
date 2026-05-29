`default_nettype none

// Parallel CRC computation core
// Source: skill reference references/patterns/crc-examples.md
// IEEE 802.3 CRC-32 polynomial: x32 + x26 + x23 + x22 + x16 + x12 + x11 + x10 + x8 + x7 + x5 + x4 + x2 + x + 1

module crc_parallel #(
  parameter DATA_W      = 32,
  parameter CRC_W       = 32,
  parameter [CRC_W-1:0] POLYNOMIAL = 32'h04C11DB7,
  parameter [CRC_W-1:0] INIT_VALUE = {CRC_W{1'b1}},
  parameter [CRC_W-1:0] XOR_OUT    = {CRC_W{1'b1}},
  parameter REFLECT_IN  = 1,
  parameter REFLECT_OUT = 1
) (
  input  wire                clk,
  input  wire                rst,

  input  wire                valid_i,
  input  wire [DATA_W-1:0]   data_i,
  input  wire                flush_i,

  output wire [CRC_W-1:0]    crc_o,
  output wire                crc_valid_o
);

  function [DATA_W-1:0] reflect_data;
    input [DATA_W-1:0] d;
    integer j;
    begin
      reflect_data = {DATA_W{1'b0}};
      for (j = 0; j < DATA_W; j = j + 1)
        reflect_data[j] = d[DATA_W-1-j];
    end
  endfunction

  function [CRC_W-1:0] reflect_crc;
    input [CRC_W-1:0] c;
    integer j;
    begin
      reflect_crc = {CRC_W{1'b0}};
      for (j = 0; j < CRC_W; j = j + 1)
        reflect_crc[j] = c[CRC_W-1-j];
    end
  endfunction

  wire [DATA_W-1:0] data_processed;
  assign data_processed = REFLECT_IN ? reflect_data(data_i) : data_i;

  reg [CRC_W-1:0] crc_r;

  always @(posedge clk) begin
    if (rst) begin
      crc_r <= INIT_VALUE;
    end else if (flush_i) begin
      crc_r <= INIT_VALUE;
    end else if (valid_i) begin
      integer bit_idx;
      reg [CRC_W-1:0] crc_next;
      crc_next = crc_r;
      for (bit_idx = 0; bit_idx < DATA_W; bit_idx = bit_idx + 1) begin
        if (crc_next[CRC_W-1] ^ data_processed[DATA_W-1-bit_idx])
          crc_next = (crc_next << 1) ^ POLYNOMIAL;
        else
          crc_next = crc_next << 1;
      end
      crc_r <= crc_next;
    end
  end

  wire [CRC_W-1:0] crc_raw;
  assign crc_raw = REFLECT_OUT ? reflect_crc(crc_r) : crc_r;

  assign crc_o       = crc_raw ^ XOR_OUT;
  assign crc_valid_o = 1'b1;

endmodule

`default_nettype wire
