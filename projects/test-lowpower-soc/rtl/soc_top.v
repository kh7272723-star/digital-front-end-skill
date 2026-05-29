`default_nettype none

module soc_top (
    input  wire        clk_i,
    input  wire        rst_i,
    // APB external
    input  wire [11:0] paddr_i,
    input  wire        psel_i,
    input  wire        penable_i,
    input  wire        pwrite_i,
    input  wire [31:0] pwdata_i,
    output wire [31:0] prdata_o,
    output wire        pready_o,
    output wire        pslverr_o,
    // External status (for testbench observation)
    output wire [2:0]  psm_state_o,
    output wire [3:0]  dvfs_freq_o,
    output wire [3:0]  cg_activity_o,
    output wire [31:0] mac_result_o,
    output wire        mac_done_o
);
    // ============================================================
    // Internal wires
    // ============================================================
    // PSM <-> APB
    wire        psm_sleep_req;
    wire        psm_wake_req;
    wire [2:0]  psm_power_state;
    wire        psm_sleep_ack;
    wire        psm_wake_ack;
    // PSM outputs
    wire        psm_isolation_en;
    wire        psm_power_switch;
    wire        psm_retain_save;
    wire        psm_retain_restore;
    wire        psm_domain_clk_en;
    // DVFS <-> APB
    wire        dvfs_freq_req;
    wire [3:0]  dvfs_freq_idx;
    wire [3:0]  dvfs_current_freq;
    wire        dvfs_busy;
    // DVFS outputs
    wire        dvfs_isolate_en;
    wire        dvfs_pmu_valid;
    wire [3:0]  dvfs_pmu_freq;
    // Clock Gate <-> APB
    wire [3:0]  cg_gate_en;
    wire [3:0]  cg_force_on;
    wire [3:0]  cg_activity;
    // Clock Gate outputs
    wire [3:0]  cg_domain_clk_en;
    wire        cg_bus_idle;
    wire        cg_ungated_event;
    // Datapath <-> APB
    wire [31:0] dp_src_a;
    wire [31:0] dp_src_b;
    wire        dp_start;
    wire [1:0]  dp_op_sel;
    wire [31:0] dp_result_lo;
    wire [31:0] dp_result_hi;
    wire        dp_done;
    wire        dp_busy;
    // Datapath outputs
    wire        dp_active;

    // ============================================================
    // Module instantiations
    // ============================================================

    // APB Register Block
    apb_regs u_apb_regs (
        .clk_i              (clk_i),
        .rst_i              (rst_i),
        .paddr_i            (paddr_i),
        .psel_i             (psel_i),
        .penable_i          (penable_i),
        .pwrite_i           (pwrite_i),
        .pwdata_i           (pwdata_i),
        .prdata_o           (prdata_o),
        .pready_o           (pready_o),
        .pslverr_o          (pslverr_o),
        // PSM
        .psm_sleep_req_o    (psm_sleep_req),
        .psm_wake_req_o     (psm_wake_req),
        .psm_power_state_i  (psm_power_state),
        .psm_sleep_ack_i    (psm_sleep_ack),
        .psm_wake_ack_i     (psm_wake_ack),
        // DVFS
        .dvfs_freq_req_o    (dvfs_freq_req),
        .dvfs_freq_idx_o    (dvfs_freq_idx),
        .dvfs_current_freq_i(dvfs_current_freq),
        .dvfs_busy_i        (dvfs_busy),
        // Clock Gate
        .cg_gate_en_o       (cg_gate_en),
        .cg_force_on_o      (cg_force_on),
        .cg_activity_i      (cg_activity),
        // Datapath
        .dp_src_a_o         (dp_src_a),
        .dp_src_b_o         (dp_src_b),
        .dp_start_o         (dp_start),
        .dp_op_sel_o        (dp_op_sel),
        .dp_result_lo_i     (dp_result_lo),
        .dp_result_hi_i     (dp_result_hi),
        .dp_done_i          (dp_done),
        .dp_busy_i          (dp_busy)
    );

    // Power State Machine
    psm u_psm (
        .clk_i              (clk_i),
        .rst_i              (rst_i),
        .sleep_req_i        (psm_sleep_req),
        .wake_req_i         (psm_wake_req),
        .dvfs_busy_i        (dvfs_busy),
        .isolation_en_o     (psm_isolation_en),
        .power_switch_o     (psm_power_switch),
        .retain_save_o      (psm_retain_save),
        .retain_restore_o   (psm_retain_restore),
        .domain_clk_en_o    (psm_domain_clk_en),
        .power_state_o      (psm_power_state),
        .sleep_ack_o        (psm_sleep_ack),
        .wake_ack_o         (psm_wake_ack)
    );

    // DVFS Controller
    dvfs_ctrl u_dvfs_ctrl (
        .clk_i              (clk_i),
        .rst_i              (rst_i),
        .freq_req_i         (dvfs_freq_req),
        .freq_idx_i         (dvfs_freq_idx),
        .bus_idle_i         (cg_bus_idle),
        .isolate_en_o       (dvfs_isolate_en),
        .pmu_valid_o        (dvfs_pmu_valid),
        .pmu_freq_o         (dvfs_pmu_freq),
        .pmu_done_i         (1'b1),  // PMU done immediately in simulation
        .current_freq_o     (dvfs_current_freq),
        .busy_o             (dvfs_busy)
    );

    // Clock Gating Controller
    clk_gate_ctrl u_clk_gate_ctrl (
        .clk_i              (clk_i),
        .rst_i              (rst_i),
        .gate_en_i          (cg_gate_en),
        .force_on_i         (cg_force_on),
        .domain_clk_en_o    (cg_domain_clk_en),
        .datapath_active_i  (dp_active),
        .gated_event_i      (dp_done),     // datapath done as gated event
        .ungated_event_o    (cg_ungated_event),
        .bus_idle_o         (cg_bus_idle),
        .activity_o         (cg_activity)
    );

    // Physical-Aware MAC Array
    phys_aware_datapath u_phys_aware_datapath (
        .clk_i              (clk_i),
        .rst_i              (rst_i),
        .clk_en_i           (cg_domain_clk_en[0]),
        .isolate_en_i       (dvfs_isolate_en),
        .start_i            (dp_start),
        .op_sel_i           (dp_op_sel),
        .src_a_i            (dp_src_a),
        .src_b_i            (dp_src_b),
        .result_lo_o        (dp_result_lo),
        .result_hi_o        (dp_result_hi),
        .done_o             (dp_done),
        .busy_o             (dp_busy),
        .active_o           (dp_active),
        .retain_save_i      (psm_retain_save),
        .retain_restore_i   (psm_retain_restore)
    );

    // ============================================================
    // External status outputs
    // ============================================================
    assign psm_state_o    = psm_power_state;
    assign dvfs_freq_o    = dvfs_current_freq;
    assign cg_activity_o  = cg_activity;
    assign mac_result_o   = dp_result_lo;
    assign mac_done_o     = dp_done;

endmodule

`default_nettype wire
