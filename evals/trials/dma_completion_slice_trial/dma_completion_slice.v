module dma_completion_slice #(
    parameter COUNT_W = 8
) (
    input  wire                 clk_i,
    input  wire                 rst_i,

    input  wire                 desc_valid_i,
    output wire                 desc_ready_o,
    input  wire [COUNT_W-1:0]   desc_resp_count_i,

    input  wire                 write_data_accept_i,
    input  wire                 write_data_last_i,

    input  wire                 bvalid_i,
    output wire                 bready_o,
    input  wire [1:0]           bresp_i,

    output reg                  done_valid_o,
    input  wire                 done_ready_i,
    output reg                  error_o,
    output wire                 busy_o,
    output wire [COUNT_W-1:0]   outstanding_resp_o
);

    localparam RESP_OKAY = 2'b00;

    reg active_q;
    reg data_done_q;
    reg [COUNT_W-1:0] outstanding_resp_q;
    reg error_q;

    wire accept_desc;
    wire accept_last_data;
    wire accept_b;
    wire accept_done;
    wire [COUNT_W-1:0] outstanding_after_b;
    wire data_done_after_edge;
    wire error_after_edge;
    wire complete_after_edge;

    assign desc_ready_o = (!active_q) && (!done_valid_o);
    assign bready_o = active_q && (outstanding_resp_q != {COUNT_W{1'b0}});
    assign busy_o = active_q;
    assign outstanding_resp_o = outstanding_resp_q;

    assign accept_desc = desc_valid_i && desc_ready_o;
    assign accept_last_data = active_q && write_data_accept_i && write_data_last_i;
    assign accept_b = bvalid_i && bready_o;
    assign accept_done = done_valid_o && done_ready_i;

    assign outstanding_after_b = outstanding_resp_q - {{(COUNT_W-1){1'b0}}, accept_b};
    assign data_done_after_edge = data_done_q || accept_last_data;
    assign error_after_edge = error_q || (accept_b && (bresp_i != RESP_OKAY));
    assign complete_after_edge = active_q &&
                                 data_done_after_edge &&
                                 (outstanding_after_b == {COUNT_W{1'b0}});

    always @(posedge clk_i) begin
        if (rst_i) begin
            active_q <= 1'b0;
            data_done_q <= 1'b0;
            outstanding_resp_q <= {COUNT_W{1'b0}};
            error_q <= 1'b0;
            done_valid_o <= 1'b0;
            error_o <= 1'b0;
        end else begin
            if (accept_done) begin
                done_valid_o <= 1'b0;
            end

            if (accept_desc) begin
                active_q <= 1'b1;
                data_done_q <= 1'b0;
                outstanding_resp_q <= desc_resp_count_i;
                error_q <= 1'b0;
            end else if (active_q) begin
                data_done_q <= data_done_after_edge;
                outstanding_resp_q <= outstanding_after_b;
                error_q <= error_after_edge;

                if (complete_after_edge) begin
                    active_q <= 1'b0;
                    done_valid_o <= 1'b1;
                    error_o <= error_after_edge;
                end
            end
        end
    end

endmodule
