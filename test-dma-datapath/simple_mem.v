`default_nettype none

// Parameterized synchronous memory with registered read output.
// Models real SRAM: write on posedge, read data available next cycle.
module simple_mem #(
    parameter DATA_W = 32,
    parameter ADDR_W = 8,
    parameter DEPTH  = 256
)(
    input  wire               clk_i,
    input  wire               rst_i,
    // Write port
    input  wire               wr_en_i,
    input  wire [ADDR_W-1:0]  wr_addr_i,
    input  wire [DATA_W-1:0]  wr_data_i,
    // Read port
    input  wire               rd_en_i,
    input  wire [ADDR_W-1:0]  rd_addr_i,
    output reg  [DATA_W-1:0]  rd_data_o
);

    reg [DATA_W-1:0] mem [0:DEPTH-1];

    always @(posedge clk_i) begin
        if (rst_i) begin
            rd_data_o <= {DATA_W{1'b0}};
        end else begin
            if (wr_en_i) mem[wr_addr_i] <= wr_data_i;
            if (rd_en_i) rd_data_o <= mem[rd_addr_i];
        end
    end

endmodule
`default_nettype wire
