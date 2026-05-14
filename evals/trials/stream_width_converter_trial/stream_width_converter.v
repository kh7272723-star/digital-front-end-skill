module stream_width_converter (
    input  wire          clk_i,
    input  wire          rst_i,
    input  wire          valid_i,
    output wire          ready_o,
    input  wire [31:0]   data_i,
    input  wire [3:0]    keep_i,
    input  wire          last_i,
    output wire          valid_o,
    input  wire          ready_i,
    output wire [127:0]  data_o,
    output wire [15:0]   keep_o,
    output wire          last_o
);
    reg [127:0] data_q;
    reg [15:0]  keep_q;
    reg [1:0]   lane_count_q;
    reg         valid_q;
    reg         last_q;

    reg [127:0] data_d;
    reg [15:0]  keep_d;
    reg [1:0]   lane_count_d;
    reg         valid_d;
    reg         last_d;

    wire accept_input = valid_i && ready_o;
    wire accept_output = valid_o && ready_i;
    wire output_complete = (lane_count_q == 2'd3) || last_i;

    assign ready_o = !valid_q || ready_i;
    assign valid_o = valid_q;
    assign data_o = data_q;
    assign keep_o = keep_q;
    assign last_o = last_q;

    always @* begin
        data_d = data_q;
        keep_d = keep_q;
        lane_count_d = lane_count_q;
        valid_d = valid_q;
        last_d = last_q;

        if (accept_output) begin
            valid_d = 1'b0;
            last_d = 1'b0;
        end

        if (accept_input) begin
            if (lane_count_q == 2'd0) begin
                data_d = 128'h0;
                keep_d = 16'h0000;
            end

            case (lane_count_q)
                2'd0: begin
                    data_d[31:0] = data_i;
                    keep_d[3:0] = keep_i;
                end
                2'd1: begin
                    data_d[63:32] = data_i;
                    keep_d[7:4] = keep_i;
                end
                2'd2: begin
                    data_d[95:64] = data_i;
                    keep_d[11:8] = keep_i;
                end
                default: begin
                    data_d[127:96] = data_i;
                    keep_d[15:12] = keep_i;
                end
            endcase

            if (output_complete) begin
                valid_d = 1'b1;
                last_d = last_i;
                lane_count_d = 2'd0;
            end else begin
                lane_count_d = lane_count_q + 2'd1;
            end
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            data_q <= 128'h0;
            keep_q <= 16'h0000;
            lane_count_q <= 2'd0;
            valid_q <= 1'b0;
            last_q <= 1'b0;
        end else begin
            data_q <= data_d;
            keep_q <= keep_d;
            lane_count_q <= lane_count_d;
            valid_q <= valid_d;
            last_q <= last_d;
        end
    end
endmodule
