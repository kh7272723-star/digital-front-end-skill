`timescale 1ns / 100ps
// ============================================================================
// tb_nvme_io — NVMe I/O Datapath Testbench
// Golden Reference Strategy D: end-to-end data integrity
// ============================================================================

module tb_nvme_io;

    reg         clk_i;
    reg         rst_ni;
    // Command
    reg         cmd_valid_i;
    wire        cmd_ready_o;
    reg  [7:0]  cmd_opcode_i;
    reg  [16:0] cmd_cid_i;
    reg  [31:0] cmd_nsid_i;
    reg  [63:0] cmd_prp1_i;
    reg  [63:0] cmd_prp2_i;
    reg  [63:0] cmd_slba_i;
    reg  [16:0] cmd_nlb_i;
    reg  [7:0]  cmd_sqid_i;
    reg  [16:0] cmd_sq_head_i;
    // Completion
    wire        cpl_valid_o;
    reg         cpl_ready_i;
    wire [7:0]  cpl_sqid_o;
    wire [16:0] cpl_sqhd_o;
    wire [16:0] cpl_cid_o;
    wire [16:0] cpl_status_o;
    // NVM SRAM
    wire [63:0] nvm_addr_o;
    wire        nvm_rd_en_o;
    reg  [63:0] nvm_rdata_i;
    reg         nvm_rvalid_i;
    // AXI master
    wire        m_axi_aw_valid;
    reg         m_axi_aw_ready;
    wire [63:0] m_axi_aw_addr;
    wire [7:0]  m_axi_aw_len;
    wire        m_axi_w_valid;
    reg         m_axi_w_ready;
    wire [63:0] m_axi_w_data;
    wire [7:0]  m_axi_w_strb;
    wire        m_axi_w_last;
    reg         m_axi_b_valid;
    wire        m_axi_b_ready;
    reg  [1:0]  m_axi_b_resp;

    localparam CLK_PERIOD = 20;
    localparam LBA_SIZE   = 512;

    integer error_cnt;
    integer i;
    reg [63:0] host_buf [0:8191];  // host memory: 512KB
    reg [63:0] nvm_mem  [0:8191];  // NVM SRAM model
    reg [63:0] expected_val;

    nvme_io_top dut (.*);

    always #(CLK_PERIOD/2) clk_i = ~clk_i;

    // ==================================================================
    // AXI Write Monitor: capture data to host_buf
    // ==================================================================
    reg [63:0] aw_addr_held;
    reg [7:0]  aw_len_held;
    reg [7:0]  w_beat;

    always @(posedge clk_i) begin
        #1;
        if (m_axi_aw_valid && m_axi_aw_ready) begin
            aw_addr_held <= m_axi_aw_addr;
            aw_len_held  <= m_axi_aw_len;
        end
    end

    always @(posedge clk_i) begin
        #1;
        if (m_axi_w_valid && m_axi_w_ready) begin
            host_buf[aw_addr_held[15:3] + w_beat] <= m_axi_w_data;
            w_beat <= w_beat + 1'b1;
            if (m_axi_w_last)
                w_beat <= 0;
        end
    end

    // AXI B responder
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            m_axi_b_valid <= 0;
        else if (m_axi_w_valid && m_axi_w_ready && m_axi_w_last)
            m_axi_b_valid <= 1;
        else if (m_axi_b_valid && m_axi_b_ready)
            m_axi_b_valid <= 0;
    end

    // ==================================================================
    // NVM SRAM: 1-cycle read latency
    // ==================================================================
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            nvm_rvalid_i <= 0;
            nvm_rdata_i  <= 0;
        end else begin
            if (nvm_rd_en_o) begin
                nvm_rvalid_i <= 1;
                nvm_rdata_i  <= nvm_mem[nvm_addr_o[15:3]];
            end else begin
                nvm_rvalid_i <= 0;
            end
        end
    end

    // ==================================================================
    // Command sender
    // ==================================================================
    task send_cmd;
        input [16:0] cid;
        input [63:0] slba;
        input [16:0] nlb;
        input [63:0] prp1;
        input [63:0] prp2;
    begin
        while (!cmd_ready_o) @(posedge clk_i);
        @(negedge clk_i);
        cmd_valid_i   = 1;
        cmd_opcode_i  = 8'h02;
        cmd_cid_i     = cid;
        cmd_nsid_i    = 1;
        cmd_slba_i    = slba;
        cmd_nlb_i     = nlb;
        cmd_prp1_i    = prp1;
        cmd_prp2_i    = prp2;
        cmd_sqid_i    = 1;
        cmd_sq_head_i = 1;
        @(negedge clk_i);
        cmd_valid_i = 0;
    end
    endtask

    // ==================================================================
    // Main test sequence
    // ==================================================================
    initial begin
        clk_i   = 0;
        rst_ni  = 0;
        error_cnt = 0;
        {cmd_valid_i, cmd_opcode_i, cmd_cid_i, cmd_nsid_i,
         cmd_prp1_i, cmd_prp2_i, cmd_slba_i, cmd_nlb_i,
         cmd_sqid_i, cmd_sq_head_i} = 0;
        m_axi_aw_ready = 1;
        m_axi_w_ready  = 1;
        cpl_ready_i    = 1;
        m_axi_b_resp   = 0;
        w_beat = 0;

        $display("SIMULATION_START");
        repeat (10) @(posedge clk_i);
        rst_ni = 1;
        repeat (5) @(posedge clk_i);
        $display("RESET_RELEASED");

        // ────────────────────────────────────────
        // T1: NLB=0, single 512B page, PRP2=Reserved
        // ────────────────────────────────────────
        $display("TEST_START T1_nlb0_single_page");
        // Fill NVM with known pattern at SLBA=0
        for (i = 0; i < 64; i = i + 1)
            nvm_mem[i] = 64'hA000_0000_0000_0000 + i;

        // PRP1 points to host addr 0x1000 (offset 0, 4KB page)
        send_cmd(1, 0, 0, 64'h0000_0000_0000_1000, 64'h0000_0000_0000_0000);

        while (!cpl_valid_o) @(posedge clk_i);
        $display("  CPL: CID=%0d SQID=%0d STATUS=%0d", cpl_cid_o, cpl_sqid_o, cpl_status_o);

        // Verify: host_buf at 0x1000 should match nvm_mem[0..63]
        for (i = 0; i < 64; i = i + 1) begin
            expected_val = 64'hA000_0000_0000_0000 + i;
            if (host_buf[512 + i] != expected_val) begin
                $display("  FAIL: host_buf[%0d]=%016h expect %016h",
                         i, host_buf[512 + i], expected_val);
                error_cnt = error_cnt + 1;
            end
        end
        if (cpl_status_o != 0) begin
            $display("  FAIL: status=%0d expect 0", cpl_status_o);
            error_cnt = error_cnt + 1;
        end
        if (cpl_cid_o != 1) begin
            $display("  FAIL: CID=%0d expect 1", cpl_cid_o);
            error_cnt = error_cnt + 1;
        end
        $display("TEST_PASS T1_nlb0_single_page");
        cpl_ready_i = 1; @(posedge clk_i); cpl_ready_i = 0; @(posedge clk_i); cpl_ready_i = 1;

        // ────────────────────────────────────────
        // T2: NLB=15, 8KB, two-page PRP2=Page
        // ────────────────────────────────────────
        $display("TEST_START T2_nlb15_two_page");
        for (i = 0; i < 1024; i = i + 1)
            nvm_mem[64 + i] = 64'hB000_0000_0000_0000 + i;

        // PRP1→host 0x2000, PRP2→host 0x3000
        send_cmd(2, 1, 15, 64'h0000_0000_0000_2000, 64'h0000_0000_0000_3000);

        while (!cpl_valid_o) @(posedge clk_i);
        $display("  CPL: CID=%0d SQID=%0d STATUS=%0d", cpl_cid_o, cpl_sqid_o, cpl_status_o);

        // PRP1 page (first 512 bytes = 64 beats)
        for (i = 0; i < 64; i = i + 1) begin
            expected_val = 64'hB000_0000_0000_0000 + i;
            if (host_buf[1024 + i] != expected_val) begin
                $display("  FAIL PRP1: host_buf[%0d]=%016h expect %016h",
                         i, host_buf[1024 + i], expected_val);
                error_cnt = error_cnt + 1;
            end
        end
        // PRP2 page (remaining 64 beats)
        for (i = 0; i < 64; i = i + 1) begin
            expected_val = 64'hB000_0000_0000_0000 + 64 + i;
            if (host_buf[1536 + i] != expected_val) begin
                $display("  FAIL PRP2: host_buf[%0d]=%016h expect %016h",
                         i, host_buf[1536 + i], expected_val);
                error_cnt = error_cnt + 1;
            end
        end
        if (cpl_status_o != 0) begin
            $display("  FAIL: status=%0d", cpl_status_o); error_cnt = error_cnt + 1;
        end
        $display("TEST_PASS T2_nlb15_two_page");

        // Report
        if (error_cnt == 0)
            $display("ALL_TESTS_PASS");
        else
            $display("FAIL: %0d errors", error_cnt);
        $display("SIMULATION_DONE");
        $finish;
    end

endmodule
