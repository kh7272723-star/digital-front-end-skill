module axi_lite_regs #(
    parameter ADDR_W = 4,
    parameter DATA_W = 32
) (
    input  wire              clk_i,
    input  wire              rst_i,

    input  wire              awvalid_i,
    output wire              awready_o,
    input  wire [ADDR_W-1:0] awaddr_i,

    input  wire              wvalid_i,
    output wire              wready_o,
    input  wire [DATA_W-1:0] wdata_i,
    input  wire [3:0]        wstrb_i,

    output reg               bvalid_o,
    input  wire              bready_i,
    output reg  [1:0]        bresp_o,

    input  wire              arvalid_i,
    output wire              arready_o,
    input  wire [ADDR_W-1:0] araddr_i,

    output reg               rvalid_o,
    input  wire              rready_i,
    output reg  [DATA_W-1:0] rdata_o,
    output reg  [1:0]        rresp_o,

    output wire [DATA_W-1:0] reg0_o,
    output wire [DATA_W-1:0] reg1_o
);

    localparam RESP_OKAY  = 2'b00;
    localparam RESP_ERROR = 2'b10;

    reg [DATA_W-1:0] reg0_q;
    reg [DATA_W-1:0] reg1_q;

    reg aw_hold_valid_q;
    reg [ADDR_W-1:0] awaddr_q;
    reg w_hold_valid_q;
    reg [DATA_W-1:0] wdata_q;
    reg [3:0] wstrb_q;

    wire aw_accept;
    wire w_accept;
    wire ar_accept;
    wire [ADDR_W-1:0] write_addr;
    wire [DATA_W-1:0] write_data;
    wire [3:0] write_strb;
    wire write_ready_to_execute;
    wire b_accept;
    wire r_accept;

    assign awready_o = (!aw_hold_valid_q) && (!bvalid_o);
    assign wready_o = (!w_hold_valid_q) && (!bvalid_o);
    assign arready_o = !rvalid_o;

    assign aw_accept = awvalid_i && awready_o;
    assign w_accept = wvalid_i && wready_o;
    assign ar_accept = arvalid_i && arready_o;
    assign b_accept = bvalid_o && bready_i;
    assign r_accept = rvalid_o && rready_i;

    assign write_addr = aw_accept ? awaddr_i : awaddr_q;
    assign write_data = w_accept ? wdata_i : wdata_q;
    assign write_strb = w_accept ? wstrb_i : wstrb_q;
    assign write_ready_to_execute = (!bvalid_o) &&
                                    (aw_hold_valid_q || aw_accept) &&
                                    (w_hold_valid_q || w_accept);

    assign reg0_o = reg0_q;
    assign reg1_o = reg1_q;

    function [DATA_W-1:0] apply_wstrb;
        input [DATA_W-1:0] old_value;
        input [DATA_W-1:0] new_value;
        input [3:0] strb;
        begin
            apply_wstrb = old_value;
            if (strb[0]) begin
                apply_wstrb[7:0] = new_value[7:0];
            end
            if (strb[1]) begin
                apply_wstrb[15:8] = new_value[15:8];
            end
            if (strb[2]) begin
                apply_wstrb[23:16] = new_value[23:16];
            end
            if (strb[3]) begin
                apply_wstrb[31:24] = new_value[31:24];
            end
        end
    endfunction

    always @(posedge clk_i) begin
        if (rst_i) begin
            reg0_q <= {DATA_W{1'b0}};
            reg1_q <= {DATA_W{1'b0}};
            aw_hold_valid_q <= 1'b0;
            awaddr_q <= {ADDR_W{1'b0}};
            w_hold_valid_q <= 1'b0;
            wdata_q <= {DATA_W{1'b0}};
            wstrb_q <= 4'b0000;
            bvalid_o <= 1'b0;
            bresp_o <= RESP_OKAY;
            rvalid_o <= 1'b0;
            rdata_o <= {DATA_W{1'b0}};
            rresp_o <= RESP_OKAY;
        end else begin
            if (b_accept) begin
                bvalid_o <= 1'b0;
            end

            if (write_ready_to_execute) begin
                case (write_addr[3:2])
                    2'b00: begin
                        reg0_q <= apply_wstrb(reg0_q, write_data, write_strb);
                        bresp_o <= RESP_OKAY;
                    end
                    2'b01: begin
                        reg1_q <= apply_wstrb(reg1_q, write_data, write_strb);
                        bresp_o <= RESP_OKAY;
                    end
                    default: begin
                        bresp_o <= RESP_ERROR;
                    end
                endcase
                bvalid_o <= 1'b1;
                aw_hold_valid_q <= 1'b0;
                w_hold_valid_q <= 1'b0;
            end else begin
                if (aw_accept) begin
                    aw_hold_valid_q <= 1'b1;
                    awaddr_q <= awaddr_i;
                end
                if (w_accept) begin
                    w_hold_valid_q <= 1'b1;
                    wdata_q <= wdata_i;
                    wstrb_q <= wstrb_i;
                end
            end

            if (r_accept) begin
                rvalid_o <= 1'b0;
            end

            if (ar_accept) begin
                rvalid_o <= 1'b1;
                case (araddr_i[3:2])
                    2'b00: begin
                        rdata_o <= reg0_q;
                        rresp_o <= RESP_OKAY;
                    end
                    2'b01: begin
                        rdata_o <= reg1_q;
                        rresp_o <= RESP_OKAY;
                    end
                    default: begin
                        rdata_o <= {DATA_W{1'b0}};
                        rresp_o <= RESP_ERROR;
                    end
                endcase
            end
        end
    end

endmodule
