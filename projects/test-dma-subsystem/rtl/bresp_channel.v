`default_nettype none

// bresp_channel: AXI B response with completion tracking
module bresp_channel #(parameter COUNT_W = 16) (
    input  wire               clk_i,
    input  wire               rst_i,
    // AXI B channel
    input  wire               bvalid_i,
    output wire               bready_o,
    input  wire [1:0]         bresp_i,
    // From planner
    input  wire               desc_valid_i,
    input  wire [COUNT_W-1:0] b_count_i,
    // Completion
    output reg                done_valid_o,
    input  wire               done_ready_i,
    output reg                error_o,
    output reg                busy_o
);

    // ---------------------------------------------------------------
    // State
    // ---------------------------------------------------------------
    reg                active_q, active_d;
    reg [COUNT_W-1:0]  outstanding_q, outstanding_d;
    reg                error_q, error_d;
    reg                done_valid_q, done_valid_d;

    // ---------------------------------------------------------------
    // Sequential
    // ---------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            active_q      <= 1'b0;
            outstanding_q <= {COUNT_W{1'b0}};
            error_q       <= 1'b0;
            done_valid_q  <= 1'b0;
        end else begin
            active_q      <= active_d;
            outstanding_q <= outstanding_d;
            error_q       <= error_d;
            done_valid_q  <= done_valid_d;
        end
    end

    // ---------------------------------------------------------------
    // Combinational: next-state
    // ---------------------------------------------------------------
    wire b_accepted = bvalid_i && bready_o;

    always @(*) begin
        // Defaults
        active_d      = active_q;
        outstanding_d = outstanding_q;
        error_d       = error_q;
        done_valid_d  = 1'b0;  // single-cycle pulse default off

        // New descriptor takes priority
        if (desc_valid_i) begin
            active_d      = 1'b1;
            outstanding_d = b_count_i;
            error_d       = 1'b0;
            done_valid_d  = 1'b0;
        end else if (active_q) begin
            // Accept B responses
            if (b_accepted && outstanding_q != 0) begin
                outstanding_d = outstanding_q - 1'b1;
                if (bresp_i != 2'b00) begin
                    error_d = 1'b1;
                end
                // Check if this was the last one
                if (outstanding_q == {{(COUNT_W-1){1'b0}}, 1'b1}) begin
                    done_valid_d = 1'b1;
                    active_d     = 1'b0;
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // Output assignments
    // ---------------------------------------------------------------
    // bready: accept B when active, outstanding > 0, and not signaling done
    assign bready_o = active_q && (outstanding_q != {COUNT_W{1'b0}}) && !done_valid_q;

    always @(*) begin
        done_valid_o = done_valid_q;
        error_o      = error_q;
        busy_o       = active_q;
    end

endmodule

`default_nettype wire
