// =============================================================================
// tb_nvme_io — NVMe I/O Data Path Testbench (Direct cmd_tracker drive)
// =============================================================================
// Bypasses sq_fetch to test PRP walker + read_engine + cmd_tracker + cq_post
// directly. sq_fetch integration is a separate debug step.
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module tb_nvme_io;
    localparam CLK_PERIOD     = 4;
    localparam PAGE_SIZE      = 4096;
    localparam HOST_MEM_SIZE  = 131072;
    localparam NVM_SRAM_SIZE  = 131072;
    localparam TIMEOUT_CYCLES = 50000;

    // ── DUT signals ──
    reg         clk, rst_n;
    reg  [63:0] sq_base;
    reg  [15:0] sq_depth, cq_depth;
    reg  [63:0] cq_base;
    reg  [15:0] doorbell_tail;
    reg         doorbell_valid;
    wire [63:0] nvm_addr;
    wire        nvm_rd_en;
    reg  [63:0] nvm_rdata;
    reg         nvm_rvalid;
    wire        axi_ar_valid, axi_aw_valid, axi_w_valid;
    reg         axi_ar_ready, axi_aw_ready, axi_w_ready;
    wire [63:0] axi_ar_addr, axi_aw_addr, axi_w_data;
    wire [7:0]  axi_ar_len, axi_aw_len, axi_w_strb;
    wire        axi_w_last;
    reg         axi_r_valid, axi_b_valid;
    wire        axi_r_ready, axi_b_ready;
    reg  [63:0] axi_r_data;
    reg         axi_r_last;
    reg  [1:0]  axi_b_resp;
    wire        cqe_written;
    wire [15:0] cqe_cid, cqe_status;
    // cqe_written = cpl handshake complete
    assign cqe_written = cpl_valid && cpl_ready;
    assign cqe_cid     = cpl_cid;
    assign cqe_status  = cpl_status;

    // ── Host memory ──
    reg [63:0] host_mem [0:HOST_MEM_SIZE-1];

    // ── AXI slave state ──
    reg [63:0] ar_addr_q;
    reg [7:0]  ar_len_q, ar_beat_q;
    reg        ar_active_q;
    reg [63:0] aw_addr_q;
    reg [7:0]  aw_len_q, aw_beat_q;
    reg        aw_active_q, b_pending_q;

    // ── NVM SRAM ──
    reg [63:0] nvm_sram [0:NVM_SRAM_SIZE-1];

    // ── Golden Reference Scoreboard ──
    reg [63:0] sb_expected [0:HOST_MEM_SIZE-1];
    reg [63:0] sb_observed  [0:HOST_MEM_SIZE-1];
    reg        sb_written   [0:HOST_MEM_SIZE-1];
    integer    sb_wr_cnt, sb_mismatch;

    // ── Test state ──
    integer   fail_cnt, cycle_cnt, i, j, wait_cnt;
    reg [15:0] got_cid, got_status;

    // ── Direct command injection to cmd_tracker ──
    reg        tkr_cmd_valid;
    wire       tkr_cmd_ready;
    reg [7:0]  tkr_cmd_opcode;
    reg [15:0] tkr_cmd_cid;
    reg [31:0] tkr_cmd_nsid;
    reg [63:0] tkr_cmd_prp1;
    reg [63:0] tkr_cmd_prp2;
    reg [63:0] tkr_cmd_slba;
    reg [15:0] tkr_cmd_nlb;
    reg [7:0]  tkr_cmd_sqid;
    reg [15:0] tkr_cmd_sq_head;

    // =========================================================================
    // DUT — simplified top: cmd_tracker + prp_walker + read_engine + cq_post + axi_adapter
    // =========================================================================
    wire        prp_start, prp_done, prp_error;
    wire [15:0] prp_err_st;
    wire [63:0] prp1, prp2;
    wire [31:0] prp_xfer;
    wire        rd_start, rd_done, rd_error;
    wire [63:0] rd_slba;
    wire [31:0] rd_total;
    wire [63:0] page_addr;
    wire [15:0] page_bytes;
    wire        page_valid, page_ready, page_done;
    wire        s2_ar_valid, s2_ar_ready;
    wire [63:0] s2_ar_addr;
    wire [7:0]  s2_ar_len;
    wire        s2_r_valid, s2_r_ready;
    wire [63:0] s2_r_data;
    wire        s2_r_last;
    wire        s3_aw_valid, s3_aw_ready;
    wire [63:0] s3_aw_addr;
    wire [7:0]  s3_aw_len;
    wire        s3_w_valid, s3_w_ready;
    wire [63:0] s3_w_data;
    wire [7:0]  s3_w_strb;
    wire        s3_w_last;
    wire        s3_b_valid, s3_b_ready;
    wire        cpl_valid, cpl_ready;
    wire [7:0]  cpl_sqid;
    wire [15:0] cpl_sqhd, cpl_cid, cpl_status;
    wire        s1_aw_valid, s1_aw_ready, s1_w_valid, s1_w_ready;
    wire [63:0] s1_aw_addr, s1_w_data;
    wire [7:0]  s1_w_strb;
    wire        s1_w_last, s1_b_valid, s1_b_ready;

    // R channel: use wires (driven by combinational assign)
    wire        dut_r_valid, dut_r_ready;
    wire [63:0] dut_r_data;
    wire        dut_r_last;

    nvme_cmd_tracker #(.NUM_SLOTS(4), .LBA_SIZE(512)) u_tracker (
        .clk_i(clk), .rst_ni(rst_n),
        .cmd_valid_i(tkr_cmd_valid), .cmd_ready_o(tkr_cmd_ready),
        .cmd_opcode_i(tkr_cmd_opcode), .cmd_cid_i(tkr_cmd_cid),
        .cmd_nsid_i(tkr_cmd_nsid), .cmd_prp1_i(tkr_cmd_prp1),
        .cmd_prp2_i(tkr_cmd_prp2), .cmd_slba_i(tkr_cmd_slba),
        .cmd_nlb_i(tkr_cmd_nlb), .cmd_sqid_i(tkr_cmd_sqid),
        .cmd_sq_head_i(tkr_cmd_sq_head),
        .prp_start_o(prp_start), .prp_done_i(prp_done),
        .prp_error_i(prp_error), .prp_error_status_i(prp_err_st),
        .prp_prp1_o(prp1), .prp_prp2_o(prp2), .prp_transfer_bytes_o(prp_xfer),
        .rd_start_o(rd_start), .rd_done_i(rd_done), .rd_error_i(rd_error),
        .rd_slba_o(rd_slba), .rd_total_bytes_o(rd_total),
        .cpl_valid_o(cpl_valid), .cpl_ready_i(cpl_ready),
        .cpl_sqid_o(cpl_sqid), .cpl_sqhd_o(cpl_sqhd),
        .cpl_cid_o(cpl_cid), .cpl_status_o(cpl_status)
    );

    nvme_prp_walker #(.PAGE_SIZE(4096), .AXI_DATA_W(64), .AXI_ADDR_W(64), .LIST_ENTRIES(512)) u_walker (
        .clk_i(clk), .rst_ni(rst_n),
        .start_i(prp_start), .done_o(prp_done), .error_o(prp_error),
        .error_status_o(prp_err_st),
        .prp1_i(prp1), .prp2_i(prp2), .transfer_bytes_i(prp_xfer),
        .page_addr_o(page_addr), .page_bytes_o(page_bytes),
        .page_valid_o(page_valid), .page_ready_i(page_ready),
        .page_done_i(page_done),
        .list_ar_valid_o(s2_ar_valid), .list_ar_ready_i(s2_ar_ready),
        .list_ar_addr_o(s2_ar_addr), .list_ar_len_o(s2_ar_len),
        .list_r_valid_i(s2_r_valid), .list_r_ready_o(s2_r_ready),
        .list_r_data_i(s2_r_data), .list_r_last_i(s2_r_last)
    );

    nvme_read_engine #(.AXI_DATA_W(64), .AXI_ADDR_W(64), .AXI_MAX_BURST(256),
                       .LBA_SIZE(512), .FIFO_DEPTH(8192), .FIFO_ADDR_W(13)) u_reader (
        .clk_i(clk), .rst_ni(rst_n),
        .start_i(rd_start), .done_o(rd_done), .error_o(rd_error),
        .slba_i(rd_slba), .total_bytes_i(rd_total),
        .page_addr_i(page_addr), .page_bytes_i(page_bytes),
        .page_valid_i(page_valid), .page_ready_o(page_ready),
        .page_done_o(page_done),
        .nvm_addr_o(nvm_addr), .nvm_rd_en_o(nvm_rd_en),
        .nvm_rdata_i(nvm_rdata), .nvm_rvalid_i(nvm_rvalid),
        .axi_aw_valid_o(s3_aw_valid), .axi_aw_ready_i(s3_aw_ready),
        .axi_aw_addr_o(s3_aw_addr), .axi_aw_len_o(s3_aw_len),
        .axi_w_valid_o(s3_w_valid), .axi_w_ready_i(s3_w_ready),
        .axi_w_data_o(s3_w_data), .axi_w_strb_o(s3_w_strb),
        .axi_w_last_o(s3_w_last),
        .axi_b_valid_i(s3_b_valid), .axi_b_ready_o(s3_b_ready),
        .axi_b_resp_i(2'b00)
    );

    nvme_cq_post u_cq_post (
        .clk_i(clk), .rst_ni(rst_n),
        .cq_base_i(cq_base), .cq_depth_i(cq_depth),
        .cpl_valid_i(cpl_valid), .cpl_ready_o(cpl_ready),
        .cpl_sqid_i(cpl_sqid), .cpl_sqhd_i(cpl_sqhd),
        .cpl_cid_i(cpl_cid), .cpl_status_i(cpl_status),
        .cpl_has_data_i(1'b0), .cq_data_done_i(1'b1), .cq_data_head_i(16'd0),
        .axi_aw_valid_o(s1_aw_valid), .axi_aw_ready_i(s1_aw_ready),
        .axi_aw_addr_o(s1_aw_addr),
        .axi_w_valid_o(s1_w_valid), .axi_w_ready_i(s1_w_ready),
        .axi_w_data_o(s1_w_data), .axi_w_strb_o(s1_w_strb),
        .axi_w_last_o(s1_w_last)
    );

    // Simplified AXI adapter: just S2(PRP walker AR) + S3(read engine AW/W/B) + S1(cq_post AW/W)
    // No S0 (sq_fetch) in this simplified version
    assign axi_ar_valid = s2_ar_valid;
    assign s2_ar_ready  = axi_ar_ready;
    assign axi_ar_addr  = s2_ar_addr;
    assign axi_ar_len   = s2_ar_len;
    // s2_r_valid is driven by adapter output (R demux)

    // Actually, let's use the full adapter but with S0 disconnected
    nvme_axi_adapter u_adapter (
        .clk_i(clk), .rst_ni(rst_n),
        .s0_ar_valid_i(1'b0), .s0_ar_ready_o(), .s0_ar_addr_i(64'd0), .s0_ar_len_i(8'd0),
        .s0_r_valid_o(), .s0_r_ready_i(1'b1),
        .s0_r_data_o(), .s0_r_last_o(),
        .s1_aw_valid_i(s1_aw_valid), .s1_aw_ready_o(s1_aw_ready),
        .s1_aw_addr_i(s1_aw_addr),
        .s1_w_valid_i(s1_w_valid), .s1_w_ready_o(s1_w_ready),
        .s1_w_data_i(s1_w_data), .s1_w_strb_i(s1_w_strb), .s1_w_last_i(s1_w_last),
        .s1_b_valid_o(s1_b_valid), .s1_b_ready_i(s1_b_ready),
        .s2_ar_valid_i(s2_ar_valid), .s2_ar_ready_o(s2_ar_ready),
        .s2_ar_addr_i(s2_ar_addr), .s2_ar_len_i(s2_ar_len),
        .s2_r_valid_o(s2_r_valid), .s2_r_ready_i(s2_r_ready),
        .s2_r_data_o(s2_r_data), .s2_r_last_o(s2_r_last),
        .s3_aw_valid_i(s3_aw_valid), .s3_aw_ready_o(s3_aw_ready),
        .s3_aw_addr_i(s3_aw_addr), .s3_aw_len_i(s3_aw_len),
        .s3_w_valid_i(s3_w_valid), .s3_w_ready_o(s3_w_ready),
        .s3_w_data_i(s3_w_data), .s3_w_strb_i(s3_w_strb), .s3_w_last_i(s3_w_last),
        .s3_b_valid_o(s3_b_valid), .s3_b_ready_i(s3_b_ready),
        .m_axi_ar_valid(axi_ar_valid), .m_axi_ar_ready(axi_ar_ready),
        .m_axi_ar_addr(axi_ar_addr), .m_axi_ar_len(axi_ar_len),
        .m_axi_r_valid(dut_r_valid), .m_axi_r_ready(dut_r_ready),
        .m_axi_r_data(dut_r_data), .m_axi_r_last(dut_r_last),
        .m_axi_aw_valid(axi_aw_valid), .m_axi_aw_ready(axi_aw_ready),
        .m_axi_aw_addr(axi_aw_addr), .m_axi_aw_len(axi_aw_len),
        .m_axi_w_valid(axi_w_valid), .m_axi_w_ready(axi_w_ready),
        .m_axi_w_data(axi_w_data), .m_axi_w_strb(axi_w_strb), .m_axi_w_last(axi_w_last),
        .m_axi_b_valid(axi_b_valid), .m_axi_b_ready(axi_b_ready),
        .m_axi_b_resp(axi_b_resp)
    );

    // R slave: continuous assignments for clean timing
    assign dut_r_data = host_mem[(ar_addr_q >> 3) + ar_beat_q];
    assign dut_r_last = ar_active_q && (ar_beat_q == ar_len_q);
    assign dut_r_valid = ar_active_q;

    // =========================================================================
    // Clock
    // =========================================================================
    initial begin clk = 1'b0; #(CLK_PERIOD/2); forever #(CLK_PERIOD/2) clk = ~clk; end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_cnt <= 0; else cycle_cnt <= cycle_cnt + 1;
    end

    // =========================================================================
    // AXI Slave: AR → R
    // =========================================================================
    assign axi_ar_ready = !ar_active_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_active_q <= 1'b0; ar_beat_q <= 0;
        end else begin
            if (axi_ar_valid && axi_ar_ready) begin
                ar_active_q <= 1'b1; ar_addr_q <= axi_ar_addr;
                ar_len_q <= axi_ar_len; ar_beat_q <= 0;
            end
            if (ar_active_q && dut_r_ready) begin
                ar_beat_q <= (ar_beat_q == ar_len_q) ? 0 : ar_beat_q + 8'd1;
                if (ar_beat_q == ar_len_q) ar_active_q <= 1'b0;
            end
        end
    end

    // R data already assigned above as dut_r_* wires

    // =========================================================================
    // AXI Slave: AW+W → B
    // =========================================================================
    assign axi_aw_ready = !aw_active_q;
    assign axi_w_ready  = aw_active_q;

    // W data capture on posedge (no negedge needed with pipe register)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_active_q <= 1'b0; aw_beat_q <= 0; b_pending_q <= 1'b0;
            axi_b_valid <= 1'b0;
        end else begin
            if (axi_aw_valid && axi_aw_ready) begin
                aw_active_q <= 1'b1; aw_addr_q <= axi_aw_addr;
                aw_len_q <= axi_aw_len; aw_beat_q <= 0;
            end
            if (aw_active_q && axi_w_valid && axi_w_ready) begin
                host_mem[(aw_addr_q >> 3) + aw_beat_q] <= axi_w_data;
                // Scoreboard: only track data writes (not CQ area 0x2000-0x2FFF)
                if (aw_addr_q < 64'h2000 || aw_addr_q >= 64'h3000) begin
                    sb_observed[(aw_addr_q >> 3) + aw_beat_q] <= axi_w_data;
                    sb_written[(aw_addr_q >> 3) + aw_beat_q] <= 1'b1;
                    sb_wr_cnt <= sb_wr_cnt + 1;
                end
                if (axi_w_last || aw_beat_q == aw_len_q) begin
                    aw_active_q <= 1'b0; b_pending_q <= 1'b1;
                end else aw_beat_q <= aw_beat_q + 8'd1;
            end
            if (b_pending_q) begin
                axi_b_valid <= 1'b1; axi_b_resp <= 2'b00;
                if (axi_b_valid && axi_b_ready) begin
                    b_pending_q <= 1'b0; axi_b_valid <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // NVM SRAM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin nvm_rvalid <= 1'b0; nvm_rdata <= 0; end
        else begin
            nvm_rvalid <= 1'b0;
            if (nvm_rd_en) begin
                nvm_rdata  <= nvm_sram[nvm_addr >> 3];
                nvm_rvalid <= 1'b1;
            end
        end
    end

    // =========================================================================
    // Tasks
    // =========================================================================
    task inject_cmd;
        input [7:0]  opc;
        input [15:0] cid;
        input [63:0] prp1;
        input [63:0] prp2;
        input [63:0] slba;
        input [15:0] nlb;
    begin
        @(posedge clk);
        tkr_cmd_valid  <= 1'b1;
        tkr_cmd_opcode <= opc;
        tkr_cmd_cid    <= cid;
        tkr_cmd_nsid   <= 32'd1;
        tkr_cmd_prp1   <= prp1;
        tkr_cmd_prp2   <= prp2;
        tkr_cmd_slba   <= slba;
        tkr_cmd_nlb    <= nlb;
        tkr_cmd_sqid   <= 8'd0;
        tkr_cmd_sq_head <= 16'd0;
        @(posedge clk);
        while (!tkr_cmd_ready) @(posedge clk);
        tkr_cmd_valid <= 1'b0;
    end
    endtask

    task wait_cqe;
        output [15:0] cid;
        output [15:0] st;
    begin
        wait_cnt = 0; cid = 16'hFFFF; st = 16'hFFFF;
        while (!cqe_written && wait_cnt < TIMEOUT_CYCLES) begin
            @(posedge clk); wait_cnt = wait_cnt + 1;
        end
        if (cqe_written) begin cid = cqe_cid; st = cqe_status; end
        else $display("TIMEOUT after %0d cycles", wait_cnt);
    end
    endtask

    task compute_golden;
        input [31:0] xfer_bytes;
        input [63:0] prp1;
        input [63:0] prp2;
        input [15:0] nlb;
        integer byte_done, page_off, j;
        reg [63:0] cur_page;
        reg [31:0] page_bytes;
    begin
        byte_done = 0;
        page_off  = prp1[11:0];
        cur_page  = {prp1[63:12], 12'h000};

        // First page from PRP1
        page_bytes = PAGE_SIZE - page_off;
        if (page_bytes > xfer_bytes) page_bytes = xfer_bytes;

        for (j = 0; j < page_bytes; j = j + 8) begin
            sb_expected[((cur_page + page_off) >> 3) + (j >> 3)]
                = nvm_sram[(byte_done + j) >> 3];
        end
        byte_done = byte_done + page_bytes;

        if (byte_done >= xfer_bytes) begin
            // Single page only
        end else if (xfer_bytes <= (PAGE_SIZE - page_off) + PAGE_SIZE) begin
            // Two-page (PRP2 is second page)
            cur_page = {prp2[63:12], 12'h000};
            page_bytes = xfer_bytes - byte_done;
            for (j = 0; j < page_bytes; j = j + 8) begin
                sb_expected[(cur_page >> 3) + (j >> 3)]
                    = nvm_sram[(byte_done + j) >> 3];
            end
        end else begin
            // Multi-page via PRP list
            integer entries, k;
            entries = ((xfer_bytes - byte_done) + PAGE_SIZE - 1) / PAGE_SIZE;
            for (k = 0; k < entries && byte_done < xfer_bytes; k = k + 1) begin
                cur_page = host_mem[(prp2 >> 3) + k];  // PRP list entries
                page_bytes = PAGE_SIZE;
                if (page_bytes > xfer_bytes - byte_done)
                    page_bytes = xfer_bytes - byte_done;
                for (j = 0; j < page_bytes; j = j + 8) begin
                    sb_expected[(cur_page >> 3) + (j >> 3)]
                        = nvm_sram[(byte_done + j) >> 3];
                end
                byte_done = byte_done + page_bytes;
            end
        end
    end
    endtask

    task verify_sb;
        input [1023:0] name;
    begin
        sb_mismatch = 0;
        for (i = 0; i < HOST_MEM_SIZE; i = i + 1) if (sb_written[i]) begin
            if (sb_observed[i] !== sb_expected[i]) begin
                sb_mismatch = sb_mismatch + 1;
                $display("  MISMATCH addr=0x%04x got=0x%016x exp=0x%016x",
                         i*8, sb_observed[i], sb_expected[i]);
            end
        end
        if (sb_mismatch == 0)
            $display("TEST_PASS %0s (scoreboard %0d writes OK)", name, sb_wr_cnt);
        else begin
            $display("TEST_FAIL %0s: %0d mismatches", name, sb_mismatch);
            fail_cnt = fail_cnt + 1;
        end
    end
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    initial begin
        $display("SIMULATION_START");
        $dumpfile("sim.vcd");
        $dumpvars(0, tb_nvme_io);

        fail_cnt = 0; cycle_cnt = 0;
        tkr_cmd_valid = 1'b0;

        // Clear memories
        for (i = 0; i < HOST_MEM_SIZE; i = i + 1) begin
            host_mem[i] = 64'd0; sb_written[i] = 1'b0;
            sb_observed[i] = 64'd0; sb_expected[i] = 64'd0;
        end
        for (i = 0; i < NVM_SRAM_SIZE; i = i + 1)
            nvm_sram[i] = {8{i[7:0]}};

        cq_base = 64'h2000; cq_depth = 16'd256;

        rst_n = 1'b0; repeat(5) @(posedge clk); rst_n = 1'b1;
        repeat(2) @(posedge clk);
        $display("RESET_RELEASED at cycle %0d", cycle_cnt);

        // =====================================================================
        // T1: Tiny transfer — NLB=0 (512B), PRP2=Reserved
        // =====================================================================
        begin
            sb_wr_cnt = 0;
            $display("TEST_START T1_tiny");
            compute_golden(512, 64'h3000, 64'd0, 16'd0);
            inject_cmd(8'h02, 16'd1, 64'h3000, 64'd0, 64'd0, 16'd0);
            wait_cqe(got_cid, got_status);
            if (got_cid == 16'hFFFF) begin
                $display("TEST_FAIL T1: timeout"); fail_cnt = fail_cnt + 1;
            end else if (got_status != 16'h0000) begin
                $display("TEST_FAIL T1: status=0x%04x", got_status); fail_cnt = fail_cnt + 1;
            end else verify_sb("T1_tiny");
        end

        // =====================================================================
        // T2: 2-page — NLB=15 (8KB), PRP2=Page
        // =====================================================================
        begin
            sb_wr_cnt = 0;
            for (i = 0; i < HOST_MEM_SIZE; i = i + 1) sb_written[i] = 1'b0;
            $display("TEST_START T2_two_page");
            compute_golden(8192, 64'h3000, 64'h4000, 16'd15);
            inject_cmd(8'h02, 16'd2, 64'h3000, 64'h4000, 64'd0, 16'd15);
            wait_cqe(got_cid, got_status);
            if (got_cid == 16'hFFFF) begin
                $display("TEST_FAIL T2: timeout"); fail_cnt = fail_cnt + 1;
            end else if (got_status != 16'h0000) begin
                $display("TEST_FAIL T2: status=0x%04x", got_status); fail_cnt = fail_cnt + 1;
            end else verify_sb("T2_two_page");
        end

        // =====================================================================
        // T3: Multi-page list — NLB=63 (32KB), PRP2=List (8 entries)
        // =====================================================================
        begin
            sb_wr_cnt = 0;
            for (i = 0; i < HOST_MEM_SIZE; i = i + 1) sb_written[i] = 1'b0;

            // Setup PRP list at 0x6000
            for (i = 0; i < 8; i = i + 1)
                host_mem[(64'h6000 >> 3) + i] = 64'h4000 + (i * 64'h1000);
            host_mem[(64'h6000 >> 3) + 511] = 64'd0;  // chain end

            $display("TEST_START T3_multipage_list");
            compute_golden(32768, 64'h3000, 64'h6000, 16'd63);
            inject_cmd(8'h02, 16'd3, 64'h3000, 64'h6000, 64'd0, 16'd63);
            wait_cqe(got_cid, got_status);
            if (got_cid == 16'hFFFF) begin
                $display("TEST_FAIL T3: timeout"); fail_cnt = fail_cnt + 1;
            end else if (got_status != 16'h0000) begin
                $display("TEST_FAIL T3: status=0x%04x", got_status); fail_cnt = fail_cnt + 1;
            end else verify_sb("T3_multipage_list");
        end

        // =====================================================================
        // Done
        // =====================================================================
        if (fail_cnt == 0) $display("ALL_TESTS_PASS");
        else $display("TESTS_FAILED: %0d", fail_cnt);
        $display("SIMULATION_DONE");
        $finish;
    end

    initial begin #5000000; $display("FATAL: watchdog"); $finish; end

    // ── Debug monitors ──
    always @(posedge clk) if (u_walker.state_q != 0)
        $display("[%0d] walker state=%0d", cycle_cnt, u_walker.state_q);
    always @(posedge clk) if (prp_start)
        $display("[%0d] tracker: prp_start", cycle_cnt);
    always @(posedge clk) if (rd_start)
        $display("[%0d] tracker: rd_start", cycle_cnt);
    always @(posedge clk) if (prp_done)
        $display("[%0d] walker: prp_done", cycle_cnt);
    always @(posedge clk) if (rd_done)
        $display("[%0d] reader: rd_done", cycle_cnt);
    always @(posedge clk) if (cpl_valid && cpl_ready)
        $display("[%0d] CQE: cid=%0d status=0x%04x", cycle_cnt, cpl_cid, cpl_status);
    always @(posedge clk) if (nvm_rd_en && nvm_rvalid)
        $display("[%0d] NVM rd: addr=0x%04x data=0x%016x", cycle_cnt, nvm_addr, nvm_rdata);
    always @(posedge clk) if (axi_aw_valid && axi_aw_ready)
        $display("[%0d] AXI AW: addr=0x%016x len=%0d", cycle_cnt, axi_aw_addr, axi_aw_len);
    // Targeted debug: page 0x8000 (page 5 in T3, base=0x8000, upper bits=0x8)
    always @(posedge clk) if (axi_aw_valid && axi_aw_ready && axi_aw_addr[63:12] == 52'd8)
        $display("[%0d] AW to 0x8xxx: addr=0x%016x len=%0d", cycle_cnt, axi_aw_addr, axi_aw_len);
    always @(posedge clk) if (axi_w_valid && axi_w_ready && axi_w_last
                              && aw_addr_q[63:12] == 52'd8)
        $display("[%0d] WLAST to 0x8xxx: beat=%0d len=%0d",
                 cycle_cnt, aw_beat_q, aw_len_q);

endmodule
`default_nettype wire
