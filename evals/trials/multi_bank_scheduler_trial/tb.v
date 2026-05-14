`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;
    reg req0_valid_i;
    reg [7:0] req0_addr_i;
    wire req0_ready_o;
    reg req1_valid_i;
    reg [7:0] req1_addr_i;
    wire req1_ready_o;
    wire [3:0] bank_valid_o;
    wire [3:0] bank_req_id_o;
    wire conflict_o;
    wire rr_owner_o;

    integer cycle_count;

    multi_bank_scheduler dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .req0_valid_i(req0_valid_i),
        .req0_addr_i(req0_addr_i),
        .req0_ready_o(req0_ready_o),
        .req1_valid_i(req1_valid_i),
        .req1_addr_i(req1_addr_i),
        .req1_ready_o(req1_ready_o),
        .bank_valid_o(bank_valid_o),
        .bank_req_id_o(bank_req_id_o),
        .conflict_o(conflict_o),
        .rr_owner_o(rr_owner_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    task fail;
        input [512*8-1:0] msg;
        begin
            $display("FAIL cycle %0d: %0s", cycle_count, msg);
            $finish;
        end
    endtask

    task step;
        begin
            @(posedge clk_i);
            #1;
            cycle_count = cycle_count + 1;
        end
    endtask

    task expect_comb;
        input expected_req0_ready;
        input expected_req1_ready;
        input [3:0] expected_bank_valid;
        input [3:0] expected_bank_req_id;
        input expected_conflict;
        begin
            #1;
            if (req0_ready_o !== expected_req0_ready) begin
                fail("unexpected req0_ready_o");
            end
            if (req1_ready_o !== expected_req1_ready) begin
                fail("unexpected req1_ready_o");
            end
            if (bank_valid_o !== expected_bank_valid) begin
                fail("unexpected bank_valid_o");
            end
            if (bank_req_id_o !== expected_bank_req_id) begin
                fail("unexpected bank_req_id_o");
            end
            if (conflict_o !== expected_conflict) begin
                fail("unexpected conflict_o");
            end
        end
    endtask

    initial begin
        cycle_count = 0;
        rst_i = 1'b1;
        req0_valid_i = 1'b0;
        req0_addr_i = 8'h00;
        req1_valid_i = 1'b0;
        req1_addr_i = 8'h00;

        repeat (2) step();
        rst_i = 1'b0;
        step();

        req0_valid_i = 1'b1;
        req0_addr_i = 8'h00;
        req1_valid_i = 1'b1;
        req1_addr_i = 8'h04;
        expect_comb(1'b1, 1'b1, 4'b0011, 4'b0010, 1'b0);
        step();

        req0_addr_i = 8'h08;
        req1_addr_i = 8'h08;
        expect_comb(1'b1, 1'b0, 4'b0100, 4'b0000, 1'b1);
        step();
        if (rr_owner_o !== 1'b1) begin
            fail("round-robin owner did not toggle after conflict");
        end

        expect_comb(1'b0, 1'b1, 4'b0100, 4'b0100, 1'b1);
        step();
        if (rr_owner_o !== 1'b0) begin
            fail("round-robin owner did not toggle back after conflict");
        end

        req0_valid_i = 1'b0;
        req1_valid_i = 1'b1;
        req1_addr_i = 8'h0c;
        expect_comb(1'b0, 1'b1, 4'b1000, 4'b1000, 1'b0);
        step();

        req0_valid_i = 1'b0;
        req1_valid_i = 1'b0;
        expect_comb(1'b0, 1'b0, 4'b0000, 4'b0000, 1'b0);

        $display("PASS multi bank scheduler");
        $finish;
    end
endmodule
