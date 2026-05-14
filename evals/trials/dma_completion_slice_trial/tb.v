`timescale 1ns/1ps

module tb;
    reg clk_i;
    reg rst_i;

    reg desc_valid_i;
    wire desc_ready_o;
    reg [7:0] desc_resp_count_i;

    reg write_data_accept_i;
    reg write_data_last_i;

    reg bvalid_i;
    wire bready_o;
    reg [1:0] bresp_i;

    wire done_valid_o;
    reg done_ready_i;
    wire error_o;
    wire busy_o;
    wire [7:0] outstanding_resp_o;

    integer cycle_count;

    dma_completion_slice dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .desc_valid_i(desc_valid_i),
        .desc_ready_o(desc_ready_o),
        .desc_resp_count_i(desc_resp_count_i),
        .write_data_accept_i(write_data_accept_i),
        .write_data_last_i(write_data_last_i),
        .bvalid_i(bvalid_i),
        .bready_o(bready_o),
        .bresp_i(bresp_i),
        .done_valid_o(done_valid_o),
        .done_ready_i(done_ready_i),
        .error_o(error_o),
        .busy_o(busy_o),
        .outstanding_resp_o(outstanding_resp_o)
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

    task idle_inputs;
        begin
            desc_valid_i = 1'b0;
            desc_resp_count_i = 8'd0;
            write_data_accept_i = 1'b0;
            write_data_last_i = 1'b0;
            bvalid_i = 1'b0;
            bresp_i = 2'b00;
            done_ready_i = 1'b0;
        end
    endtask

    task start_desc;
        input [7:0] response_count;
        begin
            desc_resp_count_i = response_count;
            desc_valid_i = 1'b1;
            if (desc_ready_o !== 1'b1) begin
                fail("descriptor should be ready before start");
            end
            step();
            desc_valid_i = 1'b0;
            desc_resp_count_i = 8'd0;
            if (busy_o !== 1'b1) begin
                fail("descriptor should become active");
            end
            if (outstanding_resp_o !== response_count) begin
                fail("unexpected outstanding response count after descriptor");
            end
        end
    endtask

    task send_last_data;
        begin
            write_data_accept_i = 1'b1;
            write_data_last_i = 1'b1;
            step();
            write_data_accept_i = 1'b0;
            write_data_last_i = 1'b0;
        end
    endtask

    task send_b;
        input [1:0] response;
        begin
            bresp_i = response;
            bvalid_i = 1'b1;
            if (bready_o !== 1'b1) begin
                fail("B response should be ready while outstanding");
            end
            step();
            bvalid_i = 1'b0;
            bresp_i = 2'b00;
        end
    endtask

    task expect_no_done;
        begin
            if (done_valid_o !== 1'b0) begin
                fail("completion appeared too early");
            end
        end
    endtask

    task expect_done;
        input expected_error;
        begin
            if (done_valid_o !== 1'b1) begin
                fail("expected completion");
            end
            if (error_o !== expected_error) begin
                fail("unexpected completion error flag");
            end
            if (busy_o !== 1'b0) begin
                fail("busy should clear when completion becomes visible");
            end
        end
    endtask

    task accept_done;
        begin
            done_ready_i = 1'b1;
            step();
            done_ready_i = 1'b0;
            if (done_valid_o !== 1'b0) begin
                fail("completion should clear after acceptance");
            end
            if (desc_ready_o !== 1'b1) begin
                fail("descriptor should be ready after completion acceptance");
            end
        end
    endtask

    initial begin
        cycle_count = 0;
        rst_i = 1'b1;
        idle_inputs();

        repeat (2) step();
        rst_i = 1'b0;
        step();
        if (desc_ready_o !== 1'b1 || busy_o !== 1'b0 || done_valid_o !== 1'b0) begin
            fail("bad reset release state");
        end

        start_desc(8'd2);
        send_last_data();
        expect_no_done();
        if (outstanding_resp_o !== 8'd2) begin
            fail("last W beat must not change response count");
        end

        send_b(2'b00);
        expect_no_done();
        if (outstanding_resp_o !== 8'd1) begin
            fail("first response should leave one outstanding");
        end

        send_b(2'b00);
        expect_done(1'b0);

        step();
        expect_done(1'b0);
        step();
        expect_done(1'b0);
        accept_done();

        start_desc(8'd2);
        send_last_data();
        send_b(2'b10);
        expect_no_done();
        if (outstanding_resp_o !== 8'd1) begin
            fail("error response should still drain remaining responses");
        end
        send_b(2'b00);
        expect_done(1'b1);
        accept_done();

        start_desc(8'd1);
        write_data_accept_i = 1'b1;
        write_data_last_i = 1'b1;
        bvalid_i = 1'b1;
        bresp_i = 2'b00;
        if (bready_o !== 1'b1) begin
            fail("B response should be ready before same-cycle final");
        end
        step();
        write_data_accept_i = 1'b0;
        write_data_last_i = 1'b0;
        bvalid_i = 1'b0;
        bresp_i = 2'b00;
        expect_done(1'b0);
        accept_done();

        $display("PASS dma completion slice");
        $finish;
    end
endmodule
