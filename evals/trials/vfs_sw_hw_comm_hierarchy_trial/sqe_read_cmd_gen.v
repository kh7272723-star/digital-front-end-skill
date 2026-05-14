module sqe_read_cmd_gen #(
    parameter ADDR_W = 32,
    parameter PTR_W = 2,
    parameter COUNT_W = 3,
    parameter ENTRY_BYTES = 64,
    parameter MAX_BURST_ENTRIES = 2
) (
    input  wire                  clk_i,
    input  wire                  rst_i,

    input  wire [ADDR_W-1:0]     sq_base_addr_i,
    input  wire                  sq_tail_db_wr_en_i,
    input  wire [PTR_W-1:0]      sq_tail_db_i,

    output wire [PTR_W-1:0]      sq_head_o,
    output wire [PTR_W-1:0]      sq_tail_o,
    output wire [COUNT_W-1:0]    sq_pending_o,

    output wire                  cmd_valid_o,
    input  wire                  cmd_ready_i,
    output wire [ADDR_W-1:0]     cmd_addr_o,
    output wire [COUNT_W-1:0]    cmd_len_o
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_ISSUE = 2'd1;

    localparam [COUNT_W-1:0] DEPTH_COUNT = (1 << PTR_W);
    localparam [COUNT_W-1:0] MAX_BURST_COUNT = MAX_BURST_ENTRIES;

    reg [1:0] state_q;
    reg [1:0] state_d;

    reg [PTR_W-1:0] sq_head_q;
    reg [PTR_W-1:0] sq_head_d;
    reg [PTR_W-1:0] sq_tail_q;
    reg [PTR_W-1:0] sq_tail_d;
    reg [ADDR_W-1:0] cmd_addr_q;
    reg [ADDR_W-1:0] cmd_addr_d;
    reg [COUNT_W-1:0] cmd_len_q;
    reg [COUNT_W-1:0] cmd_len_d;

    wire accept_cmd;
    wire [COUNT_W-1:0] pending_current;
    wire [COUNT_W-1:0] until_wrap;
    wire [COUNT_W-1:0] boundary_len;
    wire [COUNT_W-1:0] next_len;

    function [COUNT_W-1:0] ring_distance;
        input [PTR_W-1:0] head;
        input [PTR_W-1:0] tail;
        begin
            if (tail >= head) begin
                ring_distance = tail - head;
            end else begin
                ring_distance = DEPTH_COUNT - head + tail;
            end
        end
    endfunction

    function [PTR_W-1:0] ptr_add;
        input [PTR_W-1:0] ptr;
        input [COUNT_W-1:0] inc;
        reg [COUNT_W:0] sum;
        begin
            sum = ptr + inc;
            if (sum >= DEPTH_COUNT) begin
                sum = sum - DEPTH_COUNT;
            end
            ptr_add = sum[PTR_W-1:0];
        end
    endfunction

    function [COUNT_W-1:0] min_count;
        input [COUNT_W-1:0] a;
        input [COUNT_W-1:0] b;
        begin
            min_count = (a < b) ? a : b;
        end
    endfunction

    function [ADDR_W-1:0] entry_addr;
        input [ADDR_W-1:0] base_addr;
        input [PTR_W-1:0] ptr;
        begin
            entry_addr = base_addr + (ptr * ENTRY_BYTES);
        end
    endfunction

    assign cmd_valid_o = (state_q == S_ISSUE);
    assign cmd_addr_o = cmd_addr_q;
    assign cmd_len_o = cmd_len_q;
    assign accept_cmd = cmd_valid_o && cmd_ready_i;

    assign pending_current = ring_distance(sq_head_q, sq_tail_q);
    assign until_wrap = DEPTH_COUNT - sq_head_q;
    assign boundary_len = min_count(pending_current, until_wrap);
    assign next_len = min_count(boundary_len, MAX_BURST_COUNT);

    assign sq_head_o = sq_head_q;
    assign sq_tail_o = sq_tail_q;
    assign sq_pending_o = pending_current;

    always @(*) begin
        state_d = state_q;
        sq_head_d = sq_head_q;
        sq_tail_d = sq_tail_q;
        cmd_addr_d = cmd_addr_q;
        cmd_len_d = cmd_len_q;

        if (sq_tail_db_wr_en_i) begin
            sq_tail_d = sq_tail_db_i;
        end

        case (state_q)
            S_IDLE: begin
                if (pending_current != {COUNT_W{1'b0}}) begin
                    cmd_addr_d = entry_addr(sq_base_addr_i, sq_head_q);
                    cmd_len_d = next_len;
                    state_d = S_ISSUE;
                end
            end
            S_ISSUE: begin
                if (accept_cmd) begin
                    sq_head_d = ptr_add(sq_head_q, cmd_len_q);
                    state_d = S_IDLE;
                end
            end
            default: begin
                state_d = S_IDLE;
            end
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= S_IDLE;
            sq_head_q <= {PTR_W{1'b0}};
            sq_tail_q <= {PTR_W{1'b0}};
            cmd_addr_q <= {ADDR_W{1'b0}};
            cmd_len_q <= {COUNT_W{1'b0}};
        end else begin
            state_q <= state_d;
            sq_head_q <= sq_head_d;
            sq_tail_q <= sq_tail_d;
            cmd_addr_q <= cmd_addr_d;
            cmd_len_q <= cmd_len_d;
        end
    end

endmodule
