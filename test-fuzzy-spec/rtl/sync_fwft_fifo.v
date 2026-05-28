`default_nettype none

// Synchronous FWFT (First-Word-Fall-Through) FIFO with flush
// FWFT: combinational read; data visible same cycle as empty_o deasserts
// flush_i: synchronous clear of all pointers and count

module sync_fwft_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 256
) (
    input  wire                    clk_i,
    input  wire                    rst_i,

    // Write interface
    input  wire                    wr_en_i,
    input  wire [DATA_WIDTH-1:0]   wdata_i,
    output wire                    full_o,

    // Read interface (FWFT: combinational output)
    output wire [DATA_WIDTH-1:0]   rdata_o,
    input  wire                    rd_en_i,
    output wire                    empty_o,

    // Flush: discard all data, reset pointers (synchronous clear)
    input  wire                    flush_i,

    // Occupancy count (optional, width depends on DEPTH)
    output wire [$clog2(DEPTH+1)-1:0] count_o
);

    localparam ADDR_W = $clog2(DEPTH);

    // Memory
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Pointers
    reg [ADDR_W-1:0] wr_ptr_q;
    reg [ADDR_W-1:0] rd_ptr_q;
    reg [ADDR_W:0]   count_q;

    // Accepted operations
    wire wr_do = wr_en_i && !full_o && !flush_i;
    wire rd_do = rd_en_i && !empty_o && !flush_i;

    // Write pointer
    always @(posedge clk_i) begin
        if (rst_i || flush_i) begin
            wr_ptr_q <= {ADDR_W{1'b0}};
        end else if (wr_do) begin
            wr_ptr_q <= wr_ptr_q + {{ADDR_W-1{1'b0}}, 1'b1};
        end
    end

    // Read pointer
    always @(posedge clk_i) begin
        if (rst_i || flush_i) begin
            rd_ptr_q <= {ADDR_W{1'b0}};
        end else if (rd_do) begin
            rd_ptr_q <= rd_ptr_q + {{ADDR_W-1{1'b0}}, 1'b1};
        end
    end

    // Count
    always @(posedge clk_i) begin
        if (rst_i || flush_i) begin
            count_q <= {(ADDR_W+1){1'b0}};
        end else begin
            case ({wr_do, rd_do})
                2'b10:   count_q <= count_q + {{ADDR_W{1'b0}}, 1'b1};
                2'b01:   count_q <= count_q - {{ADDR_W{1'b0}}, 1'b1};
                default: count_q <= count_q;
            endcase
        end
    end

    // Write data
    always @(posedge clk_i) begin
        if (wr_do) begin
            mem[wr_ptr_q] <= wdata_i;
        end
    end

    // FWFT read: combinational (data valid same cycle as empty_o deasserts)
    assign rdata_o = mem[rd_ptr_q];

    // Status
    assign full_o  = (count_q == DEPTH[ADDR_W:0]);
    assign empty_o = (count_q == {(ADDR_W+1){1'b0}});
    assign count_o = count_q;

endmodule

`default_nettype wire
