`default_nettype none

//==============================================================================
// psm — Power State Machine
//
// Purpose:
//   Controls power domain state transitions for a low-power SoC. Validates
//   LP1 (isolation before power-off), LP2 (retention save/restore handshake),
//   LP3 (no illegal state transitions), and LP5 (DVFS gating).
//
// FSM States (7 states, binary encoding):
//   S_ON          — normal operation, isolation OFF
//   S_ISOLATING   — assert isolation, wait settling (LP1)
//   S_SAVE_RETAIN — pulse retain_save, wait for save (LP2)
//   S_POWER_OFF   — power_switch OFF, wait for power-down
//   S_SLEEP       — wait for wake_req_i
//   S_WAKING      — power_switch ON, wait for stable
//   S_RESTORE     — pulse retain_restore, then de-isolate (LP2)
//
// State transition sequence (LP3 — no skipping allowed):
//   ON → ISOLATING → SAVE → OFF → SLEEP → WAKING → RESTORE → ON
//
// Key timing:
//   isolation_en_o:   asserted in S_ISOLATING through S_RESTORE (LP1)
//   power_switch_o:   registered, OFF only in S_POWER_OFF and S_SLEEP
//   retain_save_o:    1-cycle pulse on entry to S_SAVE_RETAIN (LP2)
//   retain_restore_o: 1-cycle pulse on entry to S_RESTORE (LP2)
//   sleep_req_i:      gated by dvfs_busy_i (LP5 check)
//   Wait counters:    per-state configurable thresholds prevent premature
//                     state transitions
//
// Bug patterns validated:
//   LP1 — isolation_en asserted in S_ISOLATING (BEFORE S_POWER_OFF)
//   LP2 — retain_save pulses before power-off; retain_restore after
//         power-on and before de-isolation
//   LP3 — no illegal state jumps (explicit sequential transitions only)
//   LP5 — dvfs_busy_i blocks sleep_req acceptance
//   SM1 — FSM combinational assigns only state_d + single-bit enables
//   SM2 — no shadow datapath combinational block
//   C2  — default case recovers illegal states to S_ON
//   C3  — default assignments prevent latch inference
//==============================================================================

module psm (
    // Clock and reset
    input  wire       clk_i,
    input  wire       rst_i,

    // APB CSR interface (from apb_regs)
    input  wire       sleep_req_i,         // PMU sleep request
    input  wire       wake_req_i,          // PMU wake request

    // DVFS gating (from dvfs_ctrl busy_o, LP5)
    input  wire       dvfs_busy_i,         // block sleep during DVFS

    // Domain control outputs (to switchable modules)
    output wire       isolation_en_o,      // assert BEFORE power-off (LP1)
    output reg        power_switch_o,      // 1=on, 0=off (registered)
    output reg        retain_save_o,       // pulse: save retention state (LP2)
    output reg        retain_restore_o,    // pulse: restore retention (LP2)
    output reg        domain_clk_en_o,     // clock enable (same timing as power)

    // Status (to apb_regs)
    output wire [2:0] power_state_o,       // current PSM state (RO)
    output reg        sleep_ack_o,         // pulsed on sleep entry
    output reg        wake_ack_o           // pulsed on wake completion
);

    //----------------------------------------------------------------------
    // FSM state encoding (binary, 7 states)
    //----------------------------------------------------------------------
    localparam S_ON          = 3'b001;
    localparam S_ISOLATING   = 3'b010;
    localparam S_SAVE_RETAIN = 3'b011;
    localparam S_POWER_OFF   = 3'b100;
    localparam S_SLEEP       = 3'b101;
    localparam S_WAKING      = 3'b110;
    localparam S_RESTORE     = 3'b111;

    //----------------------------------------------------------------------
    // Wait counter thresholds (configurable parameters)
    // The state persists for at least WAIT_* + 1 cycles (entry + WAIT_*
    // incrementing cycles) before the next transition is allowed.
    //----------------------------------------------------------------------
    parameter WAIT_ISOLATE = 4'd3;
    parameter WAIT_SAVE    = 4'd3;
    parameter WAIT_POWER   = 4'd5;
    parameter WAIT_WAKE    = 4'd5;
    parameter WAIT_RESTORE = 4'd3;

    //----------------------------------------------------------------------
    // State registers
    //----------------------------------------------------------------------
    reg [2:0] state_q;
    reg [2:0] state_d;
    reg [2:0] prev_state_q;  // previous state for transition detection

    //----------------------------------------------------------------------
    // Wait counter (4-bit, saturates at WAIT_*+1 before transition)
    //----------------------------------------------------------------------
    reg [3:0] wait_cnt_q;

    //----------------------------------------------------------------------
    // FSM single-bit enables (output by combinational block, consumed by
    // synchronous datapath blocks — single-bit control rule)
    //----------------------------------------------------------------------
    reg incr_wait;        // increment wait counter
    reg clr_wait;         // clear wait counter
    reg power_off_set;    // set power_switch_o low (enter S_POWER_OFF)
    reg power_on_set;     // set power_switch_o high (enter S_WAKING)

    //----------------------------------------------------------------------
    // Process 1: State register + wait counter + registered outputs
    //----------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q         <= S_ON;
            prev_state_q    <= S_ON;
            wait_cnt_q      <= 4'd0;
            power_switch_o  <= 1'b1;
            domain_clk_en_o <= 1'b1;
            retain_save_o   <= 1'b0;
            retain_restore_o <= 1'b0;
            sleep_ack_o     <= 1'b0;
            wake_ack_o      <= 1'b0;
        end else begin
            // State register + previous state tracking
            state_q      <= state_d;
            prev_state_q <= state_q;

            // Wait counter: clr_wait has priority over incr_wait
            if (clr_wait) begin
                wait_cnt_q <= 4'd0;
            end else if (incr_wait) begin
                wait_cnt_q <= wait_cnt_q + 4'd1;
            end

            // power_switch_o (registered, glitch-free output)
            if (power_off_set) begin
                power_switch_o  <= 1'b0;
                domain_clk_en_o <= 1'b0;
            end else if (power_on_set) begin
                power_switch_o  <= 1'b1;
                domain_clk_en_o <= 1'b1;
            end

            // retain_save_o: 1-cycle pulse on entry to S_SAVE_RETAIN
            if (state_q == S_SAVE_RETAIN && wait_cnt_q == 4'd0) begin
                retain_save_o <= 1'b1;
            end else begin
                retain_save_o <= 1'b0;
            end

            // retain_restore_o: 1-cycle pulse on entry to S_RESTORE
            if (state_q == S_RESTORE && wait_cnt_q == 4'd0) begin
                retain_restore_o <= 1'b1;
            end else begin
                retain_restore_o <= 1'b0;
            end

            // sleep_ack_o: 1-cycle pulse on transition PWR_OFF → SLEEP (LP7)
            if (prev_state_q == S_POWER_OFF && state_q == S_SLEEP) begin
                sleep_ack_o <= 1'b1;
            end else begin
                sleep_ack_o <= 1'b0;
            end

            // wake_ack_o: 1-cycle pulse on transition RESTORE → ON (LP7)
            if (prev_state_q == S_RESTORE && state_q == S_ON) begin
                wake_ack_o <= 1'b1;
            end else begin
                wake_ack_o <= 1'b0;
            end
        end
    end

    //----------------------------------------------------------------------
    // Process 2: FSM next-state + single-bit enables (combinational)
    //
    // All outputs have default assignments before the case statement to
    // prevent latch inference (C3). state_d defaults to state_q (stay in
    // current state). Default case recovers illegal states to S_ON (C2).
    //----------------------------------------------------------------------
    always @(*) begin
        state_d       = state_q;
        incr_wait     = 1'b0;
        clr_wait      = 1'b0;
        power_off_set = 1'b0;
        power_on_set  = 1'b0;

        case (state_q)
            //--------------------------------------------------------------
            // S_ON: Normal operation, accept sleep request (gated by DVFS)
            //--------------------------------------------------------------
            S_ON: begin
                // LP5: sleep_req_i is gated by dvfs_busy_i. If DVFS is in
                // progress, the sleep request is ignored.
                if (sleep_req_i && !dvfs_busy_i) begin
                    state_d  = S_ISOLATING;
                    clr_wait = 1'b1;
                end
            end

            //--------------------------------------------------------------
            // S_ISOLATING: Assert isolation, wait for settling (LP1)
            // isolation_en_o is combinational from state_q, so it goes high
            // immediately on cycle 1 of this state — BEFORE power_switch_o
            // goes low in S_POWER_OFF.
            //--------------------------------------------------------------
            S_ISOLATING: begin
                incr_wait = 1'b1;
                if (wait_cnt_q >= WAIT_ISOLATE) begin
                    state_d  = S_SAVE_RETAIN;
                    clr_wait = 1'b1;
                end
            end

            //--------------------------------------------------------------
            // S_SAVE_RETAIN: Pulse retain_save, wait for save (LP2)
            // retain_save_o pulses on entry (registered in Process 1).
            // Save completes BEFORE transitioning to S_POWER_OFF.
            //--------------------------------------------------------------
            S_SAVE_RETAIN: begin
                incr_wait = 1'b1;
                if (wait_cnt_q >= WAIT_SAVE) begin
                    state_d       = S_POWER_OFF;
                    power_off_set = 1'b1;
                    clr_wait      = 1'b1;
                end
            end

            //--------------------------------------------------------------
            // S_POWER_OFF: Power domain is OFF, wait for power-down
            // power_switch_o goes low on power_off_set (registered).
            // domain_clk_en_o also goes low (clock gated).
            //--------------------------------------------------------------
            S_POWER_OFF: begin
                incr_wait = 1'b1;
                if (wait_cnt_q >= WAIT_POWER) begin
                    state_d  = S_SLEEP;
                    clr_wait = 1'b1;
                end
            end

            //--------------------------------------------------------------
            // S_SLEEP: Waiting for wake_req_i
            //--------------------------------------------------------------
            S_SLEEP: begin
                if (wake_req_i) begin
                    state_d      = S_WAKING;
                    power_on_set = 1'b1;
                    clr_wait     = 1'b1;
                end
            end

            //--------------------------------------------------------------
            // S_WAKING: Power restored, wait for stability
            // power_switch_o goes high on power_on_set (registered).
            // domain_clk_en_o goes high. isolation_en_o is still active.
            //--------------------------------------------------------------
            S_WAKING: begin
                incr_wait = 1'b1;
                if (wait_cnt_q >= WAIT_WAKE) begin
                    state_d  = S_RESTORE;
                    clr_wait = 1'b1;
                end
            end

            //--------------------------------------------------------------
            // S_RESTORE: Pulse retain_restore, then de-isolate (LP2)
            // retain_restore_o pulses on entry (registered in Process 1).
            // Restore happens AFTER power-on (S_WAKING) and BEFORE
            // de-isolation (return to S_ON).
            //--------------------------------------------------------------
            S_RESTORE: begin
                incr_wait = 1'b1;
                if (wait_cnt_q >= WAIT_RESTORE) begin
                    state_d  = S_ON;
                    clr_wait = 1'b1;
                end
            end

            //--------------------------------------------------------------
            // Default: recover illegal state to S_ON (C2), clear counter
            //--------------------------------------------------------------
            default: begin
                state_d  = S_ON;
                clr_wait = 1'b1;
            end
        endcase
    end

    //----------------------------------------------------------------------
    // Combinational output assignments (no latches — all branches covered)
    //----------------------------------------------------------------------

    // LP1: isolation_en asserted from S_ISOLATING through S_RESTORE
    // Deasserted only in S_ON (after restore completes).
    // This means isolation is active for 6 states BEFORE power_switch goes
    // low (asserts in S_ISOLATING, 2 states before S_POWER_OFF) and remains
    // active AFTER power comes back (through S_WAKING and S_RESTORE).
    assign isolation_en_o = (state_q != S_ON);

    // power_state_o: always reflects current FSM state for status readback
    assign power_state_o  = state_q;

endmodule

`default_nettype wire
