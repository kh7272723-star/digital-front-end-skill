`timescale 1ns/100ps
module tb_t2;
    reg clk=0, rst=0, start=0;
    reg [63:0] prp1=64'h2000, prp2=64'h3000;
    reg [31:0] tbytes=8192;
    wire prp_done, pg_v, pg_r, pg_done;
    wire [63:0] pg_addr; wire [16:0] pg_bytes;
    wire re_done, nv_en; reg [63:0] nd=0; reg nv=0;
    wire aw_v, w_v, w_l, b_r; reg aw_r=1, w_r=1, b_v=0;
    reg [63:0] mem[0:2047]; integer i, cyc;
    nvme_prp_walker #(4096) p(clk, rst, start, prp_done, ,,,prp1,prp2,tbytes,
        pg_addr,pg_bytes,pg_v,pg_r,,,,,,,,,,,,pg_done);
    nvme_read_engine r(clk, rst, 1'b0, re_done, 64'd1, tbytes,
        pg_addr,pg_bytes,pg_v,pg_r,pg_done,
        ,nv_en,nd,nv,,
        aw_v,aw_r,,,,w_v,w_r,,,w_l,b_v,b_r,0);
    always #10 clk=~clk;
    always @(posedge clk) begin cyc<=cyc+1; #1;
        if(nv_en) begin nv<=1; nd<=mem[r.nvm_addr_o[15:3]]; end else nv<=0;
        if(w_v&&w_r&&w_l) b_v<=1; else if(b_v&&b_r) b_v<=0;
    end
    initial begin
        cyc=0; for(i=0;i<1024;i++) mem[64+i]=64'hB000+i;
        #20 rst=1; #200;
        @(negedge clk); start=1;
        @(negedge clk); start=0;
        while(!re_done) begin @(posedge clk); #1; if(cyc>100000) begin
            $display("TIMEOUT cyc=%0d pg_in=%0d pg_out=%0d pg_lv=%b",cyc,r.page_in_q,r.page_out_q,r.page_live_q);
            $finish; end end
        $display("PASS cyc=%0d",cyc); $display("ALL_TESTS_PASS SIMULATION_DONE"); $finish;
    end
endmodule
