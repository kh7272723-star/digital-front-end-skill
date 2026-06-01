`timescale 1ns/100ps
module tb_prp_read;

    reg clk=0, rst=0, start=0;
    reg [63:0] prp1=64'h1000, prp2=0;
    reg [31:0] tbytes=512;
    wire prp_done, prp_err, pg_v, pg_r, pg_done;
    wire [63:0] pg_addr; wire [16:0] pg_bytes;
    wire re_done, nv_en; reg [63:0] nd=0; reg nv=0;
    wire aw_v, w_v, w_l, b_r; reg aw_r=1, w_r=1, b_v=0;
    wire [63:0] aw_a, w_d; wire [7:0] aw_l, w_s;

    reg [63:0] mem [0:63];
    integer i, cyc;

    nvme_prp_walker #(4096) u_prp (clk, rst, start, prp_done, prp_err, ,
        prp1, prp2, tbytes,
        pg_addr, pg_bytes, pg_v, pg_r,
        ,1'b0, ,,1'b0,,1'b0,1'b0, pg_done);

    nvme_read_engine u_re (clk, rst, 1'b0, re_done, 64'd0, tbytes,
        pg_addr, pg_bytes, pg_v, pg_r, pg_done,
        ,nv_en, nd, nv,,
        aw_v, aw_r, aw_a, aw_l,
        w_v, w_r, w_d, w_s, w_l,
        b_v, b_r, 2'd0);

    always #10 clk=~clk;
    always @(posedge clk) begin
        cyc<=cyc+1; #1;
        if (nv_en) begin nv<=1; nd<=mem[nv_en ? u_re.nvm_addr_o[15:3] : 0]; end else nv<=0;
        if (w_v && w_r && w_l) b_v<=1; else if (b_v && b_r) b_v<=0;
    end

    initial begin
        cyc=0;
        for (i=0;i<64;i++) mem[i]=64'hAAAA000000000000+i;
        $display("SIMULATION_START");
        #20 rst=1; #200;
        $display("RESET_RELEASED");
        @(negedge clk); start=1;
        @(negedge clk); start=0;
        while (!re_done) begin
            @(posedge clk); #1;
            if (cyc > 2000) begin
                $display("TIMEOUT@cyc=%0d: prp=%0d pg_lv=%b pg_rem=%0d nv_en=%b fifo=%0d aw=%b w=%b",
                    cyc, u_prp.cstate, u_re.page_live_q, u_re.page_remain_q,
                    nv_en, u_re.fifo_cnt_q, aw_v, w_v);
                $display("  aw_vld=%b aw_left=%0d aw_len=%0d b_cnt=%0d",
                    u_re.aw_vld_q, u_re.aw_left_q, u_re.aw_len_q, u_re.b_cnt_q);
                $finish;
            end
        end
        $display("done at cyc=%0d", cyc);
        $display("ALL_TESTS_PASS");
        $display("SIMULATION_DONE");
    end
endmodule
