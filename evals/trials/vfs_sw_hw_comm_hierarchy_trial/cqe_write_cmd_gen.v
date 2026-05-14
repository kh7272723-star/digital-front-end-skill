module cqe_write_cmd_gen #(
    parameter ADDR_W = 32,
    parameter PTR_W = 2,
    parameter COUNT_W = 3,
    parameter BYTE_W = 16,
    parameter ENTRY_BYTES = 64
) (
    input  wire                  clk_i,
    input  wire                  rst_i,

    input  wire [ADDR_W-1:0]     cq_base_addr_i,
    input  wire                  cq_head_db_wr_en_i,
    input  wire [PTR_W-1:0]      cq_head_db_i,

    output wire [PTR_W-1:0]      cq_head_o,
    output wire [PTR_W-1:0]      cq_tail_o,
    output wire [COUNT_W-1:0]    cq_pending_o,
    output wire                  cq_full_o,

    input  wire                  cpl_valid_i,
    output wire                  cpl_ready_o,
    input  wire [BYTE_W-1:0]     cpl_bytes_i,

    output wire                  cmd_valid_o,
    input  wire                  cmd_ready_i,
    output wire [ADDR_W-1:0]     cmd_addr_o,
    output wire [COUNT_W-1:0]    cmd_len_o,
    output wire                  cmd_phase_o,
    input  wire                  write_done_i,

    output wire                  cpl_commit_valid_o,
    output wire [BYTE_W-1:0]     cpl_commit_bytes_o
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_ISSUE = 2'd1;
    localparam [1:0] S_WAIT_DONE = 2'd2;

    localparam [COUNT_W-1:0] DEPTH_COUNT = (1 << PTR_W);
    localparam [COUNT_W-1:0] ONE_COUNT = {{(COUNT_W-1){1'b0}}, 1'b1};

    reg [1:0] state_q;
    reg [1:0] state_d;

    reg [PTR_W-1:0] cq_head_q;
    reg [PTR_W-1:0] cq_head_d;
    reg [PTR_W-1:0] cq_tail_q;
    reg [PTR_W-1:0] cq_tail_d;
    reg             cq_phase_q;
    reg             cq_phase_d;
    reg [BYTE_W-1:0] cpl_bytes_q;
    reg [BYTE_W-1:0] cpl_bytes_d;
    reg [ADDR_W-1:0] cmd_addr_q;
    reg [ADDR_W-1:0] cmd_addr_d;
    reg [COUNT_W-1:0] cmd_len_q;
    reg [COUNT_W-1:0] cmd_len_d;
    reg             cmd_phase_q;
    reg             cmd_phase_d;
    reg             cpl_commit_valid_q;
    reg             cpl_commit_valid_d;
    reg [BYTE_W-1:0] cpl_commit_bytes_q;
    reg [BYTE_W-1:0] cpl_commit_bytes_d;

    wire accept_cpl;
    wire accept_cmd;
    wire [COUNT_W-1:0] pending_current;
    wire [PTR_W-1:0] cq_tail_next;

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

    function [ADDR_W-1:0] entry_addr;
        input [ADDR_W-1:0] base_addr;
        input [PTR_W-1:0] ptr;
        begin
            entry_addr = base_addr + (ptr * ENTRY_BYTES);
        end
    endfunction

    assign pending_current = ring_distance(cq_head_q, cq_tail_q);
    assign cq_tail_next = ptr_add(cq_tail_q, ONE_COUNT);
    assign cq_full_o = (cq_tail_next == cq_head_q);
    assign cpl_ready_o = (state_q == S_IDLE) && !cq_full_o;
    assign accept_cpl = cpl_valid_i && cpl_ready_o;

    assign cmd_valid_o = (state_q == S_ISSUE);
    assign cmd_addr_o = cmd_addr_q;
    assign cmd_len_o = cmd_len_q;
    assign cmd_phase_o = cmd_phase_q;
    assign accept_cmd = cmd_valid_o && cmd_ready_i;

    assign cq_head_o = cq_head_q;
    assign cq_tail_o = cq_tail_q;
    assign cq_pending_o = pending_current;
    assign cpl_commit_valid_o = cpl_commit_valid_q;
    assign cpl_commit_bytes_o = cpl_commit_bytes_q;

    always @(*) begin
        state_d = state_q;
        cq_head_d = cq_head_q;
        cq_tail_d = cq_tail_q;
        cq_phase_d = cq_phase_q;
        cpl_bytes_d = cpl_bytes_q;
        cmd_addr_d = cmd_addr_q;
        cmd_len_d = cmd_len_q;
        cmd_phase_d = cmd_phase_q;
        cpl_commit_valid_d = 1'b0;
        cpl_commit_bytes_d = {BYTE_W{1'b0}};

        if (cq_head_db_wr_en_i) begin
            cq_head_d = cq_head_db_i;
        end

        case (state_q)
            S_IDLE: begin
                if (accept_cpl) begin
                    cpl_bytes_d = cpl_bytes_i;
                    cmd_addr_d = entry_addr(cq_base_addr_i, cq_tail_q);
                    cmd_len_d = ONE_COUNT;
                    cmd_phase_d = cq_phase_q;
                    state_d = S_ISSUE;
                end
            end
            S_ISSUE: begin
                if (accept_cmd) begin
                    state_d = S_WAIT_DONE;
                end
            end
            S_WAIT_DONE: begin
                if (write_done_i) begin
                    cq_tail_d = cq_tail_next;
                    if (cq_tail_q == (DEPTH_COUNT - ONE_COUNT)) begin
                        cq_phase_d = !cq_phase_q;
                    end
                    cpl_commit_valid_d = 1'b1;
                    cpl_commit_bytes_d = cpl_bytes_q;
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
            cq_head_q <= {PTR_W{1'b0}};
            cq_tail_q <= {PTR_W{1'b0}};
            cq_phase_q <= 1'b1;
            cpl_bytes_q <= {BYTE_W{1'b0}};
            cmd_addr_q <= {ADDR_W{1'b0}};
            cmd_len_q <= {COUNT_W{1'b0}};
            cmd_phase_q <= 1'b0;
            cpl_commit_valid_q <= 1'b0;
            cpl_commit_bytes_q <= {BYTE_W{1'b0}};
        end else begin
            state_q <= state_d;
            cq_head_q <= cq_head_d;
            cq_tail_q <= cq_tail_d;
            cq_phase_q <= cq_phase_d;
            cpl_bytes_q <= cpl_bytes_d;
            cmd_addr_q <= cmd_addr_d;
            cmd_len_q <= cmd_len_d;
            cmd_phase_q <= cmd_phase_d;
            cpl_commit_valid_q <= cpl_commit_valid_d;
            cpl_commit_bytes_q <= cpl_commit_bytes_d;
        end
    end

endmodule
