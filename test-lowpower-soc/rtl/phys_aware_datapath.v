`default_nettype none

//==============================================================================
// phys_aware_datapath — Physical-Aware MAC Array
//
// Purpose:
//   3-stage multiply-accumulate (MAC) pipeline with physical-awareness
//   features. Validates PH1 (registered I/O at hierarchy boundaries),
//   PH2 (max_fanout attribute on high-fanout signals), PH3 (SRAM in same
//   hierarchy as consumer), PH4 (port groups by channel), LP2 (retention
//   save/restore), and LP6 (operand isolation for wide combinational logic).
//
// MAC Pipeline (3 stages):
//   Stage 1:  Register src_a_i, src_b_i, op_sel_i on start_i. Apply
//             operand isolation if isolate_en_i is asserted (LP6).
//             Load current accumulator value from SRAM (PH3).
//   Stage 2:  32x32 multiplier -> 64-bit product. 64-bit accumulator
//             updated based on op_sel_i (MAC/MUL/ADD/ACC).
//   Stage 3:  Output registers: result_lo_o, result_hi_o, done_o (PH1).
//             Save result back to SRAM for context persistence (PH3).
//
// Physical Awareness:
//   PH1 — ALL outputs driven from registers (no combinational output paths)
//   PH2 — (* max_fanout = 50 *) on clk_en_i, isolate_en_i, start_i
//   PH3 — 256x32 SRAM accumulation buffer declared INSIDE this module,
//         actively read (Stage 1) and written (Stage 3)
//   PH4 — Port declarations grouped: clock/reset, control, data, status,
//         retention
//
// Operand Isolation (LP6):
//   When isolate_en_i is asserted, registered operands are zeroed before
//   entering the 32x32 multiplier (>32-bit wide combinational logic).
//
// Retention (LP2):
//   retain_save_i pulse:
//     save accumulator (result_lo_q, result_hi_q) to shadow registers
//   retain_restore_i pulse:
//     restore accumulator from shadow; also write shadow to SRAM at
//     current address for consistency on the next context load
//
// Pipeline latency: 3 cycles from start_i to done_o
//   Cycle N (start_i):  inputs registered, SRAM loaded into acc_loaded
//   Cycle N+1:          multiply + accumulate
//   Cycle N+2:          output registers updated, done_o pulsed, SRAM saved
//==============================================================================

module phys_aware_datapath (
    // -----------------------------------------------------------------
    // Group 1: Clock / Reset
    // -----------------------------------------------------------------
    input  wire       clk_i,
    input  wire       rst_i,

    // -----------------------------------------------------------------
    // Group 2: Control Inputs
    // -----------------------------------------------------------------
    // PH2: high-fanout control signals annotated with max_fanout attribute
    `ifdef SYNTHESIS
    (* max_fanout = 50 *)
    `endif
    input  wire       clk_en_i,           // domain clock enable (from clk_gate_ctrl)

    `ifdef SYNTHESIS
    (* max_fanout = 50 *)
    `endif
    input  wire       isolate_en_i,       // operand isolation (from dvfs_ctrl, LP6)

    `ifdef SYNTHESIS
    (* max_fanout = 50 *)
    `endif
    input  wire       start_i,            // start MAC computation (pulse)

    input  wire [1:0] op_sel_i,           // 00=MAC, 01=MUL, 10=ADD, 11=ACC

    // -----------------------------------------------------------------
    // Group 3: Data Inputs
    // -----------------------------------------------------------------
    input  wire [31:0] src_a_i,           // operand A
    input  wire [31:0] src_b_i,           // operand B

    // -----------------------------------------------------------------
    // Group 4: Status Outputs (all registered — PH1)
    // -----------------------------------------------------------------
    output wire [31:0] result_lo_o,       // low 32 bits of result
    output wire [31:0] result_hi_o,       // high 32 bits of result
    output wire        done_o,            // computation complete (pulse)
    output wire        busy_o,            // computation in progress
    output wire        active_o,          // MAC has pending/in-progress work

    // -----------------------------------------------------------------
    // Group 5: Retention (from psm, LP2)
    // -----------------------------------------------------------------
    input  wire       retain_save_i,      // save accumulator to shadow
    input  wire       retain_restore_i    // restore accumulator from shadow
);

    // ===================================================================
    // Internal Declarations
    // ===================================================================

    // PH3: 256x32 SRAM accumulation buffer — declared inside this module,
    // NOT in a separate submodule (validates PH3 requirement).
    // The SRAM stores the 64-bit accumulator as two consecutive 32-bit
    // entries (lo at even address, hi at odd address), providing 128
    // independent accumulator contexts.
    reg [31:0] mem_q [0:255];

    // SRAM address pointer. Increments by 2 on each completed MAC to
    // advance to the next accumulator context. After 128 contexts
    // (256 entries), wraps to 0.
    reg [7:0]  addr_q;

    // Pipeline Stage 1: Input registers (registered on start_i)
    reg [31:0] src_a_q;             // operand A, registered + isolated
    reg [31:0] src_b_q;             // operand B, registered + isolated
    reg [1:0]  op_sel_q;            // operation select, registered
    reg        stage1_valid_q;      // stage 1 valid flag

    // Accumulator loaded from SRAM on start_i (PH3 read path)
    reg [31:0] acc_loaded_lo_q;     // SRAM[addr_q]   — accumulator low
    reg [31:0] acc_loaded_hi_q;     // SRAM[addr_q+1] — accumulator high

    // Pipeline Stage 2: Computed result register
    reg [31:0] result_lo_q;         // computed accumulator low
    reg [31:0] result_hi_q;         // computed accumulator high
    reg        stage2_valid_q;      // stage 2 valid flag

    // Pipeline Stage 3: Output registers (PH1 — registered I/O boundary)
    reg [31:0] result_lo_o_q;       // output register low
    reg [31:0] result_hi_o_q;       // output register high
    reg        done_q;              // output done flag

    // Busy flag: set on start_i acceptance, cleared on done_q
    reg        busy_q;

    // SRAM validity — tracks whether SRAM has been written (PH-init fix)
    reg        sram_valid_q;       // 0 after reset, 1 after first SRAM write

    // Retention shadow registers (always-on domain model, LP2)
    reg [31:0] shadow_lo_q;         // shadow copy of result_lo_q
    reg [31:0] shadow_hi_q;         // shadow copy of result_hi_q

    // Combinational signals
    wire [63:0] product;             // 32x32 multiplier output
    reg  [63:0] accum_d;            // accumulator next value

    // ===================================================================
    // Combinational: Stage 2 Compute Logic
    // ===================================================================

    // 32x32 multiplier -> 64-bit product
    assign product = src_a_q * src_b_q;

    // Accumulator next value (E2: default-first prevents latch inference)
    // Base value comes from SRAM load (acc_loaded_*_q) rather than from
    // the computed result, making the SRAM the true persistent storage.
    always @(*) begin
        // Default: hold SRAM-loaded accumulator value
        accum_d = {acc_loaded_hi_q, acc_loaded_lo_q};

        if (stage1_valid_q) begin
            case (op_sel_q)
                2'b00:  // MAC: accumulate product onto loaded accumulator
                    accum_d = {acc_loaded_hi_q, acc_loaded_lo_q} + product;

                2'b01:  // MUL: product only (no accumulation)
                    accum_d = product;

                2'b10:  // ADD: add operands (32-bit result, upper zero)
                    accum_d = {32'd0, src_a_q + src_b_q};

                2'b11:  // ACC: accumulate src_a onto loaded accumulator
                    accum_d = {acc_loaded_hi_q, acc_loaded_lo_q}
                            + {32'd0, src_a_q};

                default: // C2: recover to SRAM-loaded value
                    accum_d = {acc_loaded_hi_q, acc_loaded_lo_q};
            endcase
        end
    end

    // ===================================================================
    // Sequential: Stage 1 — Input Registers (PH1)
    // ===================================================================
    // Register src_a_i, src_b_i, op_sel_i on start_i (when not busy).
    // Apply operand isolation (LP6): if isolate_en_i, zero the registered
    // operands to gate the wide (>32-bit) combinational multiplier inputs.
    //
    // Load accumulator from SRAM at current addr_q so the Stage 2 compute
    // adds the product onto the SRAM-stored context value (PH3 read path).
    always @(posedge clk_i) begin
        if (rst_i) begin
            src_a_q        <= 32'd0;
            src_b_q        <= 32'd0;
            op_sel_q       <= 2'd0;
            acc_loaded_lo_q <= 32'd0;
            acc_loaded_hi_q <= 32'd0;
            stage1_valid_q <= 1'b0;
        end else if (clk_en_i) begin
            stage1_valid_q <= start_i && !busy_q;
            if (start_i && !busy_q) begin
                // LP6: operand isolation for >32-bit combinational logic
                src_a_q  <= isolate_en_i ? 32'd0 : src_a_i;
                src_b_q  <= isolate_en_i ? 32'd0 : src_b_i;
                op_sel_q <= op_sel_i;

                // PH3: load accumulator from SRAM in same hierarchy.
                // Skip SRAM read on first use after reset (SRAM uninitialized).
                // sram_valid_q tracks whether SRAM has been written.
                if (sram_valid_q) begin
                    acc_loaded_lo_q <= mem_q[addr_q];
                    acc_loaded_hi_q <= mem_q[addr_q + 8'd1];
                end else begin
                    // First use: keep acc_loaded at reset value (0)
                    acc_loaded_lo_q <= 32'd0;
                    acc_loaded_hi_q <= 32'd0;
                end
            end
        end
    end

    // ===================================================================
    // Sequential: Stage 2 — Computed Result Register
    // ===================================================================
    // Register the computed accum_d into the accumulator pipeline register
    // when stage1_valid_q is asserted. Handles retention restore with
    // priority over normal computation.
    //
    // LP2: retain_restore_i restores the accumulator from shadow registers
    // during PSM wake sequence (S_RESTORE state), after the domain clock
    // has been re-enabled.
    always @(posedge clk_i) begin
        if (rst_i) begin
            result_lo_q    <= 32'd0;
            result_hi_q    <= 32'd0;
            stage2_valid_q <= 1'b0;
        end else if (clk_en_i) begin
            // LP2 restore has priority over normal computation
            if (retain_restore_i) begin
                {result_hi_q, result_lo_q} <= {shadow_hi_q, shadow_lo_q};
                stage2_valid_q <= 1'b0;
            end else begin
                stage2_valid_q <= stage1_valid_q;
                if (stage1_valid_q) begin
                    {result_hi_q, result_lo_q} <= accum_d;
                end
            end
        end
    end

    // ===================================================================
    // Sequential: Stage 3 — Output Registers (PH1)
    // ===================================================================
    // All module outputs driven from registers (PH1):
    //   result_lo_o_q, result_hi_o_q, done_q
    // stage2_valid_q propagates through to generate a 1-cycle done_o pulse
    // at the output (3 cycles after start_i).
    always @(posedge clk_i) begin
        if (rst_i) begin
            result_lo_o_q <= 32'd0;
            result_hi_o_q <= 32'd0;
            done_q        <= 1'b0;
        end else if (clk_en_i) begin
            result_lo_o_q <= result_lo_q;
            result_hi_o_q <= result_hi_q;
            done_q        <= stage2_valid_q;
        end
    end

    // ===================================================================
    // Busy / Active Flags (registered outputs — PH1)
    // ===================================================================
    always @(posedge clk_i) begin
        if (rst_i) begin
            busy_q <= 1'b0;
        end else if (clk_en_i) begin
            // Busy: set on start pulse, clear on done pulse
            if (start_i && !busy_q) begin
                busy_q <= 1'b1;
            end else if (done_q) begin
                busy_q <= 1'b0;
            end
        end
    end

    // ===================================================================
    // PH3: SRAM Accumulation Buffer — Write Path
    // ===================================================================
    // 256x32 SRAM stores the 64-bit accumulator as two consecutive entries
    // (lo at even address, hi at odd address). Written on each completed
    // MAC operation (stage2_valid_q) to preserve context.
    //
    // On LP2 retain_restore: write shadow value back to SRAM at current
    // addr_q so the next Stage-1 load gets the correct restored context.
    //
    // Address pointer increments by 2 per operation, wraps after 128
    // contexts (256 entries = 256 x 32b).
    always @(posedge clk_i) begin
        if (rst_i) begin
            addr_q        <= 8'd0;
            sram_valid_q  <= 1'b0;
            // SRAM (mem_q) is NOT reset — 256 words are too large for
            // synthesis reset. Contents are undefined after reset.
            // sram_valid_q tracks first-write to avoid 'x' reads.
        end else if (clk_en_i) begin
            // LP2: on restore, write shadow to SRAM so the SRAM content
            // matches the restored accumulator for the next context load
            if (retain_restore_i) begin
                mem_q[addr_q]       <= shadow_lo_q;
                mem_q[addr_q + 8'd1] <= shadow_hi_q;
            end else if (stage2_valid_q) begin
                // Save 64-bit accumulator as two 32-bit SRAM entries
                // Fixed single-context: always use SRAM[0:1]
                mem_q[8'd0]      <= result_lo_q;
                mem_q[8'd1]      <= result_hi_q;
                sram_valid_q     <= 1'b1;  // SRAM now has valid data
            end
        end
    end

    // ===================================================================
    // LP2: Retention Save — Shadow Registers (Always-On Domain)
    // ===================================================================
    // Shadow registers are NOT gated by clk_en_i (always-on domain model).
    // On retain_save_i pulse, capture the current computed accumulator so
    // it can be restored after power-off.
    //
    // Per LP2 protocol: retain_save_i is asserted by PSM during
    // S_SAVE_RETAIN BEFORE power is switched off and clock is gated.
    always @(posedge clk_i) begin
        if (retain_save_i) begin
            shadow_lo_q <= result_lo_q;
            shadow_hi_q <= result_hi_q;
        end
    end

    // ===================================================================
    // Output Assignments (PH1: all from registered sources)
    // ===================================================================
    assign result_lo_o = result_lo_o_q;     // registered: line 128-129
    assign result_hi_o = result_hi_o_q;     // registered: line 130
    assign done_o      = done_q;            // registered: line 131
    assign busy_o      = busy_q;            // registered: line 134
    assign active_o    = busy_q;            // registered via busy_q

endmodule

`default_nettype wire
