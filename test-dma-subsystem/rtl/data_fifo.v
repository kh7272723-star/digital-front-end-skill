`default_nettype none

// Synchronous FWFT FIFO with {data, last} payload
module data_fifo #(parameter DATA_W=32, DEPTH=16) (
    input  wire                 clk_i,
    input  wire                 rst_i,
    input  wire                 wr_en_i,
    input  wire [DATA_W:0]      wr_data_i,   // {data, last}
    output wire                 full_o,
    input  wire                 rd_en_i,
    output wire [DATA_W:0]      rd_data_o,   // {data, last}
    output wire                 empty_o
);

    localparam ADDR_W = $clog2(DEPTH);

    // Memory and pointers
    reg [DATA_W:0] mem_q [0:DEPTH-1];
    reg [ADDR_W:0] wr_ptr_q;
    reg [ADDR_W:0] rd_ptr_q;

    // Next-state signals
    reg [ADDR_W:0] wr_ptr_d;
    reg [ADDR_W:0] rd_ptr_d;

    // FWFT: data output is combinational from memory
    assign rd_data_o = mem_q[rd_ptr_q[ADDR_W-1:0]];

    // Full: MSBs differ, lower bits match
    assign full_o  = (wr_ptr_q[ADDR_W] != rd_ptr_q[ADDR_W]) &&
                     (wr_ptr_q[ADDR_W-1:0] == rd_ptr_q[ADDR_W-1:0]);

    // Empty: pointers equal
    assign empty_o = (wr_ptr_q == rd_ptr_q);

    // Combinational next-state for pointers
    always @(*) begin
        wr_ptr_d = wr_ptr_q;
        rd_ptr_d = rd_ptr_q;

        if (wr_en_i && !full_o) begin
            wr_ptr_d = wr_ptr_q + 1'b1;
        end
        if (rd_en_i && !empty_o) begin
            rd_ptr_d = rd_ptr_q + 1'b1;
        end
    end

    // Sequential: memory write and pointer update
    always @(posedge clk_i) begin
        if (rst_i) begin
            wr_ptr_q <= {(ADDR_W+1){1'b0}};
            rd_ptr_q <= {(ADDR_W+1){1'b0}};
        end else begin
            wr_ptr_q <= wr_ptr_d;
            rd_ptr_q <= rd_ptr_d;
            if (wr_en_i && !full_o) begin
                mem_q[wr_ptr_q[ADDR_W-1:0]] <= wr_data_i;
            end
        end
    end

endmodule

`default_nettype wire
