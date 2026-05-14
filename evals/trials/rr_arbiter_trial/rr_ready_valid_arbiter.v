module rr_ready_valid_arbiter #(
    parameter DATA_W = 8
) (
    input  wire                  clk_i,
    input  wire                  rst_i,

    input  wire [3:0]            valid_i,
    output reg  [3:0]            ready_o,
    input  wire [(4*DATA_W)-1:0] data_i,

    output reg                   valid_o,
    input  wire                  ready_i,
    output reg  [DATA_W-1:0]     data_o,
    output reg  [1:0]            grant_o
);

    reg [1:0] rr_ptr_q;

    wire output_can_load;
    wire any_valid;
    wire grant_valid;
    wire [1:0] grant_sel;
    wire accept_input;
    wire accept_output;

    assign output_can_load = (!valid_o) || ready_i;
    assign any_valid = |valid_i;
    assign grant_valid = any_valid;
    assign grant_sel = pick_grant(valid_i, rr_ptr_q);
    assign accept_input = output_can_load && grant_valid;
    assign accept_output = valid_o && ready_i;

    function [1:0] pick_grant;
        input [3:0] valid;
        input [1:0] start;
        begin
            case (start)
                2'd0: begin
                    if (valid[0]) begin
                        pick_grant = 2'd0;
                    end else if (valid[1]) begin
                        pick_grant = 2'd1;
                    end else if (valid[2]) begin
                        pick_grant = 2'd2;
                    end else begin
                        pick_grant = 2'd3;
                    end
                end
                2'd1: begin
                    if (valid[1]) begin
                        pick_grant = 2'd1;
                    end else if (valid[2]) begin
                        pick_grant = 2'd2;
                    end else if (valid[3]) begin
                        pick_grant = 2'd3;
                    end else begin
                        pick_grant = 2'd0;
                    end
                end
                2'd2: begin
                    if (valid[2]) begin
                        pick_grant = 2'd2;
                    end else if (valid[3]) begin
                        pick_grant = 2'd3;
                    end else if (valid[0]) begin
                        pick_grant = 2'd0;
                    end else begin
                        pick_grant = 2'd1;
                    end
                end
                default: begin
                    if (valid[3]) begin
                        pick_grant = 2'd3;
                    end else if (valid[0]) begin
                        pick_grant = 2'd0;
                    end else if (valid[1]) begin
                        pick_grant = 2'd1;
                    end else begin
                        pick_grant = 2'd2;
                    end
                end
            endcase
        end
    endfunction

    function [DATA_W-1:0] pick_data;
        input [(4*DATA_W)-1:0] bus;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: pick_data = bus[(0*DATA_W) +: DATA_W];
                2'd1: pick_data = bus[(1*DATA_W) +: DATA_W];
                2'd2: pick_data = bus[(2*DATA_W) +: DATA_W];
                default: pick_data = bus[(3*DATA_W) +: DATA_W];
            endcase
        end
    endfunction

    always @(*) begin
        ready_o = 4'b0000;
        if (accept_input) begin
            case (grant_sel)
                2'd0: ready_o = 4'b0001;
                2'd1: ready_o = 4'b0010;
                2'd2: ready_o = 4'b0100;
                default: ready_o = 4'b1000;
            endcase
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            rr_ptr_q <= 2'd0;
            valid_o <= 1'b0;
            data_o <= {DATA_W{1'b0}};
            grant_o <= 2'd0;
        end else if (output_can_load) begin
            if (grant_valid) begin
                valid_o <= 1'b1;
                data_o <= pick_data(data_i, grant_sel);
                grant_o <= grant_sel;
                rr_ptr_q <= grant_sel + 2'd1;
            end else begin
                valid_o <= 1'b0;
            end
        end
    end

endmodule
