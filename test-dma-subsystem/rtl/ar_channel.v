`default_nettype none

// AXI AR address channel with command buffer
module ar_channel #(parameter ADDR_W=32, LEN_W=8) (
    input  wire               clk_i,
    input  wire               rst_i,
    // Command from burst planner
    input  wire               cmd_valid_i,
    output wire               cmd_ready_o,
    input  wire [ADDR_W-1:0]  cmd_addr_i,
    input  wire [LEN_W-1:0]   cmd_len_i,
    // AXI AR
    output reg                arvalid_o,
    input  wire               arready_i,
    output reg  [ADDR_W-1:0]  araddr_o,
    output reg  [7:0]         arlen_o
);

    // Next-state signals
    reg                arvalid_d;
    reg  [ADDR_W-1:0]  araddr_d;
    reg  [7:0]         arlen_d;

    // Accept command when not driving AR
    assign cmd_ready_o = !arvalid_o;

    // Combinational next-state
    always @(*) begin
        // Defaults: hold state
        arvalid_d = arvalid_o;
        araddr_d  = araddr_o;
        arlen_d   = arlen_o;

        if (arvalid_o && arready_i) begin
            // Handshake complete: deassert valid
            arvalid_d = 1'b0;
        end else if (!arvalid_o && cmd_valid_i) begin
            // Latch new command
            arvalid_d = 1'b1;
            araddr_d  = cmd_addr_i;
            arlen_d   = cmd_len_i;
        end
    end

    // Sequential register update
    always @(posedge clk_i) begin
        if (rst_i) begin
            arvalid_o <= 1'b0;
            araddr_o  <= {ADDR_W{1'b0}};
            arlen_o   <= 8'd0;
        end else begin
            arvalid_o <= arvalid_d;
            araddr_o  <= araddr_d;
            arlen_o   <= arlen_d;
        end
    end

endmodule

`default_nettype wire
