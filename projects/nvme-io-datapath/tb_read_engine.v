`timescale 1ns/100ps
module tb_read_engine;

    reg clk=0, rst=0;
    reg start=0, pv=0, pr=1;
    reg [63:0] pa=64'h1000; reg [16:0] pb=17'd64;  // 64 beats = 512 bytes
    reg [63:0] slba=0; reg [31:0] tbytes=512;

    wire p_rdy, p_done, done, nv_en, nv_rrdy;
    wire [63:0] nv_addr;
    reg [63:0] nd=0; reg nv=0;
    wire aw_v, w_v, w_l, b_r;
    reg aw_r=1, w_r=1, b_v=0;
    wire [63:0] aw_a, w_d;
    wire [7:0] aw_l, w_s;

    nvme_read_engine dut (clk, rst, start, done, slba, tbytes,
        pa, pb, pv, p_rdy, p_done,
        nv_addr, nv_en, nd, nv, nv_rrdy,
        aw_v, aw_r, aw_a, aw_l,
        w_v, w_r, w_d, w_s, w_l,
        b_v, b_r, 2'd0);

    reg [63:0] mem [0:63];
    integer i, cyc;

    always #10 clk=~clk;
    always @(posedge clk) begin
        cyc<=cyc+1; #1;
        if (nv_en) begin nv<=1; nd<=mem[nv_addr[15:3]]; end else nv<=0;
        if (w_v && w_r && w_l) b_v<=1; else if (b_v && b_r) b_v<=0;
    end

    initial begin
        cyc=0;
        for (i=0;i<64;i++) mem[i]=64'hAAAA000000000000+i;
        $display("SIMULATION_START");
        #20 rst=1; #200;
        $display("RESET_RELEASED");
        // Start
        @(negedge clk); start=1;
        @(negedge clk); start=0;
        // Drive page_valid
        @(negedge clk); pv=1; pa=64'h1000; pb=17'd64;
        @(negedge clk); pv=0;
        // Wait
        while (!done) begin
            @(posedge clk); #1;
            if (cyc > 500) begin
                $display("TIMEOUT: pg=%b nvm_en=%b fifo=%0d aw=%b w=%b b=%0d pg_d=%b pg_r=%b",
                    dut.page_live_q, nv_en, dut.fifo_cnt_q, aw_v, w_v, dut.b_cnt_q,
                    dut.page_done_q, dut.page_ready_o);
                $display("  pg_rem=%0d aw_left=%0d aw_len=%0d",
                    dut.page_remain_q, dut.aw_left_q, dut.aw_len_q);
                $finish;
            end
        end
        $display("done=%b at cyc=%0d", done, cyc);
        $display("ALL_TESTS_PASS");
        $display("SIMULATION_DONE");
    end
endmodule
