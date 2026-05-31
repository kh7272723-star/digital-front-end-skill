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
        $monitor("%0t: to=%0b s0v=%0b s1v=%0b vo=%0b tr=%0b done=%0b cnt=%0d infl=%0b",
                 $time, to, u.s0_valid_q, u.s1_valid_q, vo, tr, done, cnt, u.pkt_in_flight_q);
        #10 rst=0; #100 rst=1; #200;
        // Single beat
        tr = 1'b1;
        @(negedge clk); v=1; d=77; l=1;  // send beat
        while (!to) @(negedge clk);       // wait for acceptance
        @(negedge clk); v=0;
        // NOW stall
        tr = 1'b0;
        repeat(5) @(posedge clk);
        $display("--- After 5 stall cycles: done=%b s1v=%b infl=%b ---", done, u.s1_valid_q, u.pkt_in_flight_q);
        // Release
        tr = 1'b1;
        repeat(10) @(posedge clk);
        $display("--- After release: done=%b s1v=%b infl=%b ---", done, u.s1_valid_q, u.pkt_in_flight_q);
        #1000 $finish;
    end
endmodule
