module data_integrity_slice (
    input  wire [7:0]  data_i,
    output wire [7:0]  crc8_o,
    output wire [12:0] ecc_code_o,
    input  wire [12:0] ecc_code_i,
    output reg  [7:0]  ecc_data_o,
    output reg         ecc_single_error_o,
    output reg         ecc_double_error_o
);
    reg [3:0] syndrome;
    reg [12:0] corrected_code;
    wire overall_error = ^ecc_code_i;

    assign crc8_o = crc8_byte(data_i);
    assign ecc_code_o = ecc_encode(data_i);

    function [7:0] crc8_byte;
        input [7:0] data;
        reg [7:0] crc;
        integer i;
        begin
            crc = 8'h00;
            for (i = 7; i >= 0; i = i - 1) begin
                if (crc[7] ^ data[i]) begin
                    crc = {crc[6:0], 1'b0} ^ 8'h07;
                end else begin
                    crc = {crc[6:0], 1'b0};
                end
            end
            crc8_byte = crc;
        end
    endfunction

    function [12:0] ecc_encode;
        input [7:0] data;
        reg [12:0] code;
        begin
            code = 13'h0000;
            code[2] = data[0];
            code[4] = data[1];
            code[5] = data[2];
            code[6] = data[3];
            code[8] = data[4];
            code[9] = data[5];
            code[10] = data[6];
            code[11] = data[7];
            code[0] = code[2] ^ code[4] ^ code[6] ^ code[8] ^ code[10];
            code[1] = code[2] ^ code[5] ^ code[6] ^ code[9] ^ code[10];
            code[3] = code[4] ^ code[5] ^ code[6] ^ code[11];
            code[7] = code[8] ^ code[9] ^ code[10] ^ code[11];
            code[12] = ^code[11:0];
            ecc_encode = code;
        end
    endfunction

    always @* begin
        syndrome[0] = ecc_code_i[0] ^ ecc_code_i[2] ^ ecc_code_i[4] ^
                      ecc_code_i[6] ^ ecc_code_i[8] ^ ecc_code_i[10];
        syndrome[1] = ecc_code_i[1] ^ ecc_code_i[2] ^ ecc_code_i[5] ^
                      ecc_code_i[6] ^ ecc_code_i[9] ^ ecc_code_i[10];
        syndrome[2] = ecc_code_i[3] ^ ecc_code_i[4] ^ ecc_code_i[5] ^
                      ecc_code_i[6] ^ ecc_code_i[11];
        syndrome[3] = ecc_code_i[7] ^ ecc_code_i[8] ^ ecc_code_i[9] ^
                      ecc_code_i[10] ^ ecc_code_i[11];

        corrected_code = ecc_code_i;
        ecc_single_error_o = 1'b0;
        ecc_double_error_o = 1'b0;

        if (overall_error) begin
            ecc_single_error_o = 1'b1;
            if (syndrome != 4'd0 && syndrome <= 4'd12) begin
                corrected_code[syndrome - 4'd1] = ~corrected_code[syndrome - 4'd1];
            end
        end else if (syndrome != 4'd0) begin
            ecc_double_error_o = 1'b1;
        end

        ecc_data_o = {
            corrected_code[11],
            corrected_code[10],
            corrected_code[9],
            corrected_code[8],
            corrected_code[6],
            corrected_code[5],
            corrected_code[4],
            corrected_code[2]
        };
    end
endmodule
