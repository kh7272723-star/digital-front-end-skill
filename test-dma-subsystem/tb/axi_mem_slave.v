`default_nettype none

// Simple AXI memory slave for DMA testing.
// Supports single-beat and burst read/write.
// Registered read output (1-cycle latency).
module axi_mem_slave #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter DEPTH  = 256
)(
    input  wire               clk_i,
    input  wire               rst_i,
    // AXI AR
    input  wire               arvalid_i,
    output reg                arready_o,
    input  wire [ADDR_W-1:0]  araddr_i,
    input  wire [7:0]         arlen_i,
    // AXI R
    output reg                rvalid_o,
    input  wire               rready_i,
    output reg  [DATA_W-1:0]  rdata_o,
    output reg                rlast_o,
    output reg  [1:0]         rresp_o,
    // AXI AW
    input  wire               awvalid_i,
    output reg                awready_o,
    input  wire [ADDR_W-1:0]  awaddr_i,
    input  wire [7:0]         awlen_i,
    // AXI W
    input  wire               wvalid_i,
    output reg                wready_o,
    input  wire [DATA_W-1:0]  wdata_i,
    input  wire               wlast_i,
    input  wire [DATA_W/8-1:0] wstrb_i,
    // AXI B
    output reg                bvalid_o,
    input  wire               bready_i,
    output reg  [1:0]         bresp_o
);

    reg [DATA_W-1:0] mem [0:DEPTH-1];

    // Read state
    reg        rd_active_q;
    reg [7:0]  rd_addr_q;
    reg [7:0]  rd_beats_q;

    // Write state
    reg        wr_active_q;
    reg [7:0]  wr_addr_q;
    reg [7:0]  wr_beats_q;
    reg        wr_b_pending_q;

    // Read path
    always @(posedge clk_i) begin
        if (rst_i) begin
            arready_o   <= 1'b1;
            rvalid_o    <= 1'b0;
            rdata_o     <= 0;
            rlast_o     <= 1'b0;
            rresp_o     <= 2'b00;
            rd_active_q <= 1'b0;
            rd_addr_q   <= 0;
            rd_beats_q  <= 0;
        end else begin
            if (arvalid_i && arready_o && !rd_active_q) begin
                rd_active_q <= 1'b1;
                rd_addr_q   <= araddr_i[7:0];
                rd_beats_q  <= arlen_i;
                arready_o   <= 1'b0;
            end

            if (rd_active_q) begin
                rvalid_o  <= 1'b1;
                rdata_o   <= mem[rd_addr_q];
                rresp_o   <= 2'b00;
                rlast_o   <= (rd_beats_q == 0);
                if (rvalid_o && rready_i) begin
                    rd_addr_q <= rd_addr_q + 1;
                    if (rd_beats_q == 0) begin
                        rd_active_q <= 1'b0;
                        rvalid_o    <= 1'b0;
                        arready_o   <= 1'b1;
                    end else begin
                        rd_beats_q <= rd_beats_q - 1;
                    end
                end
            end
        end
    end

    // Write path
    always @(posedge clk_i) begin
        if (rst_i) begin
            awready_o      <= 1'b1;
            wready_o       <= 1'b0;
            bvalid_o       <= 1'b0;
            bresp_o        <= 2'b00;
            wr_active_q    <= 1'b0;
            wr_addr_q      <= 0;
            wr_beats_q     <= 0;
            wr_b_pending_q <= 1'b0;
        end else begin
            if (awvalid_i && awready_o && !wr_active_q) begin
                wr_active_q <= 1'b1;
                wr_addr_q   <= awaddr_i[7:0];
                wr_beats_q  <= awlen_i;
                awready_o   <= 1'b0;
                wready_o    <= 1'b1;
            end

            if (wr_active_q && wvalid_i && wready_o) begin
                mem[wr_addr_q] <= wdata_i;
                wr_addr_q <= wr_addr_q + 1;
                if (wlast_i || wr_beats_q == 0) begin
                    wr_active_q    <= 1'b0;
                    wready_o       <= 1'b0;
                    wr_b_pending_q <= 1'b1;
                end else begin
                    wr_beats_q <= wr_beats_q - 1;
                end
            end

            if (wr_b_pending_q) begin
                bvalid_o       <= 1'b1;
                bresp_o        <= 2'b00;
                wr_b_pending_q <= 1'b0;
            end

            if (bvalid_o && bready_i) begin
                bvalid_o  <= 1'b0;
                awready_o <= 1'b1;
            end
        end
    end

endmodule
`default_nettype wire
