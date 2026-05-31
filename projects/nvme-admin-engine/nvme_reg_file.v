`default_nettype none

module nvme_reg_file (
    input  wire         clk_i,
    input  wire         rst_ni,

    // APB interface
    input  wire         psel_i,
    input  wire         penable_i,
    input  wire [15:0]  paddr_i,
    input  wire         pwrite_i,
    input  wire [31:0]  pwdata_i,
    output reg  [31:0]  prdata_o,
    output reg          pready_o,
    output reg          pslverr_o,

    // Configuration outputs
    output wire         ctrl_ready_o,
    output wire [63:0]  admin_sq_base_o,
    output wire [63:0]  admin_cq_base_o,
    output wire [15:0]  admin_sq_depth_o,
    output wire [15:0]  admin_cq_depth_o,

    // Doorbell interface
    output reg          doorbell_valid_o,
    output reg  [7:0]   doorbell_qid_o,
    output reg          doorbell_is_sq_o,
    output reg  [15:0]  doorbell_value_o
);

    // =========================================================================
    // Register state (all _q suffix per skill rule)
    // =========================================================================

    // CC (Controller Configuration) at offset 0x14
    reg [31:0] CC_q;

    // AQA (Admin Queue Attributes) at offset 0x24
    reg [31:0] AQA_q;

    // ASQ (Admin SQ Base Address) at offsets 0x28-0x2F
    reg [31:0] ASQ_lo_q;
    reg [31:0] ASQ_hi_q;

    // ACQ (Admin CQ Base Address) at offsets 0x30-0x37
    reg [31:0] ACQ_lo_q;
    reg [31:0] ACQ_hi_q;

    // =========================================================================
    // PREADY: zero-wait-state APB slave, always ready
    // =========================================================================
    assign pready_o = 1'b1;

    // =========================================================================
    // PSLVERR: error on invalid address
    // =========================================================================
    always @(*) begin
        if (psel_i && penable_i) begin
            if (pwrite_i) begin
                // Write — valid for RW registers and doorbell range
                case (paddr_i[15:0])
                    16'h0014,  // CC
                    16'h0024,  // AQA
                    16'h0028,  // ASQ lo
                    16'h002C,  // ASQ hi
                    16'h0030,  // ACQ lo
                    16'h0034:  // ACQ hi
                        pslverr_o = 1'b0;
                    default:
                        // Doorbell writes (offset >= 0x1000) are valid
                        pslverr_o = (paddr_i[15:0] < 16'h1000);
                endcase
            end else begin
                // Read — valid for any register map address
                case (paddr_i[15:0])
                    16'h0000,  // CAP lo
                    16'h0004,  // CAP hi
                    16'h0008,  // VS
                    16'h0014,  // CC
                    16'h001C,  // CSTS
                    16'h0024,  // AQA
                    16'h0028,  // ASQ lo
                    16'h002C,  // ASQ hi
                    16'h0030,  // ACQ lo
                    16'h0034:  // ACQ hi
                        pslverr_o = 1'b0;
                    default:
                        pslverr_o = 1'b1;
                endcase
            end
        end else begin
            pslverr_o = 1'b0;
        end
    end

    // =========================================================================
    // Read data (combinational decode)
    // =========================================================================
    always @(*) begin
        prdata_o = 32'h0000_0000;
        if (psel_i && penable_i && !pwrite_i) begin
            case (paddr_i[15:0])
                16'h0000: prdata_o = 32'h0000_00FF;  // CAP[31:0]: MQES=255[15:0]
                16'h0004: prdata_o = 32'h0000_0000;  // CAP[63:32]: DSTRD=0[3:0]
                16'h0008: prdata_o = 32'h0001_0400;  // VS: 1.4.0
                16'h0014: prdata_o = CC_q;
                16'h001C: prdata_o = {29'h0, 2'b00, ctrl_ready_o};  // CSTS: RDY=[0]
                16'h0024: prdata_o = AQA_q;
                16'h0028: prdata_o = ASQ_lo_q;
                16'h002C: prdata_o = ASQ_hi_q;
                16'h0030: prdata_o = ACQ_lo_q;
                16'h0034: prdata_o = ACQ_hi_q;
                default: prdata_o = 32'h0000_0000;
            endcase
        end
    end

    // =========================================================================
    // Register writes (clocked, inline APB write condition per skill rule)
    // =========================================================================
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            CC_q     <= 32'h0000_0000;
            AQA_q    <= 32'h0000_0000;
            ASQ_lo_q <= 32'h0000_0000;
            ASQ_hi_q <= 32'h0000_0000;
            ACQ_lo_q <= 32'h0000_0000;
            ACQ_hi_q <= 32'h0000_0000;
        end else begin
            // Inline condition — no separate `assign apb_write` (Icarus B1)
            if (psel_i && penable_i && pwrite_i) begin
                case (paddr_i[15:0])
                    16'h0014: CC_q     <= pwdata_i;
                    16'h0024: AQA_q    <= pwdata_i;
                    16'h0028: ASQ_lo_q <= pwdata_i;
                    16'h002C: ASQ_hi_q <= pwdata_i;
                    16'h0030: ACQ_lo_q <= pwdata_i;
                    16'h0034: ACQ_hi_q <= pwdata_i;
                    // RO registers and doorbell: no state update
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // Doorbell detection (clocked, single-cycle pulse on APB write >= 0x1000)
    // =========================================================================
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            doorbell_valid_o <= 1'b0;
            doorbell_qid_o   <= 8'h0;
            doorbell_is_sq_o <= 1'b0;
            doorbell_value_o <= 16'h0;
        end else begin
            // Inline condition — no separate `assign apb_write` (Icarus B1)
            if (psel_i && penable_i && pwrite_i && (paddr_i >= 16'h1000)) begin
                doorbell_valid_o <= 1'b1;
                // Decode: offset = paddr - 0x1000, stride=4, qid = offset/(2*stride)
                doorbell_qid_o   <= (paddr_i - 16'h1000) >> 3;
                // is_sq: (offset % (2*stride)) < stride → (offset & 7) < 4
                doorbell_is_sq_o <= ((paddr_i - 16'h1000) & 8'h07) < 8'h04;
                doorbell_value_o <= pwdata_i[15:0];
            end else begin
                doorbell_valid_o <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Combinational output assignments
    // =========================================================================

    // Admin queue base addresses (64-bit)
    assign admin_sq_base_o = {ASQ_hi_q, ASQ_lo_q};
    assign admin_cq_base_o = {ACQ_hi_q, ACQ_lo_q};

    // Admin queue depths (AQA stores 0-based sizes; output 1-based)
    assign admin_sq_depth_o = {4'h0, AQA_q[27:16]} + 16'd1;
    assign admin_cq_depth_o = {4'h0, AQA_q[11:0]} + 16'd1;

    // CSTS.RDY: CC.EN && ASQ != 0 && ACQ != 0 && AQA.SQSIZE != 0 && AQA.CQSIZE != 0
    assign ctrl_ready_o = CC_q[0]
                       && (ASQ_lo_q != 32'h0 || ASQ_hi_q != 32'h0)
                       && (ACQ_lo_q != 32'h0 || ACQ_hi_q != 32'h0)
                       && (AQA_q[27:16] != 12'h0)
                       && (AQA_q[11:0]  != 12'h0);

endmodule
