module retry_buffer #(
    parameter DATA_W = 8,
    parameter DEPTH = 4,
    parameter PTR_W = 2,
    parameter COUNT_W = 3
) (
    input  wire                 clk_i,
    input  wire                 rst_i,
    input  wire                 valid_i,
    output wire                 ready_o,
    input  wire [DATA_W-1:0]    data_i,
    output wire                 valid_o,
    input  wire                 ready_i,
    output wire [DATA_W-1:0]    data_o,
    input  wire                 ack_i,
    input  wire                 nak_i,
    output wire                 full_o,
    output wire                 in_flight_o
);
    localparam [COUNT_W-1:0] DEPTH_COUNT = DEPTH;
    localparam [PTR_W-1:0] LAST_PTR = DEPTH - 1;

    reg [DATA_W-1:0] mem [0:DEPTH-1];

    reg [PTR_W-1:0]   wr_ptr_q;
    reg [PTR_W-1:0]   rd_ptr_q;
    reg [PTR_W-1:0]   ack_ptr_q;
    reg [COUNT_W-1:0] in_flight_count_q;
    reg [COUNT_W-1:0] read_count_q;

    reg [PTR_W-1:0]   wr_ptr_d;
    reg [PTR_W-1:0]   rd_ptr_d;
    reg [PTR_W-1:0]   ack_ptr_d;
    reg [COUNT_W-1:0] in_flight_count_d;
    reg [COUNT_W-1:0] read_count_d;

    wire accept_input = valid_i && ready_o;
    wire accept_output = valid_o && ready_i && !nak_i;
    wire ack_do = ack_i && !nak_i && (in_flight_count_q != {COUNT_W{1'b0}});

    assign full_o = (in_flight_count_q == DEPTH_COUNT);
    assign ready_o = !full_o;
    assign valid_o = (read_count_q != {COUNT_W{1'b0}});
    assign data_o = mem[rd_ptr_q];
    assign in_flight_o = (in_flight_count_q != {COUNT_W{1'b0}});

    function [PTR_W-1:0] inc_ptr;
        input [PTR_W-1:0] ptr;
        begin
            if (ptr == LAST_PTR) begin
                inc_ptr = {PTR_W{1'b0}};
            end else begin
                inc_ptr = ptr + {{PTR_W-1{1'b0}}, 1'b1};
            end
        end
    endfunction

    always @* begin
        wr_ptr_d = wr_ptr_q;
        rd_ptr_d = rd_ptr_q;
        ack_ptr_d = ack_ptr_q;
        in_flight_count_d = in_flight_count_q;
        read_count_d = read_count_q;

        if (accept_input) begin
            wr_ptr_d = inc_ptr(wr_ptr_q);
            in_flight_count_d = in_flight_count_d + {{COUNT_W-1{1'b0}}, 1'b1};
        end

        if (ack_do) begin
            ack_ptr_d = inc_ptr(ack_ptr_q);
            in_flight_count_d = in_flight_count_d - {{COUNT_W-1{1'b0}}, 1'b1};
        end

        if (nak_i) begin
            rd_ptr_d = ack_ptr_q;
            read_count_d = in_flight_count_d;
        end else begin
            if (accept_output) begin
                rd_ptr_d = inc_ptr(rd_ptr_q);
                read_count_d = read_count_d - {{COUNT_W-1{1'b0}}, 1'b1};
            end
            if (accept_input) begin
                read_count_d = read_count_d + {{COUNT_W-1{1'b0}}, 1'b1};
            end
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            wr_ptr_q <= {PTR_W{1'b0}};
            rd_ptr_q <= {PTR_W{1'b0}};
            ack_ptr_q <= {PTR_W{1'b0}};
            in_flight_count_q <= {COUNT_W{1'b0}};
            read_count_q <= {COUNT_W{1'b0}};
        end else begin
            if (accept_input) begin
                mem[wr_ptr_q] <= data_i;
            end
            wr_ptr_q <= wr_ptr_d;
            rd_ptr_q <= rd_ptr_d;
            ack_ptr_q <= ack_ptr_d;
            in_flight_count_q <= in_flight_count_d;
            read_count_q <= read_count_d;
        end
    end
endmodule
