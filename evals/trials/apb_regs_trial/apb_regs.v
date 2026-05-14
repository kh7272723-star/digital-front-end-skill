module apb_regs #(
    parameter ADDR_W = 4,
    parameter DATA_W = 32
) (
    input  wire              clk_i,
    input  wire              rst_i,
    input  wire              wait_i,

    input  wire              psel_i,
    input  wire              penable_i,
    input  wire              pwrite_i,
    input  wire [ADDR_W-1:0] paddr_i,
    input  wire [DATA_W-1:0] pwdata_i,
    input  wire [3:0]        pstrb_i,
    output wire              pready_o,
    output reg  [DATA_W-1:0] prdata_o,
    output wire              pslverr_o,

    output wire [DATA_W-1:0] reg0_o,
    output wire [DATA_W-1:0] reg1_o
);

    reg [DATA_W-1:0] reg0_q;
    reg [DATA_W-1:0] reg1_q;

    wire access_phase;
    wire completed_access;
    wire valid_addr;
    wire write_access;

    assign access_phase = psel_i && penable_i;
    assign pready_o = access_phase && !wait_i;
    assign completed_access = access_phase && pready_o;
    assign valid_addr = (paddr_i[3:2] == 2'b00) || (paddr_i[3:2] == 2'b01);
    assign write_access = completed_access && pwrite_i;
    assign pslverr_o = completed_access && !valid_addr;

    assign reg0_o = reg0_q;
    assign reg1_o = reg1_q;

    function [DATA_W-1:0] apply_pstrb;
        input [DATA_W-1:0] old_value;
        input [DATA_W-1:0] new_value;
        input [3:0] strb;
        begin
            apply_pstrb = old_value;
            if (strb[0]) begin
                apply_pstrb[7:0] = new_value[7:0];
            end
            if (strb[1]) begin
                apply_pstrb[15:8] = new_value[15:8];
            end
            if (strb[2]) begin
                apply_pstrb[23:16] = new_value[23:16];
            end
            if (strb[3]) begin
                apply_pstrb[31:24] = new_value[31:24];
            end
        end
    endfunction

    always @(*) begin
        case (paddr_i[3:2])
            2'b00: prdata_o = reg0_q;
            2'b01: prdata_o = reg1_q;
            default: prdata_o = {DATA_W{1'b0}};
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            reg0_q <= {DATA_W{1'b0}};
            reg1_q <= {DATA_W{1'b0}};
        end else if (write_access && valid_addr) begin
            case (paddr_i[3:2])
                2'b00: reg0_q <= apply_pstrb(reg0_q, pwdata_i, pstrb_i);
                2'b01: reg1_q <= apply_pstrb(reg1_q, pwdata_i, pstrb_i);
                default: begin
                end
            endcase
        end
    end

endmodule
