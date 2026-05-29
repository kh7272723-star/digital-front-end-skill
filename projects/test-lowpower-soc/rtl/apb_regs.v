`default_nettype none

module apb_regs (
    input  wire        clk_i,
    input  wire        rst_i,
    // APB slave interface
    input  wire [11:0] paddr_i,
    input  wire        psel_i,
    input  wire        penable_i,
    input  wire        pwrite_i,
    input  wire [31:0] pwdata_i,
    output wire [31:0] prdata_o,
    output wire        pready_o,
    output wire        pslverr_o,
    // Control outputs (to submodules)
    // PSM
    output reg         psm_sleep_req_o,
    output reg         psm_wake_req_o,
    input  wire [2:0]  psm_power_state_i,
    input  wire        psm_sleep_ack_i,
    input  wire        psm_wake_ack_i,
    // DVFS
    output wire        dvfs_freq_req_o,
    output wire [3:0]  dvfs_freq_idx_o,
    input  wire [3:0]  dvfs_current_freq_i,
    input  wire        dvfs_busy_i,
    // Clock Gate
    output wire [3:0]  cg_gate_en_o,
    output wire [3:0]  cg_force_on_o,
    input  wire [3:0]  cg_activity_i,
    // Datapath
    output wire [31:0] dp_src_a_o,
    output wire [31:0] dp_src_b_o,
    output reg         dp_start_o,     // pulse (1 cycle) like psm_sleep_req
    output wire [1:0]  dp_op_sel_o,
    input  wire [31:0] dp_result_lo_i,
    input  wire [31:0] dp_result_hi_i,
    input  wire        dp_done_i,
    input  wire        dp_busy_i
);

    // ============================================================
    // Internal declarations
    // ============================================================

    // RW CSR registers
    reg [1:0]  psm_ctrl_q;      // offset 0x00: [0]=sleep_req, [1]=wake_req
    reg [4:0]  dvfs_ctrl_q;     // offset 0x08: [3:0]=freq_idx, [4]=req
    reg [7:0]  cg_ctrl_q;       // offset 0x10: [3:0]=gate_en, [7:4]=force_on
    reg [31:0] dp_src_a_q;      // offset 0x20
    reg [31:0] dp_src_b_q;      // offset 0x24
    reg [2:0]  dp_ctrl_q;       // offset 0x28: [0]=start, [2:1]=op_sel

    // Latched status registers (updated every cycle from status inputs)
    reg [3:0]  psm_status_q;    // offset 0x04: [2:0]=power_state, [3]=busy
    reg [4:0]  dvfs_status_q;   // offset 0x0C: [3:0]=current_freq, [4]=busy
    reg [5:0]  cg_status_q;     // offset 0x14: [3:0]=activity, [5:4]=reserved
    reg [1:0]  dp_status_q;     // offset 0x2C: [0]=done, [1]=busy
    reg [31:0] dp_result_lo_q;  // offset 0x30
    reg [31:0] dp_result_hi_q;  // offset 0x34

    // PRDATA registered output
    reg [31:0] prdata_q;

    // Read mux intermediate (assigned in combinational always block)
    reg [31:0] rd_data;


    // ============================================================
    // APB decode logic
    // ============================================================

    // Phase detection
    wire access_phase      = psel_i & penable_i;
    wire invalid_addr      = (paddr_i >= 12'h038);

    // No wait states: PREADY is asserted immediately in the ACCESS phase
    assign pready_o  = access_phase;

    // Completed access gates register updates
    // This follows P7 pattern: gate on (psel_i & penable_i & pready_o)
    wire completed_access  = access_phase & pready_o;
    wire completed_read    = completed_access & ~pwrite_i;

    // PSLVERR asserted on BOTH invalid read AND invalid write (address >= 0x38)
    assign pslverr_o = completed_access & invalid_addr;

    // Write strobes (one per RW register)
    wire wr_do_psm_ctrl  = completed_access & pwrite_i & (paddr_i[11:2] == 10'h000);
    wire wr_do_dvfs_ctrl = completed_access & pwrite_i & (paddr_i[11:2] == 10'h002);
    wire wr_do_cg_ctrl   = completed_access & pwrite_i & (paddr_i[11:2] == 10'h004);
    wire wr_do_dp_src_a  = completed_access & pwrite_i & (paddr_i[11:2] == 10'h008);
    wire wr_do_dp_src_b  = completed_access & pwrite_i & (paddr_i[11:2] == 10'h009);
    wire wr_do_dp_ctrl   = completed_access & pwrite_i & (paddr_i[11:2] == 10'h00A);


    // ============================================================
    // Read data mux (combinational)
    // ============================================================
    // Default rd_data = 32'h0; address match selects the addressed register.
    // Addresses >= 0x38 (word addr >= 0x0E) fall through to default.
    // Address holes (e.g., 0x18, 0x1C) also fall through to default.

    always @(*) begin
        case (paddr_i[11:2])
            10'h000: rd_data = {30'h0, psm_ctrl_q};
            10'h001: rd_data = {28'h0, psm_status_q};
            10'h002: rd_data = {27'h0, dvfs_ctrl_q};
            10'h003: rd_data = {27'h0, dvfs_status_q};
            10'h004: rd_data = {24'h0, cg_ctrl_q};
            10'h005: rd_data = {26'h0, cg_status_q};
            10'h008: rd_data = dp_src_a_q;
            10'h009: rd_data = dp_src_b_q;
            10'h00A: rd_data = {29'h0, dp_ctrl_q};
            10'h00B: rd_data = {30'h0, dp_status_q};
            10'h00C: rd_data = dp_result_lo_q;
            10'h00D: rd_data = dp_result_hi_q;
            default: rd_data = 32'h0;
        endcase
    end


    // ============================================================
    // PRDATA register (sampled on completed read, hold until next read)
    // ============================================================

    always @(posedge clk_i) begin
        if (rst_i) begin
            prdata_q <= 32'h0;
        end else if (completed_read) begin
            prdata_q <= rd_data;
        end
    end

    assign prdata_o = prdata_q;


    // ============================================================
    // Sequential: CSR registers, status latching, pulse outputs
    // ============================================================

    always @(posedge clk_i) begin
        if (rst_i) begin
            psm_ctrl_q      <= 2'b0;
            dvfs_ctrl_q     <= 5'b0;
            cg_ctrl_q       <= 8'b0;
            dp_src_a_q      <= 32'b0;
            dp_src_b_q      <= 32'b0;
            dp_ctrl_q       <= 3'b0;
            psm_status_q    <= 4'b0;
            dvfs_status_q   <= 5'b0;
            cg_status_q     <= 6'b0;
            dp_status_q     <= 2'b0;
            dp_result_lo_q  <= 32'b0;
            dp_result_hi_q  <= 32'b0;
            psm_sleep_req_o <= 1'b0;
            psm_wake_req_o  <= 1'b0;
            dp_start_o      <= 1'b0;
        end else begin
            // ---- Pulse outputs (1 cycle, on CSR write detection) ----
            // Edge detection on CSR write: generate pulse when wr_do fires
            // with the corresponding data bit set. Pulse width = 1 cycle.
            psm_sleep_req_o <= wr_do_psm_ctrl & pwdata_i[0];
            psm_wake_req_o  <= wr_do_psm_ctrl & pwdata_i[1];
            dp_start_o      <= wr_do_dp_ctrl  & pwdata_i[0];  // pulse (1 cycle)

            // ---- Status latching (every cycle) ----
            // PSM STATUS  (offset 0x04): [2:0]=power_state, [3]=busy (any ack)
            psm_status_q   <= {psm_sleep_ack_i | psm_wake_ack_i, psm_power_state_i};
            // DVFS STATUS (offset 0x0C): [3:0]=current_freq, [4]=busy
            dvfs_status_q  <= {dvfs_busy_i, dvfs_current_freq_i};
            // CG STATUS   (offset 0x14): [3:0]=activity, [5:4]=reserved
            cg_status_q    <= {2'b0, cg_activity_i};
            // DP STATUS: [0]=done (sticky), [1]=busy (live)
            if (dp_done_i)
                dp_status_q[0] <= 1'b1;          // sticky done
            else if (wr_do_dp_ctrl)
                dp_status_q[0] <= 1'b0;          // clear on new start
            dp_status_q[1] <= dp_busy_i;
            // DP results: latch on done pulse, hold until next done
            if (dp_done_i) begin
                dp_result_lo_q <= dp_result_lo_i;
                dp_result_hi_q <= dp_result_hi_i;
            end

            // ---- RW register updates (on write strobe) ----
            if (wr_do_psm_ctrl)  psm_ctrl_q  <= pwdata_i[1:0];
            if (wr_do_dvfs_ctrl) dvfs_ctrl_q <= pwdata_i[4:0];
            if (wr_do_cg_ctrl)   cg_ctrl_q   <= pwdata_i[7:0];
            if (wr_do_dp_src_a)  dp_src_a_q  <= pwdata_i[31:0];
            if (wr_do_dp_src_b)  dp_src_b_q  <= pwdata_i[31:0];
            if (wr_do_dp_ctrl)   dp_ctrl_q   <= pwdata_i[2:0];
        end
    end


    // ============================================================
    // Control outputs: direct from CSR register bits
    // ============================================================

    // DVFS control
    assign dvfs_freq_req_o = dvfs_ctrl_q[4];
    assign dvfs_freq_idx_o = dvfs_ctrl_q[3:0];

    // Clock Gate control
    assign cg_gate_en_o  = cg_ctrl_q[3:0];
    assign cg_force_on_o = cg_ctrl_q[7:4];

    // Datapath control (src_a and src_b are level, start is pulse)
    assign dp_src_a_o  = dp_src_a_q;
    assign dp_src_b_o  = dp_src_b_q;
    assign dp_op_sel_o = dp_ctrl_q[2:1];

endmodule
