`default_nettype none

// DMA configuration register slave.
// Direct register interface (not APB).
// Registers: 0x0=src_addr, 0x4=dst_addr, 0x8=byte_count, 0xC=control/status
module dma_cfg_slave #(
    parameter ADDR_W   = 32,
    parameter DATA_W   = 32,
    parameter COUNT_W  = 16
)(
    input  wire               clk_i,
    input  wire               rst_i,
    // Config interface
    input  wire               cfg_wr_en_i,
    input  wire [3:0]         cfg_addr_i,
    input  wire [DATA_W-1:0]  cfg_wdata_i,
    output reg  [DATA_W-1:0]  cfg_rdata_o,
    // To burst planner
    output reg  [ADDR_W-1:0]  src_addr_o,
    output reg  [ADDR_W-1:0]  dst_addr_o,
    output reg  [COUNT_W-1:0] byte_count_o,
    output reg                start_o,
    // From completion
    input  wire               busy_i,
    input  wire               done_i,
    input  wire               error_i
);

    reg done_q;

    // Config write + status
    always @(posedge clk_i) begin
        if (rst_i) begin
            src_addr_o   <= {ADDR_W{1'b0}};
            dst_addr_o   <= {ADDR_W{1'b0}};
            byte_count_o <= {COUNT_W{1'b0}};
            start_o      <= 1'b0;
            done_q       <= 1'b0;
        end else begin
            start_o <= 1'b0;
            if (done_i) done_q <= 1'b1;
            if (cfg_wr_en_i && !busy_i) begin
                case (cfg_addr_i)
                    4'h0: src_addr_o   <= cfg_wdata_i[ADDR_W-1:0];
                    4'h4: dst_addr_o   <= cfg_wdata_i[ADDR_W-1:0];
                    4'h8: byte_count_o <= cfg_wdata_i[COUNT_W-1:0];
                    4'hC: begin
                        start_o <= cfg_wdata_i[0];
                        done_q  <= 1'b0; // clear done on new start
                    end
                endcase
            end
        end
    end

    // Config read (combinational)
    always @(*) begin
        cfg_rdata_o = {DATA_W{1'b0}};
        case (cfg_addr_i)
            4'h0: cfg_rdata_o = {{(DATA_W-ADDR_W){1'b0}}, src_addr_o};
            4'h4: cfg_rdata_o = {{(DATA_W-ADDR_W){1'b0}}, dst_addr_o};
            4'h8: cfg_rdata_o = {{(DATA_W-COUNT_W){1'b0}}, byte_count_o};
            4'hC: cfg_rdata_o = {{(DATA_W-3){1'b0}}, error_i, done_q, busy_i};
        endcase
    end

endmodule
`default_nettype wire
