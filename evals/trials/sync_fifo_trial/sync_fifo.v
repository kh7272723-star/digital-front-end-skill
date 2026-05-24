module sync_fifo #(
    parameter DATA_W = 8,
    parameter DEPTH = 4
) (
    input  wire              clk_i,
    input  wire              rst_i,
    input  wire              wr_en_i,
    input  wire [DATA_W-1:0] wdata_i,
    input  wire              rd_en_i,
    output wire [DATA_W-1:0] rdata_o,
    output wire              full_o,
    output wire              empty_o,
    output reg               overflow_o,
    output reg               underflow_o
);

    localparam PTR_W   = $clog2(DEPTH > 1 ? DEPTH : 2);
    localparam COUNT_W = PTR_W + 1;

    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [COUNT_W-1:0] count_q;
    reg [PTR_W-1:0]   wr_ptr_q;
    reg [PTR_W-1:0]   rd_ptr_q;
    reg [DATA_W-1:0]  rd_data_q;

    wire wr_do = wr_en_i && !full_o;
    wire rd_do = rd_en_i && !empty_o;

    assign full_o     = (count_q == DEPTH[COUNT_W-1:0]);
    assign empty_o    = (count_q == {COUNT_W{1'b0}});
    assign rdata_o    = rd_data_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            count_q      <= {COUNT_W{1'b0}};
            wr_ptr_q     <= {PTR_W{1'b0}};
            rd_ptr_q     <= {PTR_W{1'b0}};
            rd_data_q    <= {DATA_W{1'b0}};
            overflow_o   <= 1'b0;
            underflow_o  <= 1'b0;
        end else begin
            if (wr_do) begin
                mem[wr_ptr_q] <= wdata_i;
                wr_ptr_q <= wr_ptr_q + {{PTR_W-1{1'b0}}, 1'b1};
            end
            if (rd_do) begin
                rd_data_q <= mem[rd_ptr_q];
                rd_ptr_q <= rd_ptr_q + {{PTR_W-1{1'b0}}, 1'b1};
            end
            case ({wr_do, rd_do})
                2'b10:   count_q <= count_q + {{COUNT_W-1{1'b0}}, 1'b1};
                2'b01:   count_q <= count_q - {{COUNT_W-1{1'b0}}, 1'b1};
                default: count_q <= count_q;
            endcase
            if (wr_en_i && full_o && !rd_do) begin
                overflow_o <= 1'b1;
            end
            if (rd_en_i && empty_o) begin
                underflow_o <= 1'b1;
            end
        end
    end

endmodule
