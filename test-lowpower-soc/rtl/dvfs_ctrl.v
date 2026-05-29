`default_nettype none

//==============================================================================
// dvfs_ctrl — DVFS Controller
//
// Purpose:
//   Controls dynamic voltage and frequency switching for a low-power SoC.
//   Validates LP5 (no frequency switch during active bus transfer) and LP6
//   (operand isolation for wide combinational logic >32-bit).
//
// FSM States (4 states):
//   S_IDLE       — ready for freq_req_i
//   S_CHECK_IDLE — verify bus_idle_i==1 before proceeding (LP5)
//   S_REQUEST    — assert pmu_valid_o with target frequency (LP6: isolate)
//   S_WAIT       — wait for pmu_done_i (LP6: maintain isolate)
//
// Protocol: request→check→commit→wait→done (atomic)
//
// Key timing:
//   busy_o:         freq_req_i acceptance → pmu_done_i
//   current_freq_o: updated ONLY after pmu_done_i (not during transition)
//   isolate_en_o:   asserted during S_REQUEST+S_WAIT, deasserted in S_IDLE
//   pmu_valid_o:    level, asserted from S_REQUEST through S_WAIT
//
// Bug patterns validated:
//   LP5 — bus_idle_i check gates transition to S_REQUEST
//   LP6 — registered operand isolation covers full DVFS window
//==============================================================================

module dvfs_ctrl (
    // Clock and reset
    input  wire       clk_i,
    input  wire       rst_i,

    // APB CSR interface (from apb_regs)
    input  wire       freq_req_i,         // frequency switch request
    input  wire [3:0] freq_idx_i,         // target frequency table index

    // Bus idle status (from clk_gate_ctrl)
    input  wire       bus_idle_i,         // bus is idle (LP5 check)

    // Operand isolation control (to phys_aware_datapath, LP6)
    output reg        isolate_en_o,       // isolate >32b combinational inputs

    // PMU handshake
    output reg        pmu_valid_o,        // frequency change command valid
    output wire [3:0] pmu_freq_o,         // target frequency
    input  wire       pmu_done_i,         // PMU acknowledges frequency change

    // Status
    output reg  [3:0] current_freq_o,     // current operating frequency index
    output reg        busy_o              // DVFS in progress (gates PSM sleep)
);

    //----------------------------------------------------------------------
    // FSM state encoding
    //----------------------------------------------------------------------
    localparam S_IDLE       = 2'b00;
    localparam S_CHECK_IDLE = 2'b01;
    localparam S_REQUEST    = 2'b10;
    localparam S_WAIT       = 2'b11;

    //----------------------------------------------------------------------
    // State registers
    //----------------------------------------------------------------------
    reg [1:0] state_q;
    reg [1:0] state_d;

    //----------------------------------------------------------------------
    // Datapath registers
    //----------------------------------------------------------------------
    reg [3:0] freq_idx_q;   // latched target frequency index

    //----------------------------------------------------------------------
    // FSM single-bit enables (output by combinational block, consumed by
    // synchronous datapath blocks — single-bit control rule)
    //----------------------------------------------------------------------
    reg latch_freq_en;       // latch freq_idx_i on request acceptance
    reg update_freq_en;      // update current_freq after pmu_done_i
    reg start_pmu;           // start PMU transaction (assert V + isolate)
    reg abort_dvfs;          // abort DVFS on freq_req deassert in CHECK_IDLE

    //----------------------------------------------------------------------
    // Process 1: State register (sequential)
    //----------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= S_IDLE;
        end else begin
            state_q <= state_d;
        end
    end

    //----------------------------------------------------------------------
    // Process 2: FSM next-state + single-bit enables (combinational)
    //----------------------------------------------------------------------
    always @(*) begin
        state_d        = state_q;
        latch_freq_en  = 1'b0;
        update_freq_en = 1'b0;
        start_pmu      = 1'b0;
        abort_dvfs     = 1'b0;

        case (state_q)
            S_IDLE: begin
                // Wait for frequency switch request
                if (freq_req_i) begin
                    latch_freq_en = 1'b1;
                    state_d       = S_CHECK_IDLE;
                end
            end

            S_CHECK_IDLE: begin
                // LP5: MUST check bus_idle_i before proceeding
                // SM3: abort if freq_req deasserted mid-sequence
                if (!freq_req_i) begin
                    abort_dvfs = 1'b1;   // clear busy, return to IDLE
                    state_d    = S_IDLE;
                end else if (bus_idle_i) begin
                    start_pmu = 1'b1;   // triggers isolate_en + pmu_valid
                    state_d   = S_REQUEST;
                end
                // else: remain in S_CHECK_IDLE until bus idle or abort
            end

            S_REQUEST: begin
                // 1-cycle state: pmu_valid_o already asserted by start_pmu
                state_d = S_WAIT;
            end

            S_WAIT: begin
                // Wait for PMU to complete frequency change
                if (pmu_done_i) begin
                    update_freq_en = 1'b1;  // update status, deassert isolate
                    state_d        = S_IDLE;
                end
            end

            default: begin
                state_d = S_IDLE;
            end
        endcase
    end

    //----------------------------------------------------------------------
    // Process 3: freq_idx_q — latched on freq_req acceptance
    //----------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            freq_idx_q <= 4'b0;
        end else if (latch_freq_en) begin
            freq_idx_q <= freq_idx_i;
        end
    end

    //----------------------------------------------------------------------
    // Process 4: isolate_en_o — registered output (LP6, glitch-free)
    //            Asserted during S_REQUEST+S_WAIT (full DVFS window)
    //            Deasserted on transition back to S_IDLE
    //----------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            isolate_en_o <= 1'b0;
        end else if (start_pmu) begin
            isolate_en_o <= 1'b1;
        end else if (update_freq_en) begin
            isolate_en_o <= 1'b0;
        end
    end

    //----------------------------------------------------------------------
    // Process 5: pmu_valid_o — level signal, asserted during DVFS
    //            Asserted on start_pmu, deasserted on pmu_done
    //----------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            pmu_valid_o <= 1'b0;
        end else if (start_pmu) begin
            pmu_valid_o <= 1'b1;
        end else if (update_freq_en) begin
            pmu_valid_o <= 1'b0;
        end
    end

    //----------------------------------------------------------------------
    // Process 6: busy_o — from freq_req_i acceptance to pmu_done_i
    //            Gates PSM sleep via dvfs_busy_i connection (LP5)
    //----------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            busy_o <= 1'b0;
        end else if (latch_freq_en) begin
            busy_o <= 1'b1;
        end else if (update_freq_en || abort_dvfs) begin
            busy_o <= 1'b0;
        end
    end

    //----------------------------------------------------------------------
    // Process 7: current_freq_o — updated ONLY after pmu_done_i
    //            Not changed during transition (correctness invariant)
    //----------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            current_freq_o <= 4'b0;
        end else if (update_freq_en) begin
            current_freq_o <= freq_idx_q;
        end
    end

    //----------------------------------------------------------------------
    // Combinational outputs
    //----------------------------------------------------------------------
    // pmu_freq_o: combinational from latched target — PMU samples on valid
    assign pmu_freq_o = freq_idx_q;

endmodule

`default_nettype wire
