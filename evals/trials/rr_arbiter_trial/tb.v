`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;
    reg [3:0] valid_i;
    wire [3:0] ready_o;
    reg [31:0] data_i;
    wire valid_o;
    reg ready_i;
    wire [7:0] data_o;
    wire [1:0] grant_o;

    reg expected_valid_q;
    reg [7:0] expected_data_q;
    reg [1:0] expected_grant_q;
    reg [1:0] expected_ptr_q;

    reg [3:0] expected_ready_vec;
    reg [3:0] last_accept_vec;
    reg [1:0] selected_idx;
    reg selected_valid;
    reg model_can_load;

    reg hold_check;
    reg hold_valid_before;
    reg [7:0] hold_data_before;
    reg [1:0] hold_grant_before;

    reg [31:0] rand_state;
    reg [3:0] src_valid_q;
    reg [31:0] src_data_q;
    integer item_seq0;
    integer item_seq1;
    integer item_seq2;
    integer item_seq3;

    integer cycle_count;
    integer iter;
    integer total_accepts;
    integer accept_count0;
    integer accept_count1;
    integer accept_count2;
    integer accept_count3;

    rr_ready_valid_arbiter #(
        .DATA_W(8)
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .valid_i(valid_i),
        .ready_o(ready_o),
        .data_i(data_i),
        .valid_o(valid_o),
        .ready_i(ready_i),
        .data_o(data_o),
        .grant_o(grant_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    function [1:0] model_pick_grant;
        input [3:0] valid;
        input [1:0] start;
        begin
            case (start)
                2'd0: begin
                    if (valid[0]) begin
                        model_pick_grant = 2'd0;
                    end else if (valid[1]) begin
                        model_pick_grant = 2'd1;
                    end else if (valid[2]) begin
                        model_pick_grant = 2'd2;
                    end else begin
                        model_pick_grant = 2'd3;
                    end
                end
                2'd1: begin
                    if (valid[1]) begin
                        model_pick_grant = 2'd1;
                    end else if (valid[2]) begin
                        model_pick_grant = 2'd2;
                    end else if (valid[3]) begin
                        model_pick_grant = 2'd3;
                    end else begin
                        model_pick_grant = 2'd0;
                    end
                end
                2'd2: begin
                    if (valid[2]) begin
                        model_pick_grant = 2'd2;
                    end else if (valid[3]) begin
                        model_pick_grant = 2'd3;
                    end else if (valid[0]) begin
                        model_pick_grant = 2'd0;
                    end else begin
                        model_pick_grant = 2'd1;
                    end
                end
                default: begin
                    if (valid[3]) begin
                        model_pick_grant = 2'd3;
                    end else if (valid[0]) begin
                        model_pick_grant = 2'd0;
                    end else if (valid[1]) begin
                        model_pick_grant = 2'd1;
                    end else begin
                        model_pick_grant = 2'd2;
                    end
                end
            endcase
        end
    endfunction

    function [3:0] model_onehot;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: model_onehot = 4'b0001;
                2'd1: model_onehot = 4'b0010;
                2'd2: model_onehot = 4'b0100;
                default: model_onehot = 4'b1000;
            endcase
        end
    endfunction

    function [7:0] model_pick_data;
        input [31:0] bus;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: model_pick_data = bus[7:0];
                2'd1: model_pick_data = bus[15:8];
                2'd2: model_pick_data = bus[23:16];
                default: model_pick_data = bus[31:24];
            endcase
        end
    endfunction

    function model_onehot0;
        input [3:0] value;
        begin
            case (value)
                4'b0000,
                4'b0001,
                4'b0010,
                4'b0100,
                4'b1000: model_onehot0 = 1'b1;
                default: model_onehot0 = 1'b0;
            endcase
        end
    endfunction

    task set_data;
        input [7:0] d0;
        input [7:0] d1;
        input [7:0] d2;
        input [7:0] d3;
        begin
            data_i = {d3, d2, d1, d0};
        end
    endtask

    task fail;
        input [512*8-1:0] msg;
        begin
            $display("FAIL cycle %0d: %0s", cycle_count, msg);
            $finish;
        end
    endtask

    task init_model;
        begin
            expected_valid_q = 1'b0;
            expected_data_q = 8'h00;
            expected_grant_q = 2'd0;
            expected_ptr_q = 2'd0;
            expected_ready_vec = 4'b0000;
            last_accept_vec = 4'b0000;
        end
    endtask

    task check_model_output;
        begin
            if (expected_valid_q) begin
                if (valid_o !== 1'b1) begin
                    fail("model expected valid output");
                end
                if (data_o !== expected_data_q) begin
                    fail("model expected different output data");
                end
                if (grant_o !== expected_grant_q) begin
                    fail("model expected different output grant");
                end
            end else if (valid_o !== 1'b0) begin
                fail("model expected invalid output");
            end
        end
    endtask

    task predict_ready;
        begin
            model_can_load = (!expected_valid_q) || ready_i;
            selected_valid = |valid_i;
            selected_idx = model_pick_grant(valid_i, expected_ptr_q);
            expected_ready_vec = 4'b0000;
            if (model_can_load && selected_valid) begin
                expected_ready_vec = model_onehot(selected_idx);
            end
        end
    endtask

    task checked_step;
        begin
            #1;
            predict_ready();
            if (!model_onehot0(ready_o)) begin
                fail("ready_o is not zero-or-one-hot");
            end
            if (ready_o !== expected_ready_vec) begin
                fail("ready_o does not match scoreboard model");
            end

            hold_check = expected_valid_q && !ready_i;
            hold_valid_before = valid_o;
            hold_data_before = data_o;
            hold_grant_before = grant_o;
            last_accept_vec = expected_ready_vec;

            @(posedge clk_i);
            #1;
            cycle_count = cycle_count + 1;

            if (rst_i) begin
                expected_valid_q = 1'b0;
                expected_data_q = 8'h00;
                expected_grant_q = 2'd0;
                expected_ptr_q = 2'd0;
                last_accept_vec = 4'b0000;
            end else if (model_can_load) begin
                if (selected_valid) begin
                    expected_valid_q = 1'b1;
                    expected_data_q = model_pick_data(data_i, selected_idx);
                    expected_grant_q = selected_idx;
                    expected_ptr_q = selected_idx + 2'd1;
                end else begin
                    expected_valid_q = 1'b0;
                end
            end

            if (hold_check) begin
                if (valid_o !== hold_valid_before) begin
                    fail("valid_o changed during downstream stall");
                end
                if (data_o !== hold_data_before) begin
                    fail("data_o changed during downstream stall");
                end
                if (grant_o !== hold_grant_before) begin
                    fail("grant_o changed during downstream stall");
                end
            end

            check_model_output();
        end
    endtask

    task expect_output;
        input [1:0] expected_grant;
        input [7:0] expected_data;
        begin
            if (valid_o !== 1'b1) begin
                fail("expected valid_o high");
            end
            if (grant_o !== expected_grant) begin
                fail("unexpected directed grant_o");
            end
            if (data_o !== expected_data) begin
                fail("unexpected directed data_o");
            end
        end
    endtask

    task rand_advance;
        begin
            rand_state = {
                rand_state[30:0],
                rand_state[31] ^ rand_state[21] ^ rand_state[1] ^ rand_state[0]
            };
        end
    endtask

    task clear_accepted_sources;
        begin
            if (last_accept_vec[0]) begin
                src_valid_q[0] = 1'b0;
            end
            if (last_accept_vec[1]) begin
                src_valid_q[1] = 1'b0;
            end
            if (last_accept_vec[2]) begin
                src_valid_q[2] = 1'b0;
            end
            if (last_accept_vec[3]) begin
                src_valid_q[3] = 1'b0;
            end
        end
    endtask

    task refill_random_sources;
        begin
            clear_accepted_sources();

            rand_advance();
            if (!src_valid_q[0] && rand_state[0]) begin
                src_valid_q[0] = 1'b1;
                src_data_q[7:0] = 8'h80 + item_seq0[7:0];
                item_seq0 = item_seq0 + 1;
            end

            rand_advance();
            if (!src_valid_q[1] && rand_state[1]) begin
                src_valid_q[1] = 1'b1;
                src_data_q[15:8] = 8'h90 + item_seq1[7:0];
                item_seq1 = item_seq1 + 1;
            end

            rand_advance();
            if (!src_valid_q[2] && rand_state[2]) begin
                src_valid_q[2] = 1'b1;
                src_data_q[23:16] = 8'ha0 + item_seq2[7:0];
                item_seq2 = item_seq2 + 1;
            end

            rand_advance();
            if (!src_valid_q[3] && rand_state[3]) begin
                src_valid_q[3] = 1'b1;
                src_data_q[31:24] = 8'hb0 + item_seq3[7:0];
                item_seq3 = item_seq3 + 1;
            end

            valid_i = src_valid_q;
            data_i = src_data_q;
        end
    endtask

    task count_last_accept;
        begin
            if (last_accept_vec[0]) begin
                accept_count0 = accept_count0 + 1;
                total_accepts = total_accepts + 1;
            end
            if (last_accept_vec[1]) begin
                accept_count1 = accept_count1 + 1;
                total_accepts = total_accepts + 1;
            end
            if (last_accept_vec[2]) begin
                accept_count2 = accept_count2 + 1;
                total_accepts = total_accepts + 1;
            end
            if (last_accept_vec[3]) begin
                accept_count3 = accept_count3 + 1;
                total_accepts = total_accepts + 1;
            end
        end
    endtask

    task check_fair_counts;
        begin
            if (accept_count0 < 19 || accept_count0 > 21) begin
                fail("channel 0 fairness count out of range");
            end
            if (accept_count1 < 19 || accept_count1 > 21) begin
                fail("channel 1 fairness count out of range");
            end
            if (accept_count2 < 19 || accept_count2 > 21) begin
                fail("channel 2 fairness count out of range");
            end
            if (accept_count3 < 19 || accept_count3 > 21) begin
                fail("channel 3 fairness count out of range");
            end
        end
    endtask

    initial begin
        cycle_count = 0;
        rand_state = 32'h1ace_b00c;
        item_seq0 = 0;
        item_seq1 = 0;
        item_seq2 = 0;
        item_seq3 = 0;
        src_valid_q = 4'b0000;
        src_data_q = 32'h0000_0000;
        accept_count0 = 0;
        accept_count1 = 0;
        accept_count2 = 0;
        accept_count3 = 0;
        total_accepts = 0;
        init_model();

        rst_i = 1'b1;
        valid_i = 4'b0000;
        ready_i = 1'b1;
        set_data(8'h00, 8'h00, 8'h00, 8'h00);

        repeat (2) checked_step();
        rst_i = 1'b0;
        checked_step();

        valid_i = 4'b1111;
        ready_i = 1'b1;
        set_data(8'h10, 8'h20, 8'h30, 8'h40);

        checked_step();
        expect_output(2'd0, 8'h10);
        checked_step();
        expect_output(2'd1, 8'h20);
        checked_step();
        expect_output(2'd2, 8'h30);
        checked_step();
        expect_output(2'd3, 8'h40);
        checked_step();
        expect_output(2'd0, 8'h10);

        ready_i = 1'b0;
        set_data(8'ha0, 8'ha1, 8'ha2, 8'ha3);
        checked_step();
        expect_output(2'd0, 8'h10);
        checked_step();
        expect_output(2'd0, 8'h10);

        ready_i = 1'b1;
        checked_step();
        expect_output(2'd1, 8'ha1);

        valid_i = 4'b1010;
        set_data(8'hb0, 8'hb1, 8'hb2, 8'hb3);
        checked_step();
        expect_output(2'd3, 8'hb3);
        checked_step();
        expect_output(2'd1, 8'hb1);

        valid_i = 4'b0000;
        ready_i = 1'b1;
        checked_step();

        src_valid_q = 4'b0000;
        src_data_q = 32'h0000_0000;
        last_accept_vec = 4'b0000;
        for (iter = 0; iter < 180; iter = iter + 1) begin
            refill_random_sources();
            rand_advance();
            ready_i = rand_state[0] | rand_state[4];
            checked_step();
        end

        src_valid_q = 4'b0000;
        valid_i = 4'b0000;
        ready_i = 1'b1;
        repeat (3) checked_step();

        accept_count0 = 0;
        accept_count1 = 0;
        accept_count2 = 0;
        accept_count3 = 0;
        total_accepts = 0;

        valid_i = 4'b1111;
        set_data(8'hc0, 8'hc1, 8'hc2, 8'hc3);
        for (iter = 0; iter < 140 && total_accepts < 80; iter = iter + 1) begin
            ready_i = (iter % 5) != 2;
            checked_step();
            count_last_accept();
        end

        if (total_accepts < 80) begin
            fail("fairness phase did not reach enough accepted items");
        end
        check_fair_counts();

        valid_i = 4'b0000;
        ready_i = 1'b1;
        repeat (2) checked_step();

        $display("PASS round robin arbiter");
        $finish;
    end
endmodule
