// Two-process FSM skeleton
// Reference: references/fsm-examples.md pattern 1 + pattern 4 (illegal-state recovery)
// States: IDLE, RUN, DONE
// Reset state: IDLE
// Default: IDLE (safe recovery from illegal state)

module simple_fsm (
    input  wire clk_i,
    input  wire rst_i,
    input  wire start_i,
    input  wire finish_i,
    output wire busy_o,
    output wire done_o
);

    localparam [1:0] IDLE = 2'd0,
                     RUN  = 2'd1,
                     DONE = 2'd2;

    reg [1:0] state_q;
    reg [1:0] state_d;

    // Combinational outputs: done_o pulses high in DONE state
    assign busy_o = (state_q == RUN);
    assign done_o = (state_q == DONE);

    // Process 1: state register
    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= IDLE;
        end else begin
            state_q <= state_d;
        end
    end

    // Process 2: next-state logic with defaults
    always @(*) begin
        state_d = state_q;

        case (state_q)
            IDLE: begin
                if (start_i)
                    state_d = RUN;
            end
            RUN: begin
                if (finish_i)
                    state_d = DONE;
            end
            DONE: begin
                state_d = IDLE;
            end
            default: begin
                state_d = IDLE;
            end
        endcase
    end

endmodule
