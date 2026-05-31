`timescale 1ns/100ps
module dbg;
    reg clk=0, rst=1, v=0, l=0, tr=1;
    reg [7:0] d=0;
    wire to, vo, lo, done;
    wire [7:0] cnt;
    wire [7:0] dout;
    fork_join_pipeline #(8,2) u(clk,rst,v,to,d,l,vo,tr,dout,lo,done,cnt);

    always #10 clk=~clk;
    initial begin
        $monitor("%0t: st=%0d s0v=%0b s1v=%0b to=%0b vo=%0b done=%0b cnt=%0d fire=%0b",
                 $time, u.state_q, u.s0_valid_q, u.s1_valid_q, to, vo, done, cnt, u.joiner_fire_q);
        #20 rst=0; #100 rst=1; #200;
        @(negedge clk); v=1; d=42; l=1;
        #2000 $finish;
    end
endmodule
