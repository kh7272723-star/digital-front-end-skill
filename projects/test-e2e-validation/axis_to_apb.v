`default_nettype none

//============================================================================
// axis_to_apb — AXI-Stream to APB Write Bridge
//
// Receives 32-bit AXI-Stream beats and converts each to an APB write
// transaction at a configurable base address, with optional address
// increment per beat.
//
// Complexity: L1 (Leaf) — ~250 lines, nonlinear FSM, dual protocol
//============================================================================

module axis_to_apb #(
    parameter [15:0] APB_BASE_ADDR = 16'h1000,
    parameter         ADDR_INCR    = 1
) (
    input  wire         clk_i,
    input  wire         rst_ni,

    // AXI-Stream slave interface
    input  wire         s_axis_tvalid_i,
    input  wire [31:0]  s_axis_tdata_i,
    input  wire         s_axis_tlast_i,    // ignored per contract
    output reg          s_axis_tready_o,

    // APB master interface
    output wire         apb_psel_o,
    output wire         apb_penable_o,
    output wire [15:0]  apb_paddr_o,
    output wire         apb_pwrite_o,
    output wire [31:0]  apb_pwdata_o,
    input  wire [31:0]  apb_prdata_i,      // unused (write-only bridge)
    input  wire         apb_pready_i,
    input  wire         apb_pslverr_i,

    // Status
    output wire         busy_o,
    output wire         error_o
);

    //========================================================================
    // FSM state encoding
    //========================================================================
    localparam IDLE   = 2'b00;
    localparam SETUP  = 2'b01;
    localparam ACCESS = 2'b10;

    //========================================================================
    // Register declarations
    //========================================================================
    reg [1:0]  state_q;
    reg [1:0]  state_d;
    reg [31:0] pwdata_q;
    reg [15:0] paddr_q;
    reg        error_q;
    reg        error_d;

    // FSM single-bit control enables (per SM1 rule)
    reg load_data;
    reg incr_addr;

    //========================================================================
    // Process 1: FSM combinational — next-state + single-bit enables
    //========================================================================
    // PSEL/PENABLE are combinational from state_q (per APB guidelines:
    // "combinational from FSM state is acceptable if state transitions
    // are clean").  PADDR/PWDATA/PWRITE are registered outputs.
    //========================================================================
    always @(*) begin
        // Defaults
        state_d         = state_q;
        error_d         = 1'b0;
        s_axis_tready_o = 1'b0;
        load_data       = 1'b0;
        incr_addr       = 1'b0;

        case (state_q)
            //----------------------------------------------------------------
            // IDLE: Wait for AXI-Stream data
            //----------------------------------------------------------------
            IDLE: begin
                s_axis_tready_o = 1'b1;
                if (s_axis_tvalid_i) begin
                    load_data = 1'b1;
                    state_d   = SETUP;
                end
            end

            //----------------------------------------------------------------
            // SETUP: APB setup phase — PSEL high, PENABLE low
            // Always 1 cycle (no wait condition)
            //----------------------------------------------------------------
            SETUP: begin
                state_d = ACCESS;
            end

            //----------------------------------------------------------------
            // ACCESS: APB access phase — wait for PREADY
            //----------------------------------------------------------------
            ACCESS: begin
                if (apb_pready_i) begin
                    // Transaction complete
                    error_d   = apb_pslverr_i;
                    incr_addr = 1'b1;   // advance address for next beat
                    state_d   = IDLE;
                end
                // else: waiting for PREADY — hold all APB signals stable
            end

            //----------------------------------------------------------------
            // Default: recover from illegal state
            //----------------------------------------------------------------
            default: begin
                state_d = IDLE;
            end
        endcase
    end

    //========================================================================
    // Process 2: Synchronous — state register + registered outputs
    //========================================================================
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q   <= IDLE;
            pwdata_q  <= 32'd0;
            paddr_q   <= APB_BASE_ADDR;
            error_q   <= 1'b0;
        end else begin
            state_q   <= state_d;
            error_q   <= error_d;

            // Multi-bit register updates gated by single-bit enables
            if (load_data) pwdata_q <= s_axis_tdata_i;
            if (incr_addr) paddr_q  <= paddr_q + (ADDR_INCR << 2);
        end
    end

    //========================================================================
    // Output assignments
    //========================================================================
    // PSEL/PENABLE are combinational from state_q (clean transitions,
    // no glitch risk for 3-state FSM with one-hot-like encoding).
    assign apb_psel_o    = (state_q == SETUP) || (state_q == ACCESS);
    assign apb_penable_o = (state_q == ACCESS);
    assign apb_paddr_o   = paddr_q;
    assign apb_pwdata_o  = pwdata_q;
    assign apb_pwrite_o  = 1'b1;            // write-only bridge
    assign busy_o        = (state_q != IDLE);
    assign error_o       = error_q;          // 1-cycle pulse on PSLVERR

endmodule

`default_nettype wire
