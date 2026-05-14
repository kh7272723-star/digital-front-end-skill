`timescale 1ns/1ps

module tb;
    localparam ADDR_W = 32;
    localparam PTR_W = 2;
    localparam COUNT_W = 3;
    localparam BYTE_W = 16;
    localparam TIMEOUT_W = 4;

    localparam [1:0] IRQ_REASON_COUNT = 2'd1;
    localparam [1:0] IRQ_REASON_BYTES = 2'd2;
    localparam [1:0] IRQ_REASON_TIMEOUT = 2'd3;

    reg clk_i;
    reg rst_i;

    reg [ADDR_W-1:0] sq_base_addr_i;
    reg sq_tail_db_wr_en_i;
    reg [PTR_W-1:0] sq_tail_db_i;
    wire [PTR_W-1:0] sq_head_o;
    wire [COUNT_W-1:0] sq_pending_o;
    wire sq_cmd_valid_o;
    reg sq_cmd_ready_i;
    wire [ADDR_W-1:0] sq_cmd_addr_o;
    wire [COUNT_W-1:0] sq_cmd_len_o;

    reg [ADDR_W-1:0] cq_base_addr_i;
    reg cq_head_db_wr_en_i;
    reg [PTR_W-1:0] cq_head_db_i;
    wire [PTR_W-1:0] cq_tail_o;
    wire [COUNT_W-1:0] cq_pending_o;
    wire cq_full_o;

    reg cpl_valid_i;
    wire cpl_ready_o;
    reg [BYTE_W-1:0] cpl_bytes_i;

    wire cq_cmd_valid_o;
    reg cq_cmd_ready_i;
    wire [ADDR_W-1:0] cq_cmd_addr_o;
    wire [COUNT_W-1:0] cq_cmd_len_o;
    wire cq_cmd_phase_o;
    reg cq_write_done_i;

    reg [COUNT_W-1:0] irq_cqe_threshold_i;
    reg [BYTE_W-1:0] irq_byte_threshold_i;
    reg [TIMEOUT_W-1:0] irq_timeout_threshold_i;
    wire irq_pulse_o;
    wire [1:0] irq_reason_o;

    integer cycle_count;
    integer wait_count;

    vfs_sw_hw_comm_core #(
        .ADDR_W(ADDR_W),
        .PTR_W(PTR_W),
        .COUNT_W(COUNT_W),
        .BYTE_W(BYTE_W),
        .TIMEOUT_W(TIMEOUT_W),
        .ENTRY_BYTES(64),
        .MAX_BURST_ENTRIES(2)
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .sq_base_addr_i(sq_base_addr_i),
        .sq_tail_db_wr_en_i(sq_tail_db_wr_en_i),
        .sq_tail_db_i(sq_tail_db_i),
        .sq_head_o(sq_head_o),
        .sq_pending_o(sq_pending_o),
        .sq_cmd_valid_o(sq_cmd_valid_o),
        .sq_cmd_ready_i(sq_cmd_ready_i),
        .sq_cmd_addr_o(sq_cmd_addr_o),
        .sq_cmd_len_o(sq_cmd_len_o),
        .cq_base_addr_i(cq_base_addr_i),
        .cq_head_db_wr_en_i(cq_head_db_wr_en_i),
        .cq_head_db_i(cq_head_db_i),
        .cq_tail_o(cq_tail_o),
        .cq_pending_o(cq_pending_o),
        .cq_full_o(cq_full_o),
        .cpl_valid_i(cpl_valid_i),
        .cpl_ready_o(cpl_ready_o),
        .cpl_bytes_i(cpl_bytes_i),
        .cq_cmd_valid_o(cq_cmd_valid_o),
        .cq_cmd_ready_i(cq_cmd_ready_i),
        .cq_cmd_addr_o(cq_cmd_addr_o),
        .cq_cmd_len_o(cq_cmd_len_o),
        .cq_cmd_phase_o(cq_cmd_phase_o),
        .cq_write_done_i(cq_write_done_i),
        .irq_cqe_threshold_i(irq_cqe_threshold_i),
        .irq_byte_threshold_i(irq_byte_threshold_i),
        .irq_timeout_threshold_i(irq_timeout_threshold_i),
        .irq_pulse_o(irq_pulse_o),
        .irq_reason_o(irq_reason_o)
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
            sq_tail_db_wr_en_i = 1'b0;
            sq_tail_db_i = {PTR_W{1'b0}};
            sq_cmd_ready_i = 1'b0;
            cq_head_db_wr_en_i = 1'b0;
            cq_head_db_i = {PTR_W{1'b0}};
            cpl_valid_i = 1'b0;
            cpl_bytes_i = {BYTE_W{1'b0}};
            cq_cmd_ready_i = 1'b0;
            cq_write_done_i = 1'b0;
        end
    endtask

    task reset_dut;
        begin
            rst_i = 1'b1;
            idle_inputs();
            repeat (2) step();
            rst_i = 1'b0;
            step();

            if (sq_head_o !== 2'd0 || sq_pending_o !== 3'd0 || sq_cmd_valid_o !== 1'b0) begin
                fail("bad SQ reset release state");
            end
            if (cq_tail_o !== 2'd0 || cq_pending_o !== 3'd0 || cq_full_o !== 1'b0) begin
                fail("bad CQ reset release state");
            end
            if (irq_pulse_o !== 1'b0) begin
                fail("interrupt pulse should be low after reset");
            end
        end
    endtask

    task write_sq_tail;
        input [PTR_W-1:0] tail;
        begin
            sq_tail_db_i = tail;
            sq_tail_db_wr_en_i = 1'b1;
            step();
            sq_tail_db_wr_en_i = 1'b0;
            sq_tail_db_i = {PTR_W{1'b0}};
        end
    endtask

    task accept_sq_cmd;
        input [ADDR_W-1:0] expected_addr;
        input [COUNT_W-1:0] expected_len;
        begin
            for (wait_count = 0; wait_count < 6 && sq_cmd_valid_o !== 1'b1; wait_count = wait_count + 1) begin
                step();
            end

            if (sq_cmd_valid_o !== 1'b1) begin
                fail("SQ command did not become valid");
            end
            if (sq_cmd_addr_o !== expected_addr) begin
                fail("SQ command address mismatch");
            end
            if (sq_cmd_len_o !== expected_len) begin
                fail("SQ command length mismatch");
            end

            sq_cmd_ready_i = 1'b1;
            step();
            sq_cmd_ready_i = 1'b0;
        end
    endtask

    task write_cq_head;
        input [PTR_W-1:0] head;
        begin
            cq_head_db_i = head;
            cq_head_db_wr_en_i = 1'b1;
            step();
            cq_head_db_wr_en_i = 1'b0;
            cq_head_db_i = {PTR_W{1'b0}};
        end
    endtask

    task submit_cpl_and_accept_cmd;
        input [BYTE_W-1:0] bytes;
        input [ADDR_W-1:0] expected_addr;
        input expected_phase;
        begin
            if (cpl_ready_o !== 1'b1) begin
                fail("completion input should be ready");
            end

            cpl_bytes_i = bytes;
            cpl_valid_i = 1'b1;
            step();
            cpl_valid_i = 1'b0;
            cpl_bytes_i = {BYTE_W{1'b0}};

            if (cq_cmd_valid_o !== 1'b1) begin
                fail("CQ write command should become valid after completion input");
            end
            if (cq_cmd_addr_o !== expected_addr) begin
                fail("CQ command address mismatch");
            end
            if (cq_cmd_len_o !== 3'd1) begin
                fail("CQ command length should be one CQE");
            end
            if (cq_cmd_phase_o !== expected_phase) begin
                fail("CQ phase mismatch");
            end

            cq_cmd_ready_i = 1'b1;
            step();
            cq_cmd_ready_i = 1'b0;
        end
    endtask

    task complete_cq_write;
        input expected_irq;
        input [1:0] expected_reason;
        begin
            cq_write_done_i = 1'b1;
            step();
            cq_write_done_i = 1'b0;
            step();

            if (irq_pulse_o !== expected_irq) begin
                fail("unexpected interrupt pulse result");
            end
            if (expected_irq && irq_reason_o !== expected_reason) begin
                fail("unexpected interrupt reason");
            end
        end
    endtask

    task expect_timeout_irq;
        begin
            for (wait_count = 0; wait_count < 8 && irq_pulse_o !== 1'b1; wait_count = wait_count + 1) begin
                step();
            end
            if (irq_pulse_o !== 1'b1) begin
                fail("timeout interrupt did not arrive");
            end
            if (irq_reason_o !== IRQ_REASON_TIMEOUT) begin
                fail("timeout interrupt reason mismatch");
            end
        end
    endtask

    initial begin
        cycle_count = 0;
        sq_base_addr_i = 32'h0000_1000;
        cq_base_addr_i = 32'h0000_2000;
        irq_cqe_threshold_i = 3'd0;
        irq_byte_threshold_i = 16'd0;
        irq_timeout_threshold_i = 4'd0;

        reset_dut();

        write_sq_tail(2'd3);
        accept_sq_cmd(32'h0000_1000, 3'd2);
        if (sq_head_o !== 2'd2) begin
            fail("SQ head should advance by first burst");
        end
        accept_sq_cmd(32'h0000_1080, 3'd1);
        if (sq_head_o !== 2'd3 || sq_pending_o !== 3'd0) begin
            fail("SQ head should reach first doorbell tail");
        end

        write_sq_tail(2'd1);
        accept_sq_cmd(32'h0000_10c0, 3'd1);
        if (sq_head_o !== 2'd0) begin
            fail("SQ head should wrap after boundary command");
        end
        accept_sq_cmd(32'h0000_1000, 3'd1);
        if (sq_head_o !== 2'd1 || sq_pending_o !== 3'd0) begin
            fail("SQ wrap command sequence did not drain");
        end

        irq_cqe_threshold_i = 3'd2;
        irq_byte_threshold_i = 16'd0;
        irq_timeout_threshold_i = 4'd0;

        submit_cpl_and_accept_cmd(16'd64, 32'h0000_2000, 1'b1);
        if (cq_pending_o !== 3'd0) begin
            fail("CQ tail must not advance before write response");
        end
        complete_cq_write(1'b0, 2'd0);
        if (cq_tail_o !== 2'd1 || cq_pending_o !== 3'd1) begin
            fail("first CQE commit should advance CQ tail");
        end

        submit_cpl_and_accept_cmd(16'd64, 32'h0000_2040, 1'b1);
        complete_cq_write(1'b1, IRQ_REASON_COUNT);
        if (cq_tail_o !== 2'd2 || cq_pending_o !== 3'd2) begin
            fail("second CQE commit should reach count threshold");
        end

        submit_cpl_and_accept_cmd(16'd64, 32'h0000_2080, 1'b1);
        complete_cq_write(1'b0, 2'd0);
        if (cq_full_o !== 1'b1 || cpl_ready_o !== 1'b0) begin
            fail("CQ should apply one-empty-slot full policy");
        end

        write_cq_head(2'd2);
        if (cq_full_o !== 1'b0 || cpl_ready_o !== 1'b1 || cq_pending_o !== 3'd1) begin
            fail("CQ head doorbell should release completion backpressure");
        end

        submit_cpl_and_accept_cmd(16'd64, 32'h0000_20c0, 1'b1);
        complete_cq_write(1'b1, IRQ_REASON_COUNT);
        if (cq_tail_o !== 2'd0) begin
            fail("CQ tail should wrap after slot three");
        end

        write_cq_head(2'd3);
        submit_cpl_and_accept_cmd(16'd16, 32'h0000_2000, 1'b0);
        complete_cq_write(1'b0, 2'd0);

        reset_dut();
        irq_cqe_threshold_i = 3'd0;
        irq_byte_threshold_i = 16'd100;
        irq_timeout_threshold_i = 4'd0;
        submit_cpl_and_accept_cmd(16'd40, 32'h0000_2000, 1'b1);
        complete_cq_write(1'b0, 2'd0);
        submit_cpl_and_accept_cmd(16'd70, 32'h0000_2040, 1'b1);
        complete_cq_write(1'b1, IRQ_REASON_BYTES);

        reset_dut();
        irq_cqe_threshold_i = 3'd0;
        irq_byte_threshold_i = 16'd0;
        irq_timeout_threshold_i = 4'd3;
        submit_cpl_and_accept_cmd(16'd16, 32'h0000_2000, 1'b1);
        complete_cq_write(1'b0, 2'd0);
        expect_timeout_irq();

        $display("PASS vfs sw hw comm hierarchy");
        $finish;
    end
endmodule
