`default_nettype none

// AXI AW address channel with command buffer
module aw_channel #(parameter ADDR_W=32, LEN_W=8) (
    input  wire               clk_i,
    input  wire               rst_i,
    // Command from burst planner
    input  wire               cmd_valid_i,
    output wire               cmd_ready_o,
    input  wire [ADDR_W-1:0]  cmd_addr_i,
    input  wire [LEN_W-1:0]   cmd_len_i,
    // AXI AW
    output reg                awvalid_o,
    input  wire               awready_i,
    output reg  [ADDR_W-1:0]  awaddr_o,
    output reg  [7:0]         awlen_o
);

    // Next-state signals
    reg                awvalid_d;
    reg  [ADDR_W-1:0]  awaddr_d;
    reg  [7:0]         awlen_d;

    // Accept command when not driving AW
    assign cmd_ready_o = !awvalid_o;

    // Combinational next-state
    always @(*) begin
        // Defaults: hold state
        awvalid_d = awvalid_o;
        awaddr_d  = awaddr_o;
        awlen_d   = awlen_o;

        if (awvalid_o && awready_i) begin
            // Handshake complete: deassert valid
            awvalid_d = 1'b0;
        end else if (!awvalid_o && cmd_valid_i) begin
            // Latch new command
            awvalid_d = 1'b1;
            awaddr_d  = cmd_addr_i;
            awlen_d   = cmd_len_i;
        end
    end

    // Sequential register update
    always @(posedge clk_i) begin
        if (rst_i) begin
            awvalid_o <= 1'b0;
            awaddr_o  <= {ADDR_W{1'b0}};
            awlen_o   <= 8'd0;
        end else begin
            awvalid_o <= awvalid_d;
            awaddr_o  <= awaddr_d;
            awlen_o   <= awlen_d;
        end
    end

endmodule

`default_nettype wire
