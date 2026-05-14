`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;

    reg tvalid_i;
    wire tready_o;
    reg [15:0] tdata_i;
    reg [1:0] tkeep_i;
    reg tlast_i;
    reg [3:0] tuser_i;

    wire tvalid_o;
    reg tready_i;
    wire [15:0] tdata_o;
    wire [1:0] tkeep_o;
    wire tlast_o;
    wire [3:0] tuser_o;

    reg [15:0] exp_data [0:31];
    reg [1:0] exp_keep [0:31];
    reg exp_last [0:31];
    reg [3:0] exp_user [0:31];

    reg [15:0] seq_data [0:15];
    reg [1:0] seq_keep [0:15];
    reg seq_last [0:15];
    reg [3:0] seq_user [0:15];

    integer exp_head;
    integer exp_tail;
    integer exp_count;
    integer src_idx;
    integer cycle_count;
    integer iter;

    reg accept_input;
    reg accept_output;
    reg hold_check;
    reg [15:0] hold_data;
    reg [1:0] hold_keep;
    reg hold_last;
    reg [3:0] hold_user;

    axis_two_entry_buffer dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .tvalid_i(tvalid_i),
        .tready_o(tready_o),
        .tdata_i(tdata_i),
        .tkeep_i(tkeep_i),
        .tlast_i(tlast_i),
        .tuser_i(tuser_i),
        .tvalid_o(tvalid_o),
        .tready_i(tready_i),
        .tdata_o(tdata_o),
        .tkeep_o(tkeep_o),
        .tlast_o(tlast_o),
        .tuser_o(tuser_o)
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

    task load_sequence;
        begin
            seq_data[0] = 16'h1001; seq_keep[0] = 2'b11; seq_last[0] = 1'b0; seq_user[0] = 4'h1;
            seq_data[1] = 16'h1002; seq_keep[1] = 2'b11; seq_last[1] = 1'b0; seq_user[1] = 4'h2;
            seq_data[2] = 16'h1003; seq_keep[2] = 2'b01; seq_last[2] = 1'b1; seq_user[2] = 4'h3;
            seq_data[3] = 16'h2001; seq_keep[3] = 2'b11; seq_last[3] = 1'b0; seq_user[3] = 4'h4;
            seq_data[4] = 16'h2002; seq_keep[4] = 2'b10; seq_last[4] = 1'b1; seq_user[4] = 4'h5;
            seq_data[5] = 16'h3001; seq_keep[5] = 2'b11; seq_last[5] = 1'b1; seq_user[5] = 4'h6;
            seq_data[6] = 16'h4001; seq_keep[6] = 2'b11; seq_last[6] = 1'b0; seq_user[6] = 4'h7;
            seq_data[7] = 16'h4002; seq_keep[7] = 2'b11; seq_last[7] = 1'b0; seq_user[7] = 4'h8;
            seq_data[8] = 16'h4003; seq_keep[8] = 2'b01; seq_last[8] = 1'b1; seq_user[8] = 4'h9;
            seq_data[9] = 16'h5001; seq_keep[9] = 2'b11; seq_last[9] = 1'b0; seq_user[9] = 4'ha;
            seq_data[10] = 16'h5002; seq_keep[10] = 2'b11; seq_last[10] = 1'b0; seq_user[10] = 4'hb;
            seq_data[11] = 16'h5003; seq_keep[11] = 2'b10; seq_last[11] = 1'b1; seq_user[11] = 4'hc;
        end
    endtask

    task drive_source;
        begin
            if (!tvalid_i && src_idx < 12) begin
                tvalid_i = 1'b1;
                tdata_i = seq_data[src_idx];
                tkeep_i = seq_keep[src_idx];
                tlast_i = seq_last[src_idx];
                tuser_i = seq_user[src_idx];
            end
        end
    endtask

    task check_output_before_edge;
        begin
            if (tvalid_o) begin
                if (exp_count <= 0) begin
                    fail("unexpected output item");
                end
                if (tdata_o !== exp_data[exp_head]) begin
                    fail("output data mismatch");
                end
                if (tkeep_o !== exp_keep[exp_head]) begin
                    fail("output keep mismatch");
                end
                if (tlast_o !== exp_last[exp_head]) begin
                    fail("output last mismatch");
                end
                if (tuser_o !== exp_user[exp_head]) begin
                    fail("output user mismatch");
                end
            end
        end
    endtask

    task checked_step;
        begin
            #1;
            check_output_before_edge();

            accept_input = tvalid_i && tready_o;
            accept_output = tvalid_o && tready_i;
            hold_check = tvalid_o && !tready_i;
            hold_data = tdata_o;
            hold_keep = tkeep_o;
            hold_last = tlast_o;
            hold_user = tuser_o;

            @(posedge clk_i);
            #1;
            cycle_count = cycle_count + 1;

            if (rst_i) begin
                exp_head = 0;
                exp_tail = 0;
                exp_count = 0;
            end else begin
                if (accept_output) begin
                    exp_head = exp_head + 1;
                    exp_count = exp_count - 1;
                end
                if (accept_input) begin
                    exp_data[exp_tail] = tdata_i;
                    exp_keep[exp_tail] = tkeep_i;
                    exp_last[exp_tail] = tlast_i;
                    exp_user[exp_tail] = tuser_i;
                    exp_tail = exp_tail + 1;
                    exp_count = exp_count + 1;
                    src_idx = src_idx + 1;
                    tvalid_i = 1'b0;
                end
            end

            if (hold_check) begin
                if (tvalid_o !== 1'b1 || tdata_o !== hold_data || tkeep_o !== hold_keep ||
                    tlast_o !== hold_last || tuser_o !== hold_user) begin
                    fail("output payload or sideband changed during stall");
                end
            end
        end
    endtask

    initial begin
        cycle_count = 0;
        exp_head = 0;
        exp_tail = 0;
        exp_count = 0;
        src_idx = 0;
        rst_i = 1'b1;
        tvalid_i = 1'b0;
        tdata_i = 16'h0000;
        tkeep_i = 2'b00;
        tlast_i = 1'b0;
        tuser_i = 4'h0;
        tready_i = 1'b0;
        load_sequence();

        repeat (2) checked_step();
        rst_i = 1'b0;
        checked_step();
        if (tvalid_o !== 1'b0 || tready_o !== 1'b1) begin
            fail("bad reset release state");
        end

        for (iter = 0; iter < 80 && (src_idx < 12 || exp_count > 0 || tvalid_i); iter = iter + 1) begin
            drive_source();
            case (iter % 7)
                0, 1, 4, 6: tready_i = 1'b1;
                default: tready_i = 1'b0;
            endcase
            checked_step();
        end

        if (src_idx != 12) begin
            fail("not all source items accepted");
        end
        if (exp_count != 0) begin
            fail("not all expected items consumed");
        end
        if (tvalid_o !== 1'b0) begin
            fail("output should be empty at end");
        end

        $display("PASS axis buffer");
        $finish;
    end
endmodule
