module ahb_lite_regs #(
    parameter ADDR_W = 4,
    parameter DATA_W = 32
) (
    input  wire              clk_i,
    input  wire              rst_i,
    input  wire              wait_i,

    input  wire              hsel_i,
    input  wire              hready_i,
    input  wire [1:0]        htrans_i,
    input  wire              hwrite_i,
    input  wire [2:0]        hsize_i,
    input  wire [ADDR_W-1:0] haddr_i,
    input  wire [DATA_W-1:0] hwdata_i,

    output wire              hready_o,
    output wire              hresp_o,
    output reg  [DATA_W-1:0] hrdata_o,

    output wire [DATA_W-1:0] reg0_o,
    output wire [DATA_W-1:0] reg1_o
);

    reg [DATA_W-1:0] reg0_q;
    reg [DATA_W-1:0] reg1_q;

    reg data_valid_q;
    reg [ADDR_W-1:0] data_addr_q;
    reg data_write_q;
    reg [2:0] data_size_q;
    reg data_error_q;
    reg wait_q;

    wire active_transfer;
    wire accept_addr;
    wire complete_data;
    wire valid_addr_phase;
    wire valid_addr_data;
    wire valid_size_data;

    assign active_transfer = hsel_i && htrans_i[1];
    assign hready_o = !wait_q;
    assign accept_addr = active_transfer && hready_i && hready_o;
    assign complete_data = data_valid_q && hready_o;

    assign valid_addr_phase = (haddr_i[3:2] == 2'b00) || (haddr_i[3:2] == 2'b01);
    assign valid_addr_data = (data_addr_q[3:2] == 2'b00) || (data_addr_q[3:2] == 2'b01);
    assign valid_size_data = (data_size_q == 3'b010);
    assign hresp_o = complete_data && data_error_q;

    assign reg0_o = reg0_q;
    assign reg1_o = reg1_q;

    always @(*) begin
        if (data_valid_q) begin
            case (data_addr_q[3:2])
                2'b00: hrdata_o = reg0_q;
                2'b01: hrdata_o = reg1_q;
                default: hrdata_o = {DATA_W{1'b0}};
            endcase
        end else begin
            hrdata_o = {DATA_W{1'b0}};
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            reg0_q <= {DATA_W{1'b0}};
            reg1_q <= {DATA_W{1'b0}};
            data_valid_q <= 1'b0;
            data_addr_q <= {ADDR_W{1'b0}};
            data_write_q <= 1'b0;
            data_size_q <= 3'b010;
            data_error_q <= 1'b0;
            wait_q <= 1'b0;
        end else begin
            if (wait_q) begin
                wait_q <= 1'b0;
            end

            if (complete_data && data_write_q && !data_error_q &&
                valid_addr_data && valid_size_data) begin
                case (data_addr_q[3:2])
                    2'b00: reg0_q <= hwdata_i;
                    2'b01: reg1_q <= hwdata_i;
                    default: begin
                    end
                endcase
            end

            if (complete_data) begin
                data_valid_q <= 1'b0;
            end

            if (accept_addr) begin
                data_valid_q <= 1'b1;
                data_addr_q <= haddr_i;
                data_write_q <= hwrite_i;
                data_size_q <= hsize_i;
                data_error_q <= (!valid_addr_phase) || (hsize_i != 3'b010);
                wait_q <= wait_i;
            end
        end
    end

endmodule
