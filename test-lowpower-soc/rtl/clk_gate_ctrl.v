`default_nettype none

// ============================================================================
// clk_gate_ctrl — Clock Gating Controller
//
// Controls clock gating for 4 power domains. Validates LP4 (gated clock domain
// CDC pulse synchronizer). Part of low-power SoC subsystem.
//
// Clock gating formula (per domain d):
//   domain_clk_en_o[d] = !gate_en_i[d] | force_on_i[d] | activity_detected[d]
//
// Auto-gating (domain 0): if datapath_active_i stays 0 for IDLE_THRESHOLD
// consecutive cycles, auto-activity flag clears and clock may gate.
// Auto-ungating: immediate when datapath_active_i asserts or force_on set.
//
// CDC (LP4): gated_event_i crosses from a potentially-gated domain to the
// always-on clk_i domain using a pulse synchronizer:
//   edge-detect → toggle → 2FF sync → edge-detect → ungated_event_o
//
// References:
//   - low-power-guidelines.md §1 (Clock gating), §8 (Power-aware CDC)
//   - cdc-guidelines.md (synchronizer ASYNC_REG attribute)
//   - bug-pattern-library.md CL1 (clock gating glitch)
//   - interface-contracts.md Module 3 (clk_gate_ctrl)
// ============================================================================

module clk_gate_ctrl #(
    parameter IDLE_THRESHOLD = 8  // idle cycles before auto-gate domain 0
) (
    // Clock and reset (always-on domain)
    input  wire       clk_i,
    input  wire       rst_i,

    // APB CSR interface
    input  wire [3:0] gate_en_i,    // per-domain gate enable (bit[0]=datapath)
    input  wire [3:0] force_on_i,   // per-domain force clock on (override)

    // Domain clock enables (registered internal, wire output)
    output wire [3:0] domain_clk_en_o,

    // Activity monitoring (from datapath)
    input  wire       datapath_active_i,  // datapath has pending work

    // CDC: signal FROM gated domain TO ungated (PWR_MGMT) domain (LP4)
    input  wire       gated_event_i,      // event from gated domain (on gated clk)
    output wire       ungated_event_o,    // same event, synchronized to ungated clk

    // Status
    output wire       bus_idle_o,         // all gated domains are idle
    output wire [3:0] activity_o           // per-domain activity status
);

    // -----------------------------------------------------------------------
    // Local parameters
    // -----------------------------------------------------------------------
    localparam IDLE_CNT_W   = $clog2(IDLE_THRESHOLD);  // counter width
    localparam IDLE_CNT_MAX = IDLE_THRESHOLD - 1;       // terminal count

    // -----------------------------------------------------------------------
    // Register declarations
    // -----------------------------------------------------------------------

    // Domain 0 auto-gating (idle counter + recent-activity flag)
    reg [IDLE_CNT_W-1:0] idle_cnt_q;
    reg                  auto_active_q;

    // CDC pulse synchronizer (LP4)
    reg  gated_event_q;          // edge detect: previous cycle sample
    reg  event_toggle_q;         // toggle on each event edge
    (* ASYNC_REG = "TRUE" *)
    reg  event_sync_0_q;         // 1st synchronizer stage
    (* ASYNC_REG = "TRUE" *)
    reg  event_sync_1_q;         // 2nd synchronizer stage
    reg  event_sync_prev_q;     // previous sync value for edge detect

    // Registered domain clock enables (no glitches on output)
    reg [3:0] domain_clk_en_q;

    // -----------------------------------------------------------------------
    // Wire declarations (combinational)
    // -----------------------------------------------------------------------
    wire       gated_event_rise;          // rising edge of gated_event_i
    wire [3:0] domain_clk_en_nxt;         // next clock enable value
    wire       idle_timeout;              // idle counter reached threshold

    // =======================================================================
    // Domain 0 Auto-Gating Logic
    // =======================================================================
    //
    // idle_timeout fires after IDLE_THRESHOLD consecutive idle cycles.
    // auto_active_q is the "recent activity" flag for domain 0:
    //   - Set immediately when datapath_active_i asserts
    //   - Cleared when datapath_active_i stays idle for IDLE_THRESHOLD cycles
    //
    // Cycle trace for auto-gating (IDLE_THRESHOLD=8):
    //   Cycle  N:  datapath_active_i=1 → auto_active_q<=1, idle_cnt<=0
    //   Cycle N+1: datapath_active_i=0, auto_active_q=1, idle_cnt=0 → cnt<=1
    //   ...
    //   Cycle N+8: idle_cnt=7 == IDLE_CNT_MAX → auto_active_q<=0 (gated)
    //   Total idle cycles before gate: 8 (IDLE_THRESHOLD)
    //   Auto-ungate: datapath_active_i=1 on any cycle → immediate ungate
    // -----------------------------------------------------------------------

    assign idle_timeout = (idle_cnt_q == IDLE_CNT_MAX[IDLE_CNT_W-1:0]);

    always @(posedge clk_i) begin
        if (rst_i) begin
            auto_active_q <= 1'b0;
            idle_cnt_q    <= {IDLE_CNT_W{1'b0}};
        end else if (datapath_active_i) begin
            // Activity detected: keep active, reset idle counter
            auto_active_q <= 1'b1;
            idle_cnt_q    <= {IDLE_CNT_W{1'b0}};
        end else if (auto_active_q) begin
            // Idle: count cycles until timeout
            if (idle_timeout) begin
                auto_active_q <= 1'b0;
                idle_cnt_q    <= {IDLE_CNT_W{1'b0}};
            end else begin
                idle_cnt_q <= idle_cnt_q + {{IDLE_CNT_W-1{1'b0}}, 1'b1};
            end
        end
        // else: auto_active_q=0 and idle — hold values
    end

    // =======================================================================
    // Domain Clock Enable Generation (registered output)
    // =======================================================================
    //
    // Formula: domain_clk_en_o[d] = !gate_en_i[d] | force_on_i[d] |
    //                               activity_detected[d]
    // Domain 0 has auto-activity tracking. Domains 1-3 are software-controlled.
    //
    // Registered outputs prevent glitches that could cause partial clock cycles
    // in downstream clock-enabled logic.
    // -----------------------------------------------------------------------

    assign domain_clk_en_nxt[0]   = !gate_en_i[0] | force_on_i[0] | auto_active_q;
    assign domain_clk_en_nxt[3:1] = !gate_en_i[3:1] | force_on_i[3:1];

    always @(posedge clk_i) begin
        if (rst_i)
            domain_clk_en_q <= 4'b0;
        else
            domain_clk_en_q <= domain_clk_en_nxt;
    end

    assign domain_clk_en_o = domain_clk_en_q;

    // =======================================================================
    // Activity Status and Bus Idle
    // =======================================================================
    //
    // activity_o[d] indicates whether domain d has recent/gated activity:
    //   Domain 0: reflects auto_active_q (recent datapath activity)
    //   Domains 1-3: no activity inputs, always report idle
    //
    // bus_idle_o: true when ALL domains are idle (AND of ~activity_o).
    // Used by dvfs_ctrl (LP5 check) to verify bus quiet before frequency
    // transitions.
    // -----------------------------------------------------------------------

    assign activity_o[0]   = auto_active_q;
    assign activity_o[3:1] = {3{1'b0}};

    // bus_idle_o = AND of !activity_o[d] for all gated domains
    // Since activity_o[3:1]=0, simplifies to !activity_o[0]
    assign bus_idle_o = &(~activity_o[3:0]);

    // =======================================================================
    // CDC Pulse Synchronizer (LP4)
    // =======================================================================
    //
    // LP4: Gated clock domain → ungated domain pulse synchronizer.
    //
    // gated_event_i is from a potentially-gated clock domain. If the gated
    // clock stops, a level synchronizer (2FF) would miss edges. Instead we
    // use a pulse synchronizer that converts each event edge to a persistent
    // toggle level before synchronizing.
    //
    // Implementation:
    //   Stage 1: Rising edge detect on gated_event_i
    //   Stage 2: event_toggle flop (toggle on each edge — persistent level)
    //   Stage 3: 2FF synchronizer in always-on domain (ASYNC_REG attribute)
    //   Stage 4: Edge detect on synchronized toggle → ungated_event_o pulse
    //
    // Never gate the clock used by the CDC synchronizer itself.
    //
    // Latency from rising edge of gated_event_i to ungated_event_o pulse:
    //   3 clock cycles (toggle + 2FF + edge detect).
    // -----------------------------------------------------------------------

    // Stage 1: Rising edge detect on gated_event_i
    always @(posedge clk_i) begin
        if (rst_i)
            gated_event_q <= 1'b0;
        else
            gated_event_q <= gated_event_i;
    end
    assign gated_event_rise = gated_event_i && !gated_event_q;

    // Stage 2: Toggle flop — each rising edge toggles the level.
    // The toggle level persists across clock cycles, ensuring the 2FF
    // synchronizer will capture the event even if the gated clock stalls.
    always @(posedge clk_i) begin
        if (rst_i)
            event_toggle_q <= 1'b0;
        else if (gated_event_rise)
            event_toggle_q <= ~event_toggle_q;
    end

    // Stage 3: 2FF synchronizer in the ungated (always-on) domain.
    // ASYNC_REG attribute prevents synthesis tool from optimizing away the
    // synchronizer or placing the flip-flops far apart.
    always @(posedge clk_i) begin
        if (rst_i) begin
            event_sync_0_q <= 1'b0;
            event_sync_1_q <= 1'b0;
        end else begin
            event_sync_0_q <= event_toggle_q;
            event_sync_1_q <= event_sync_0_q;
        end
    end

    // Stage 4: Edge detect on synchronized toggle → 1-cycle output pulse.
    // XOR of sync output with its previous value detects toggle transition.
    always @(posedge clk_i) begin
        if (rst_i)
            event_sync_prev_q <= 1'b0;
        else
            event_sync_prev_q <= event_sync_1_q;
    end
    assign ungated_event_o = event_sync_1_q ^ event_sync_prev_q;

endmodule

`resetall
