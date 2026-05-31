`timescale 1ns / 100ps
module tb_standalone;

    localparam DW = 64;
    localparam N  = 3;  // pipeline stages

    reg clk, rst_n, in_valid, out_ready;
    wire in_ready, out_valid;
    reg [DW-1:0] in_data;
    wire [DW-1:0] out_data;

    // Pipeline registers
    reg [N:0]            v_q;  // v_q[0]=input reg, v_q[N]=output
    reg [N:0] [DW-1:0]  d_q;
    wire [N:0]            rdy;  // backpressure chain

    assign rdy[N] = out_ready;
    genvar g;
    generate for (g = 0; g < N; g = g + 1) begin : bp
        assign rdy[g] = rdy[g+1] || !v_q[g+1];
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_q <= {N+1{1'b0}};
            d_q <= {N+1{{DW{1'b0}}}};
        end else begin
            if (rdy[0]) begin v_q[0] <= in_valid; d_q[0] <= in_data; end
            if (rdy[1]) begin v_q[1] <= v_q[0];   d_q[1] <= d_q[0]; end
            if (rdy[2]) begin v_q[2] <= v_q[1];   d_q[2] <= d_q[1]; end
            if (rdy[3]) begin v_q[3] <= v_q[2];   d_q[3] <= d_q[2]; end
        end
    end

    assign in_ready  = rdy[0];
    assign out_valid = v_q[N];
    assign out_data  = d_q[N];

    // Testbench
    always #10 clk = ~clk;
    integer i, errors, sent, recvd;
    reg [DW-1:0] expected;

    initial begin
        clk = 0; errors = 0; sent = 0; recvd = 0;
        {in_valid, in_data, out_ready} = 0;
        rst_n = 0; repeat (10) @(posedge clk);
        rst_n = 1; repeat (5) @(posedge clk);
        $display("SIMULATION_START");
        $display("RESET_RELEASED");
        out_ready = 1;

        // Send 5 beats
        in_valid = 1;
        for (i = 0; i < 5; i = i + 1) begin
            in_data = 64'h10 + i;
            @(posedge clk);
        end
        in_valid = 0;

        // Drain
        repeat (20) @(posedge clk);
        $display("Drain done. Checking output...");

        $display("SIMULATION_DONE");
        $finish;
    end

    // Monitor: count received beats
    always @(posedge clk) begin
        if (out_valid && out_ready) begin
            $display("  RX beat %0d: data=%h at time %0t", recvd, out_data, $time);
            if (out_data != 64'h10 + recvd) begin
                $display("  ERROR: expected %h", 64'h10 + recvd);
                errors = errors + 1;
            end
            recvd = recvd + 1;
        end
        if (in_valid && in_ready) begin
            $display("  TX beat %0d: data=%h at time %0t", sent, in_data, $time);
            sent = sent + 1;
        end
    end

endmodule
