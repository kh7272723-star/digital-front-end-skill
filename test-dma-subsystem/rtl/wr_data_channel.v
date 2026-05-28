`default_nettype none

// wr_data_channel: FIFO read port -> AXI W channel (two-state FSM)
module wr_data_channel #(parameter DATA_W = 32) (
    input  wire               clk_i,
    input  wire               rst_i,
    // FIFO read port
    output reg                fifo_rd_en_o,
    input  wire [DATA_W:0]    fifo_rd_data_i,  // {data, last}
    input  wire               fifo_empty_i,
    // AXI W channel
    output reg                wvalid_o,
    input  wire               wready_i,
    output reg  [DATA_W-1:0]  wdata_o,
    output reg                wlast_o,
    output reg  [DATA_W/8-1:0] wstrb_o,
    // Status
    output reg                wlast_accepted_o
);

    // ---------------------------------------------------------------
    // State encoding
    // ---------------------------------------------------------------
    localparam S_IDLE = 1'b0;
    localparam S_SEND = 1'b1;

    reg state_q, state_d;
    reg [DATA_W-1:0] wdata_q, wdata_d;
    reg              wlast_q, wlast_d;

    // ---------------------------------------------------------------
    // Sequential
    // ---------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= S_IDLE;
            wdata_q <= {DATA_W{1'b0}};
            wlast_q <= 1'b0;
        end else begin
            state_q <= state_d;
            wdata_q <= wdata_d;
            wlast_q <= wlast_d;
        end
    end

    // ---------------------------------------------------------------
    // Combinational: next-state + outputs
    // ---------------------------------------------------------------
    always @(*) begin
        // Defaults
        state_d        = state_q;
        wdata_d        = wdata_q;
        wlast_d        = wlast_q;
        fifo_rd_en_o   = 1'b0;
        wvalid_o       = 1'b0;
        wdata_o        = wdata_q;
        wlast_o        = wlast_q;
        wstrb_o        = {DATA_W/8{1'b1}};
        wlast_accepted_o = 1'b0;

        case (state_q)
            // -------------------------------------------------
            S_IDLE: begin
                // Read FWFT output combinationally (no pop).
                // This ensures we read data from a PREVIOUS cycle, not the
                // same cycle the read channel writes — avoiding stale reads.
                if (!fifo_empty_i) begin
                    wdata_d = fifo_rd_data_i[DATA_W:1];
                    wlast_d = fifo_rd_data_i[0];
                    state_d = S_SEND;
                end
            end

            // -------------------------------------------------
            S_SEND: begin
                // Assert WVALID with latched data.
                // WVALID holds until WREADY (AXI protocol).
                wvalid_o = 1'b1;
                wdata_o  = wdata_q;
                wlast_o  = wlast_q;

                if (wready_i) begin
                    // Pop the FIFO (data was consumed by slave)
                    fifo_rd_en_o = 1'b1;
                    if (wlast_q) begin
                        // Last beat accepted: back to IDLE
                        wlast_accepted_o = 1'b1;
                        wvalid_o         = 1'b0;
                        state_d          = S_IDLE;
                    end else begin
                        // Not last: latch next word from FIFO
                        if (!fifo_empty_i) begin
                            wdata_d = fifo_rd_data_i[DATA_W:1];
                            wlast_d = fifo_rd_data_i[0];
                        end
                        // If FIFO empty: hold WVALID with current data
                    end
                end
            end

            default: state_d = S_IDLE;
        endcase
    end

endmodule

`default_nettype wire
