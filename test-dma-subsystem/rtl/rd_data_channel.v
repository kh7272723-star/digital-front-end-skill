`default_nettype none

// rd_data_channel: AXI R channel -> FIFO write port (pure datapath)
module rd_data_channel #(parameter DATA_W = 32) (
    input  wire               clk_i,
    input  wire               rst_i,
    // AXI R channel
    input  wire               rvalid_i,
    output wire               rready_o,
    input  wire [DATA_W-1:0]  rdata_i,
    input  wire               rlast_i,
    input  wire [1:0]         rresp_i,
    // FIFO write port
    output wire               fifo_wr_en_o,
    output wire [DATA_W:0]    fifo_wr_data_o,  // {data, last}
    input  wire               fifo_full_i,
    // Error
    output reg                error_o
);

    // ---------------------------------------------------------------
    // Datapath: R channel -> FIFO write
    // ---------------------------------------------------------------
    // Accept R data when FIFO not full
    assign rready_o = !fifo_full_i;

    // Write into FIFO on valid handshake
    assign fifo_wr_en_o = rvalid_i && rready_o;

    // Pack data + last into FIFO word
    assign fifo_wr_data_o = {rdata_i, rlast_i};

    // ---------------------------------------------------------------
    // Error latch: set on first non-OKAY rresp
    // ---------------------------------------------------------------
    wire r_handshake = rvalid_i && rready_o;

    always @(posedge clk_i) begin
        if (rst_i) begin
            error_o <= 1'b0;
        end else if (r_handshake && (rresp_i != 2'b00) && !error_o) begin
            error_o <= 1'b1;
        end
    end

endmodule

`default_nettype wire
