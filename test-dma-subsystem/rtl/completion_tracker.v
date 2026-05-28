`default_nettype none

// DMA completion tracker: tracks WLAST + BRESP for completion.
// Done = last W beat accepted AND all B responses received.
module completion_tracker #(
    parameter COUNT_W = 16
)(
    input  wire               clk_i,
    input  wire               rst_i,
    // From burst planner
    input  wire               desc_valid_i,
    input  wire [COUNT_W-1:0] b_count_i,
    // From wr_data_channel
    input  wire               wlast_accepted_i,
    // From AXI B channel
    input  wire               bvalid_i,
    output wire               bready_o,
    input  wire [1:0]         bresp_i,
    // Completion
    output reg                done_valid_o,
    input  wire               done_ready_i,
    output reg                error_o,
    output reg                busy_o
);

    reg               active_q;
    reg [COUNT_W-1:0] outstanding_q;
    reg               data_done_q;
    reg               error_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            active_q       <= 1'b0;
            outstanding_q  <= {COUNT_W{1'b0}};
            data_done_q    <= 1'b0;
            error_q        <= 1'b0;
            done_valid_o   <= 1'b0;
            error_o        <= 1'b0;
        end else begin
            done_valid_o <= 1'b0;

            if (desc_valid_i) begin
                active_q       <= 1'b1;
                outstanding_q  <= b_count_i;
                data_done_q    <= 1'b0;
                error_q        <= 1'b0;
            end

            if (wlast_accepted_i && active_q)
                data_done_q <= 1'b1;

            if (bvalid_i && bready_o) begin
                if (bresp_i != 2'b00) error_q <= 1'b1;
                if (outstanding_q != 0)
                    outstanding_q <= outstanding_q - 1;
            end

            // Completion: data done AND all B responses received
            if (active_q && data_done_q && outstanding_q == 0 &&
                !(bvalid_i && bready_o)) begin
                done_valid_o <= 1'b1;
                error_o      <= error_q;
                active_q     <= 1'b0;
            end
        end
    end

    assign bready_o = active_q && (outstanding_q != 0) && !done_valid_o;
    assign busy_o   = active_q;

endmodule
`default_nettype wire
