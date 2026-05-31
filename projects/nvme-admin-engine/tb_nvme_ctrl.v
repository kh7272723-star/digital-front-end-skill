`timescale 1ns / 100ps

module tb_nvme_ctrl;

    reg clk_i, rst_ni;
    // APB
    reg  psel_i, penable_i, pwrite_i;
    reg  [15:0] paddr_i;
    reg  [31:0] pwdata_i;
    wire [31:0] prdata_o;
    wire pready_o, pslverr_o;
    // AXI
    wire        m_axi_aw_valid, m_axi_aw_ready;
    wire [63:0] m_axi_aw_addr;
    wire        m_axi_w_valid, m_axi_w_ready;
    wire [63:0] m_axi_w_data;
    wire [7:0]  m_axi_w_strb;
    wire        m_axi_w_last;
    wire        m_axi_ar_valid, m_axi_ar_ready;
    wire [63:0] m_axi_ar_addr;
    wire [7:0]  m_axi_ar_len;
    wire [2:0]  m_axi_ar_size;
    wire        m_axi_r_valid, m_axi_r_ready;
    wire [63:0] m_axi_r_data;
    wire        m_axi_r_last;
    wire        m_axi_b_valid, m_axi_b_ready;
    // Identify data write path
    wire        cq_data_wr, cq_data_valid, cq_data_last, cq_data_ready;
    wire [63:0] cq_data_addr, cq_data;

    assign cq_data_ready = 1'b1;  // testbench always ready to receive data

    nvme_ctrl_top dut (
        .clk_i, .rst_ni,
        .psel_i, .penable_i, .paddr_i, .pwrite_i, .pwdata_i,
        .prdata_o, .pready_o, .pslverr_o,
        .cq_data_wr_o(cq_data_wr),
        .cq_data_addr_o(cq_data_addr),
        .cq_data_o(cq_data),
        .cq_data_valid_o(cq_data_valid),
        .cq_data_last_o(cq_data_last),
        .cq_data_ready_i(cq_data_ready),
        .m_axi_aw_valid, .m_axi_aw_ready, .m_axi_aw_addr,
        .m_axi_w_valid, .m_axi_w_ready, .m_axi_w_data, .m_axi_w_strb, .m_axi_w_last,
        .m_axi_ar_valid, .m_axi_ar_ready, .m_axi_ar_addr, .m_axi_ar_len, .m_axi_ar_size,
        .m_axi_r_valid, .m_axi_r_ready, .m_axi_r_data, .m_axi_r_last,
        .m_axi_b_valid, .m_axi_b_ready
    );

    // Intercept Identify data writes to host memory
    always @(posedge clk_i) begin
        if (cq_data_valid && cq_data_ready)
            host_mem[cq_data_addr >> 3] <= cq_data;
    end

    // ──────────────────────────────────────────
    // Clock + Reset
    // ──────────────────────────────────────────
    localparam CLK_PERIOD = 20;
    always #(CLK_PERIOD/2) clk_i = ~clk_i;

    // ──────────────────────────────────────────
    // Host Memory Model (64-bit wide, AXI slave)
    // ──────────────────────────────────────────
    reg [63:0] host_mem [0:65535];  // 64K × 64-bit = 512KB

    // AW channel
    reg [63:0] aw_addr_q;
    always @(posedge clk_i or negedge rst_ni)
        if (!rst_ni) aw_addr_q <= 64'd0;
        else if (m_axi_aw_valid && m_axi_aw_ready)
            aw_addr_q <= m_axi_aw_addr;

    assign m_axi_aw_ready = 1'b1;

    // W channel — write to host_mem
    reg [7:0] w_beat;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) w_beat <= 8'd0;
        else if (m_axi_w_valid && m_axi_w_ready) begin
            host_mem[(aw_addr_q >> 3) + w_beat] <= m_axi_w_data;
            w_beat <= m_axi_w_last ? 8'd0 : w_beat + 8'd1;
        end
    end

    assign m_axi_w_ready = 1'b1;

    // AR channel — capture address and length on accepted request
    reg [63:0] ar_addr_q;
    reg [7:0]  ar_len_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ar_addr_q <= 64'd0;
            ar_len_q  <= 8'd0;
        end else if (m_axi_ar_valid && m_axi_ar_ready) begin
            ar_addr_q <= m_axi_ar_addr;
            ar_len_q  <= m_axi_ar_len;
        end
    end

    assign m_axi_ar_ready = 1'b1;

    // R channel — stream beats from host_mem
    reg r_active_q;
    reg [7:0] r_beat_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_active_q <= 1'b0;
            r_beat_q   <= 8'd0;
        end else if (m_axi_ar_valid && m_axi_ar_ready) begin
            r_active_q <= 1'b1;
            r_beat_q   <= 8'd0;
        end else if (r_active_q && m_axi_r_valid && m_axi_r_ready) begin
            if (r_beat_q == ar_len_q)
                r_active_q <= 1'b0;
            else
                r_beat_q <= r_beat_q + 8'd1;
        end
    end

    assign m_axi_r_valid = r_active_q;
    assign m_axi_r_data = host_mem[(ar_addr_q >> 3) + r_beat_q];
    assign m_axi_r_last = (r_beat_q == ar_len_q);

    // B channel
    reg b_valid_q;
    always @(posedge clk_i or negedge rst_ni)
        if (!rst_ni) b_valid_q <= 1'b0;
        else b_valid_q <= m_axi_w_valid && m_axi_w_ready && m_axi_w_last;
    assign m_axi_b_valid = b_valid_q;
    assign m_axi_b_ready = 1'b1;

    // ──────────────────────────────────────────
    // APB tasks
    // ──────────────────────────────────────────
    reg [31:0] apb_rdata;
    integer error_cnt;

    task apb_write;
        input [15:0] addr;
        input [31:0] data;
    begin
        @(negedge clk_i);
        psel_i = 1; penable_i = 0; pwrite_i = 1; paddr_i = addr; pwdata_i = data;
        @(negedge clk_i);
        penable_i = 1;
        @(negedge clk_i);
        psel_i = 0; penable_i = 0;
    end
    endtask

    task apb_read;
        input [15:0] addr;
    begin
        @(negedge clk_i);
        psel_i = 1; penable_i = 0; pwrite_i = 0; paddr_i = addr;
        @(negedge clk_i);
        penable_i = 1;
        @(negedge clk_i);
        apb_rdata = prdata_o;
        psel_i = 0; penable_i = 0;
    end
    endtask

    // ──────────────────────────────────────────
    // Helper: write 64-byte SQE to host memory
    // ──────────────────────────────────────────
    task write_sqe;
        input [63:0] addr;
        input [7:0]  opcode;
        input [15:0] cid;
        input [31:0] nsid;
        input [63:0] prp1;
        input [63:0] prp2;
        input [31:0] cdw10;
        input [31:0] cdw11;
    begin
        // SQE is 64 bytes = 8 × 64-bit beats
        // Beat 0: bytes 0-7 (DW0+NSID)
        host_mem[addr>>3]     = {nsid[31:0], 16'd0, cid[15:0], 8'd0, opcode[7:0]};
        // Beat 1: bytes 8-15 (reserved)
        host_mem[(addr>>3)+1] = 64'd0;
        // Beat 2: bytes 16-23 (reserved + MPTR)
        host_mem[(addr>>3)+2] = 64'd0;
        // Beat 3: bytes 24-31 (PRP1)
        host_mem[(addr>>3)+3] = prp1;
        // Beat 4: bytes 32-39 (PRP2)
        host_mem[(addr>>3)+4] = prp2;
        // Beat 5: bytes 40-47 (CDW10+11)
        host_mem[(addr>>3)+5] = {cdw11[31:0], cdw10[31:0]};
        // Beat 6: bytes 48-55 (CDW12+13)
        host_mem[(addr>>3)+6] = 64'd0;
        // Beat 7: bytes 56-63 (CDW14+15)
        host_mem[(addr>>3)+7] = 64'd0;
    end
    endtask

    // ──────────────────────────────────────────
    // Main test
    // ──────────────────────────────────────────
    initial begin
        clk_i = 1'b0;
        error_cnt = 0;
        {psel_i, penable_i, pwrite_i, paddr_i, pwdata_i} = 0;

        $display("SIMULATION_START");

        // Reset
        rst_ni = 1'b0;
        repeat (10) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (5) @(posedge clk_i);
        $display("RESET_RELEASED");

        // ──────────────────────────────────────
        // T1: Controller enable sequence
        // ──────────────────────────────────────
        $display("TEST_START T1_controller_enable");

        // Read CAP
        apb_read(16'h00);
        if (apb_rdata[15:0] != 16'd255) begin
            $display("  FAIL: CAP.MQES=%0d expect 255", apb_rdata[15:0]);
            error_cnt = error_cnt + 1;
        end

        // Read VS
        apb_read(16'h08);
        if (apb_rdata != 32'h00010400) begin
            $display("  FAIL: VS=%08h expect 00010400", apb_rdata);
            error_cnt = error_cnt + 1;
        end

        // Check CSTS.RDY = 0 before enable
        apb_read(16'h1C);
        if (apb_rdata[0] != 1'b0) begin
            $display("  FAIL: CSTS.RDY=1 before enable");
            error_cnt = error_cnt + 1;
        end

        // Setup admin queues
        apb_write(16'h24, (8 << 16) | 8);  // AQA: SQ size=8, CQ size=8
        apb_write(16'h28, 32'h00001000);   // ASQ low = 0x1000
        apb_write(16'h2C, 32'h0);          // ASQ high = 0
        apb_write(16'h30, 32'h00002000);   // ACQ low = 0x2000
        apb_write(16'h34, 32'h0);          // ACQ high = 0

        // Enable controller
        apb_write(16'h14, 32'h1);  // CC.EN=1

        // Check CSTS.RDY = 1
        apb_read(16'h1C);
        if (apb_rdata[0] != 1'b1) begin
            $display("  FAIL: CSTS.RDY=0 after enable");
            error_cnt = error_cnt + 1;
        end else begin
            $display("TEST_PASS T1_controller_enable");
        end

        // ──────────────────────────────────────
        // T2: Identify Controller
        // ──────────────────────────────────────
        $display("TEST_START T2_identify_controller");

        // Place SQE in host memory at ASQ + 0
        write_sqe(64'h00001000, 8'h06, 16'd1, 32'd0, 64'h00003000, 64'd0, {24'd0, 8'h01}, 32'd0);
        // Ring doorbell: SQ0 tail = 1
        apb_write(16'h1000, 32'd1);

        // Wait for Identify DATA_XFER (512 beats) + CQ post (~5 cycles)
        repeat (1000) @(posedge clk_i);

        // Wait for completion
        repeat (20000) @(posedge clk_i);

        // Check CQE in host memory at ACQ + 0
        // CQE beat 0: DW0+1 (bytes 0-7)
        // CQE beat 1: DW2+3 (bytes 8-15)
        // DW2: SQID at bits 63:48, SQHD at bits 47:32
        // DW3: status at bits 31:15, P at bit 14, CID at bits 13:0
        // Wait, let me recalculate. CQE is 16 bytes at ACQ+0.
        // ACQ = 0x2000. In 64-bit host_mem: host_mem[0x2000>>3] = host_mem[1024]
        // Beat 0 at offset 0: DW0 + DW1 = {32'd0, 32'd0} = 0
        // Beat 1 at offset 8: DW2 + DW3

        // Give time for CQ post to complete
        repeat (100) @(posedge clk_i);

        // Read CQ memory
        $display("  CQE beat0: %016h", host_mem[1024]);
        $display("  CQE beat1: %016h", host_mem[1025]);

        // Beat1: bits[31:0]=DW2, bits[63:32]=DW3
        // DW2[15:0]=SQHD(1), DW2[31:16]=SQID(0)
        // DW3[15:0]=CID(1), DW3[16]=P(1), DW3[31:17]=status(0)
        if (host_mem[1025][15:0] != 16'd1) begin
            $display("TEST_FAIL T2_identify_controller: SQHD=%0d expect 1", host_mem[1025][15:0]);
            error_cnt = error_cnt + 1;
        end else if (host_mem[1025][47:32] != 16'd1) begin
            $display("TEST_FAIL T2_identify_controller: CID=%0d expect 1", host_mem[1025][47:32]);
            error_cnt = error_cnt + 1;
        end else if (host_mem[1025][48] != 1'b1) begin
            $display("TEST_FAIL T2_identify_controller: P=%b expect 1", host_mem[1025][48]);
            error_cnt = error_cnt + 1;
        end else begin
            $display("TEST_PASS T2_identify_controller");
        end

        // Report
        if (error_cnt == 0)
            $display("ALL_TESTS_PASS");
        else
            $display("FAIL: %0d test(s) failed", error_cnt);

        $display("SIMULATION_DONE");
        $finish;
    end

endmodule
