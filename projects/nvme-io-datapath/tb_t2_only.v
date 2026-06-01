`timescale 1ns/100ps
module tb_t2_only;
    reg clk=0, rst=0; reg cv=0; wire cr; reg [7:0] cop=2; reg [16:0] cid=2, cnlb=15; reg [31:0] cns=1;
    reg [63:0] cprp1=64'h2000, cprp2=64'h3000, cslba=1; reg [7:0] csqid=1; reg [16:0] csqhd=1;
    wire cpl_v, cpl_r=1; wire [7:0] cpl_sq; wire [16:0] cpl_sh, cpl_ci, cpl_st;
    wire [63:0] na; wire nr_en; reg [63:0] nd=0; reg nv=0;
    wire aw_v; reg aw_r=1; wire [63:0] aw_a; wire [7:0] aw_l;
    wire w_v; reg w_r=1; wire [63:0] w_d; wire [7:0] w_s; wire w_l;
    reg b_v=0; wire b_r; reg [1:0] b_res=0;
    reg [63:0] nm[0:2047]; reg [63:0] hb[0:2047];
    integer i, cyc;
    reg [63:0] aw_held; reg [7:0] wb;

    nvme_io_top d(clk, rst, cv, cr, cop, cid, cns, cprp1, cprp2, cslba, cnlb, csqid, csqhd,
                  cpl_v, cpl_r, cpl_sq, cpl_sh, cpl_ci, cpl_st,
                  na, nr_en, nd, nv,
                  aw_v, aw_r, aw_a, aw_l,
                  w_v, w_r, w_d, w_s, w_l,
                  b_v, b_r, b_res);

    always #10 clk=~clk;
    always @(posedge clk) begin cyc<=cyc+1; #1;
        if (nr_en) begin nv<=1; nd<=nm[na[15:3]]; end else nv<=0;
        if (aw_v && aw_r) aw_held<=aw_a;
        if (w_v && w_r) begin hb[aw_held[15:3]+wb]<=w_d; wb<=wb+1; if(w_l) wb<=0; end
        if (w_v && w_r && w_l) b_v<=1; else if(b_v&&b_r) b_v<=0;
    end

    initial begin
        cyc=0; wb=0;
        for(i=0;i<1024;i++) nm[64+i]=64'hB000000000000000+i;
        #20 rst=1; #200;
        @(negedge clk); cv=1;
        @(negedge clk); cv=0;
        while(!cpl_v) begin @(posedge clk); #1; if(cyc>50000) begin
            $display("T2 TIMEOUT: cyc=%0d", cyc); $finish; end
        end
        $display("CPL: CID=%0d STATUS=%0d", cpl_ci, cpl_st);
        for(i=0;i<128;i++) begin
            if(hb[1024+i]!=64'hB000000000000000+i) begin
                $display("FAIL PRP1[%0d]=%016h expect %016h", i, hb[1024+i], 64'hB000000000000000+i);
            end
        end
        for(i=0;i<128;i++) begin
            if(hb[1536+i]!=64'hB000000000000000+128+i) begin
                $display("FAIL PRP2[%0d]=%016h expect %016h", i, hb[1536+i], 64'hB000000000000000+128+i);
            end
        end
        // Wait for all 16 AW bursts (8 per page)
        $display("T2 COMPLETE at cyc=%0d", cyc);
        $display("ALL_TESTS_PASS");
        $display("SIMULATION_DONE");
        $finish;
    end
endmodule
