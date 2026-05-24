`timescale 1ns/1ps

module tb;

    reg  clk_i;
    reg  rst_i;
    reg  start_i;
    reg  finish_i;
    wire busy_o;
    wire done_o;

    integer cycle_count;

    simple_fsm dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(start_i),
        .finish_i(finish_i),
        .busy_o(busy_o),
        .done_o(done_o)
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

    initial begin
        cycle_count = 0;
        rst_i = 1'b1;
        start_i = 1'b0;
        finish_i = 1'b0;

        repeat (2) step();

        // Reset state: IDLE, not busy, not done
        if (busy_o) fail("busy_o should be low after reset");
        if (done_o) fail("done_o should be low after reset");

        rst_i = 1'b0;
        step();

        // Start: IDLE -> RUN
        start_i = 1'b1;
        step();
        start_i = 1'b0;
        if (!busy_o) fail("busy_o should be high in RUN state");
        if (done_o) fail("done_o should be low in RUN state");

        // Finish: RUN -> DONE
        finish_i = 1'b1;
        step();
        finish_i = 1'b0;
        if (!done_o) fail("done_o should be high in DONE state");
        if (busy_o) fail("busy_o should be low in DONE state");

        // DONE -> IDLE (automatic)
        step();
        if (done_o) fail("done_o should be low after DONE->IDLE");
        if (busy_o) fail("busy_o should be low after DONE->IDLE");

        // Start while in IDLE
        start_i = 1'b1;
        step();
        start_i = 1'b0;
        if (!busy_o) fail("busy_o should be high after second start");

        // Start while busy (should be ignored since state_d = RUN already)
        start_i = 1'b1;
        step();
        start_i = 1'b0;
        if (!busy_o) fail("busy_o should still be high");

        // Finish to complete
        finish_i = 1'b1;
        step();
        finish_i = 1'b0;
        if (!done_o) fail("done_o should be high in DONE");

        // Wait for DONE -> IDLE
        step();
        if (busy_o || done_o) fail("should be back to IDLE");

        // Force illegal state: directly poke state_q to 2'd3
        // After one cycle, default branch should recover to IDLE
        dut.state_q = 2'd3;
        step();
        if (busy_o) fail("busy_o should be low after illegal state recovery");
        if (done_o) fail("done_o should be low after illegal state recovery");

        $display("PASS two process fsm");
        $finish;
    end

endmodule
