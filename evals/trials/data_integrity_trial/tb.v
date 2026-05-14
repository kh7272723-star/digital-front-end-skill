`timescale 1ns/1ps

module tb;
    reg [7:0] data_i;
    wire [7:0] crc8_o;
    wire [12:0] ecc_code_o;
    reg [12:0] ecc_code_i;
    wire [7:0] ecc_data_o;
    wire ecc_single_error_o;
    wire ecc_double_error_o;

    data_integrity_slice dut (
        .data_i(data_i),
        .crc8_o(crc8_o),
        .ecc_code_o(ecc_code_o),
        .ecc_code_i(ecc_code_i),
        .ecc_data_o(ecc_data_o),
        .ecc_single_error_o(ecc_single_error_o),
        .ecc_double_error_o(ecc_double_error_o)
    );

    task fail;
        input [512*8-1:0] msg;
        begin
            $display("FAIL: %0s", msg);
            $finish;
        end
    endtask

    initial begin
        data_i = 8'hab;
        #1;
        if (crc8_o !== 8'h58) begin
            fail("CRC-8 polynomial result mismatch");
        end

        ecc_code_i = ecc_code_o;
        #1;
        if (ecc_data_o !== 8'hab || ecc_single_error_o || ecc_double_error_o) begin
            fail("clean SECDED decode mismatch");
        end

        ecc_code_i = ecc_code_o ^ 13'h0020;
        #1;
        if (ecc_data_o !== 8'hab || !ecc_single_error_o || ecc_double_error_o) begin
            fail("single-bit data error was not corrected");
        end

        ecc_code_i = ecc_code_o ^ 13'h1000;
        #1;
        if (ecc_data_o !== 8'hab || !ecc_single_error_o || ecc_double_error_o) begin
            fail("overall parity error was not classified as single-bit");
        end

        ecc_code_i = ecc_code_o ^ 13'h0024;
        #1;
        if (!ecc_double_error_o || ecc_single_error_o) begin
            fail("double-bit error was not detected");
        end

        data_i = 8'h00;
        #1;
        if (crc8_o !== 8'h00) begin
            fail("zero CRC-8 mismatch");
        end

        $display("PASS data integrity");
        $finish;
    end
endmodule
