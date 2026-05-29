`default_nettype none

// Minimal DMA engine: reads words from source memory, writes to destination.
// Config interface: direct register writes (simplified, not full AXI-Lite).
// Two-process FSM, single-beat transfers (no burst).
module dma_engine #(
    parameter ADDR_W = 8,
    parameter DATA_W = 32
)(
    input  wire               clk_i,
    input  wire               rst_i,
    // Config slave
    input  wire               cfg_wr_en_i,
    input  wire [3:0]         cfg_addr_i,
    input  wire [DATA_W-1:0]  cfg_wdata_i,
    output reg  [DATA_W-1:0]  cfg_rdata_o,
    // Source memory interface
    output reg                src_rd_en_o,
    output reg  [ADDR_W-1:0]  src_rd_addr_o,
    input  wire [DATA_W-1:0]  src_rd_data_i,
    // Dest memory interface
    output reg                dst_wr_en_o,
    output reg  [ADDR_W-1:0]  dst_wr_addr_o,
    output reg  [DATA_W-1:0]  dst_wr_data_o
);

    // ---------------------------------------------------------------
    // Config registers
    // ---------------------------------------------------------------
    reg [ADDR_W-1:0] src_addr_q;
    reg [ADDR_W-1:0] dst_addr_q;
    reg [7:0]        length_q;
    reg              start_q;
    reg              done_q;
    reg              error_q;

    // Config write
    always @(posedge clk_i) begin
        if (rst_i) begin
            src_addr_q <= {ADDR_W{1'b0}};
            dst_addr_q <= {ADDR_W{1'b0}};
            length_q   <= 8'd0;
            start_q    <= 1'b0;
        end else if (cfg_wr_en_i) begin
            case (cfg_addr_i)
                4'h0: src_addr_q <= cfg_wdata_i[ADDR_W-1:0];
                4'h4: dst_addr_q <= cfg_wdata_i[ADDR_W-1:0];
                4'h8: length_q   <= cfg_wdata_i[7:0];
                4'hC: start_q    <= cfg_wdata_i[0];
            endcase
        end else begin
            start_q <= 1'b0;
        end
    end

    // Config read (combinational)
    always @(*) begin
        cfg_rdata_o = {DATA_W{1'b0}};
        case (cfg_addr_i)
            4'h0: cfg_rdata_o = {{(DATA_W-ADDR_W){1'b0}}, src_addr_q};
            4'h4: cfg_rdata_o = {{(DATA_W-ADDR_W){1'b0}}, dst_addr_q};
            4'h8: cfg_rdata_o = {{(DATA_W-8){1'b0}}, length_q};
            4'hC: cfg_rdata_o = {{(DATA_W-2){1'b0}}, done_q, error_q};
        endcase
    end

    // ---------------------------------------------------------------
    // FSM state
    // ---------------------------------------------------------------
    localparam S_IDLE       = 3'd0;
    localparam S_READ       = 3'd1;
    localparam S_READ_WAIT  = 3'd2;
    localparam S_WRITE      = 3'd3;
    localparam S_WRITE_WAIT = 3'd4;
    localparam S_DONE       = 3'd5;

    reg [2:0]        state_q, state_d;
    reg [ADDR_W-1:0] cur_src_q, cur_src_d;
    reg [ADDR_W-1:0] cur_dst_q, cur_dst_d;
    reg [7:0]        rem_q, rem_d;
    reg [DATA_W-1:0] data_buf_q, data_buf_d;
    reg              done_d, error_d;

    // State register
    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q    <= S_IDLE;
            cur_src_q  <= {ADDR_W{1'b0}};
            cur_dst_q  <= {ADDR_W{1'b0}};
            rem_q      <= 8'd0;
            data_buf_q <= {DATA_W{1'b0}};
            done_q     <= 1'b0;
            error_q    <= 1'b0;
        end else begin
            state_q    <= state_d;
            cur_src_q  <= cur_src_d;
            cur_dst_q  <= cur_dst_d;
            rem_q      <= rem_d;
            data_buf_q <= data_buf_d;
            done_q     <= done_d;
            error_q    <= error_d;
        end
    end

    // ---------------------------------------------------------------
    // FSM + datapath (combinational)
    // ---------------------------------------------------------------
    always @(*) begin
        state_d      = state_q;
        cur_src_d    = cur_src_q;
        cur_dst_d    = cur_dst_q;
        rem_d        = rem_q;
        data_buf_d   = data_buf_q;
        done_d       = 1'b0;
        error_d      = 1'b0;
        src_rd_en_o  = 1'b0;
        src_rd_addr_o = cur_src_q;
        dst_wr_en_o  = 1'b0;
        dst_wr_addr_o = cur_dst_q;
        dst_wr_data_o = data_buf_q;

        case (state_q)
            S_IDLE: begin
                done_d = done_q; // hold done until new transfer starts
                if (start_q && length_q > 0) begin
                    state_d   = S_READ;
                    cur_src_d = src_addr_q;
                    cur_dst_d = dst_addr_q;
                    rem_d     = length_q;
                    done_d    = 1'b0; // clear done on new start
                end else if (start_q) begin
                    error_d = 1'b1;
                end
            end

            S_READ: begin
                src_rd_en_o   = 1'b1;
                src_rd_addr_o = cur_src_q;
                state_d       = S_READ_WAIT;
            end

            S_READ_WAIT: begin
                data_buf_d = src_rd_data_i;
                state_d    = S_WRITE;
            end

            S_WRITE: begin
                dst_wr_en_o   = 1'b1;
                dst_wr_addr_o = cur_dst_q;
                dst_wr_data_o = data_buf_q;
                state_d       = S_WRITE_WAIT;
            end

            S_WRITE_WAIT: begin
                cur_src_d = cur_src_q + 1;
                cur_dst_d = cur_dst_q + 1;
                rem_d     = rem_q - 1;
                if (rem_q == 8'd1)
                    state_d = S_DONE;
                else
                    state_d = S_READ;
            end

            S_DONE: begin
                done_d  = 1'b1;
                state_d = S_IDLE;
            end

            default: state_d = S_IDLE;
        endcase
    end

endmodule
`default_nettype wire
