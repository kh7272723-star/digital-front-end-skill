module vfs_sw_hw_comm_slice #(
    parameter ADDR_W = 32,
    parameter PTR_W = 2,
    parameter COUNT_W = 3,
    parameter BYTE_W = 16,
    parameter TIMEOUT_W = 4,
    parameter ENTRY_BYTES = 64,
    parameter MAX_BURST_ENTRIES = 2
) (
    input  wire                   clk_i,
    input  wire                   rst_i,

    input  wire [ADDR_W-1:0]      sq_base_addr_i,
    input  wire                   sq_tail_db_wr_en_i,
    input  wire [PTR_W-1:0]       sq_tail_db_i,
    output wire [PTR_W-1:0]       sq_head_o,
    output wire [COUNT_W-1:0]     sq_pending_o,

    output reg                    sq_cmd_valid_o,
    input  wire                   sq_cmd_ready_i,
    output reg  [ADDR_W-1:0]      sq_cmd_addr_o,
    output reg  [COUNT_W-1:0]     sq_cmd_len_o,

    input  wire [ADDR_W-1:0]      cq_base_addr_i,
    input  wire                   cq_head_db_wr_en_i,
    input  wire [PTR_W-1:0]       cq_head_db_i,
    output wire [PTR_W-1:0]       cq_tail_o,
    output wire [COUNT_W-1:0]     cq_pending_o,
    output wire                   cq_full_o,

    input  wire                   cpl_valid_i,
    output wire                   cpl_ready_o,
    input  wire [BYTE_W-1:0]      cpl_bytes_i,

    output reg                    cq_cmd_valid_o,
    input  wire                   cq_cmd_ready_i,
    output reg  [ADDR_W-1:0]      cq_cmd_addr_o,
    output reg  [COUNT_W-1:0]     cq_cmd_len_o,
    output reg                    cq_cmd_phase_o,
    input  wire                   cq_write_done_i,

    input  wire [COUNT_W-1:0]     irq_cqe_threshold_i,
    input  wire [BYTE_W-1:0]      irq_byte_threshold_i,
    input  wire [TIMEOUT_W-1:0]   irq_timeout_threshold_i,
    output reg                    irq_pulse_o,
    output reg  [1:0]             irq_reason_o
);

    localparam [1:0] CQ_IDLE = 2'd0;
    localparam [1:0] CQ_ISSUE = 2'd1;
    localparam [1:0] CQ_WAIT_DONE = 2'd2;

    localparam [1:0] IRQ_REASON_NONE = 2'd0;
    localparam [1:0] IRQ_REASON_COUNT = 2'd1;
    localparam [1:0] IRQ_REASON_BYTES = 2'd2;
    localparam [1:0] IRQ_REASON_TIMEOUT = 2'd3;

    localparam [COUNT_W-1:0] DEPTH_COUNT = (1 << PTR_W);
    localparam [COUNT_W-1:0] ONE_COUNT = {{(COUNT_W-1){1'b0}}, 1'b1};
    localparam [COUNT_W-1:0] MAX_BURST_COUNT = MAX_BURST_ENTRIES;

    reg [PTR_W-1:0] sq_head_q;
    reg [PTR_W-1:0] sq_tail_q;

    reg [PTR_W-1:0] cq_head_q;
    reg [PTR_W-1:0] cq_tail_q;
    reg             cq_phase_q;
    reg [1:0]       cq_state_q;
    reg [BYTE_W-1:0] cpl_bytes_q;

    reg [COUNT_W-1:0] irq_cqe_count_q;
    reg [BYTE_W-1:0] irq_byte_count_q;
    reg [TIMEOUT_W-1:0] irq_timer_q;

    wire accept_sq_cmd;
    wire accept_cpl;
    wire accept_cq_cmd;
    wire cqe_commit;

    wire [COUNT_W-1:0] sq_pending_current;
    wire [COUNT_W-1:0] sq_until_wrap;
    wire [COUNT_W-1:0] sq_boundary_len;
    wire [COUNT_W-1:0] sq_next_len;

    wire [COUNT_W-1:0] cq_pending_current;
    wire [PTR_W-1:0] cq_tail_next;

    wire [COUNT_W-1:0] irq_count_after_commit;
    wire [BYTE_W-1:0] irq_bytes_after_commit;
    wire irq_count_threshold_hit;
    wire irq_byte_threshold_hit;
    wire irq_timeout_threshold_hit;

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

    assign accept_sq_cmd = sq_cmd_valid_o && sq_cmd_ready_i;
    assign accept_cpl = cpl_valid_i && cpl_ready_o;
    assign accept_cq_cmd = cq_cmd_valid_o && cq_cmd_ready_i;
    assign cqe_commit = (cq_state_q == CQ_WAIT_DONE) && cq_write_done_i;

    assign sq_pending_current = ring_distance(sq_head_q, sq_tail_q);
    assign sq_until_wrap = DEPTH_COUNT - sq_head_q;
    assign sq_boundary_len = min_count(sq_pending_current, sq_until_wrap);
    assign sq_next_len = min_count(sq_boundary_len, MAX_BURST_COUNT);

    assign cq_pending_current = ring_distance(cq_head_q, cq_tail_q);
    assign cq_tail_next = ptr_add(cq_tail_q, ONE_COUNT);
    assign cq_full_o = (cq_tail_next == cq_head_q);
    assign cpl_ready_o = (cq_state_q == CQ_IDLE) && !cq_full_o;

    assign sq_head_o = sq_head_q;
    assign sq_pending_o = sq_pending_current;
    assign cq_tail_o = cq_tail_q;
    assign cq_pending_o = cq_pending_current;

    assign irq_count_after_commit = irq_cqe_count_q + ONE_COUNT;
    assign irq_bytes_after_commit = irq_byte_count_q + cpl_bytes_q;
    assign irq_count_threshold_hit = (irq_cqe_threshold_i != {COUNT_W{1'b0}}) &&
                                     (irq_count_after_commit >= irq_cqe_threshold_i);
    assign irq_byte_threshold_hit = (irq_byte_threshold_i != {BYTE_W{1'b0}}) &&
                                    (irq_bytes_after_commit >= irq_byte_threshold_i);
    assign irq_timeout_threshold_hit = (irq_timeout_threshold_i != {TIMEOUT_W{1'b0}}) &&
                                       (irq_cqe_count_q != {COUNT_W{1'b0}}) &&
                                       (irq_timer_q >= (irq_timeout_threshold_i - {{(TIMEOUT_W-1){1'b0}}, 1'b1}));

    always @(posedge clk_i) begin
        if (rst_i) begin
            sq_head_q <= {PTR_W{1'b0}};
            sq_tail_q <= {PTR_W{1'b0}};
            sq_cmd_valid_o <= 1'b0;
            sq_cmd_addr_o <= {ADDR_W{1'b0}};
            sq_cmd_len_o <= {COUNT_W{1'b0}};

            cq_head_q <= {PTR_W{1'b0}};
            cq_tail_q <= {PTR_W{1'b0}};
            cq_phase_q <= 1'b1;
            cq_state_q <= CQ_IDLE;
            cpl_bytes_q <= {BYTE_W{1'b0}};
            cq_cmd_valid_o <= 1'b0;
            cq_cmd_addr_o <= {ADDR_W{1'b0}};
            cq_cmd_len_o <= {COUNT_W{1'b0}};
            cq_cmd_phase_o <= 1'b0;

            irq_cqe_count_q <= {COUNT_W{1'b0}};
            irq_byte_count_q <= {BYTE_W{1'b0}};
            irq_timer_q <= {TIMEOUT_W{1'b0}};
            irq_pulse_o <= 1'b0;
            irq_reason_o <= IRQ_REASON_NONE;
        end else begin
            irq_pulse_o <= 1'b0;
            irq_reason_o <= IRQ_REASON_NONE;

            if (sq_tail_db_wr_en_i) begin
                sq_tail_q <= sq_tail_db_i;
            end

            if (accept_sq_cmd) begin
                sq_head_q <= ptr_add(sq_head_q, sq_cmd_len_o);
                sq_cmd_valid_o <= 1'b0;
            end else if (!sq_cmd_valid_o && (sq_pending_current != {COUNT_W{1'b0}})) begin
                sq_cmd_valid_o <= 1'b1;
                sq_cmd_addr_o <= entry_addr(sq_base_addr_i, sq_head_q);
                sq_cmd_len_o <= sq_next_len;
            end

            if (cq_head_db_wr_en_i) begin
                cq_head_q <= cq_head_db_i;
            end

            case (cq_state_q)
                CQ_IDLE: begin
                    if (accept_cpl) begin
                        cpl_bytes_q <= cpl_bytes_i;
                        cq_cmd_valid_o <= 1'b1;
                        cq_cmd_addr_o <= entry_addr(cq_base_addr_i, cq_tail_q);
                        cq_cmd_len_o <= ONE_COUNT;
                        cq_cmd_phase_o <= cq_phase_q;
                        cq_state_q <= CQ_ISSUE;
                    end
                end
                CQ_ISSUE: begin
                    if (accept_cq_cmd) begin
                        cq_cmd_valid_o <= 1'b0;
                        cq_state_q <= CQ_WAIT_DONE;
                    end
                end
                CQ_WAIT_DONE: begin
                    if (cq_write_done_i) begin
                        cq_tail_q <= cq_tail_next;
                        if (cq_tail_q == (DEPTH_COUNT - ONE_COUNT)) begin
                            cq_phase_q <= !cq_phase_q;
                        end
                        cq_state_q <= CQ_IDLE;
                    end
                end
                default: begin
                    cq_state_q <= CQ_IDLE;
                    cq_cmd_valid_o <= 1'b0;
                end
            endcase

            if (cqe_commit) begin
                if (irq_count_threshold_hit) begin
                    irq_cqe_count_q <= {COUNT_W{1'b0}};
                    irq_byte_count_q <= {BYTE_W{1'b0}};
                    irq_timer_q <= {TIMEOUT_W{1'b0}};
                    irq_pulse_o <= 1'b1;
                    irq_reason_o <= IRQ_REASON_COUNT;
                end else if (irq_byte_threshold_hit) begin
                    irq_cqe_count_q <= {COUNT_W{1'b0}};
                    irq_byte_count_q <= {BYTE_W{1'b0}};
                    irq_timer_q <= {TIMEOUT_W{1'b0}};
                    irq_pulse_o <= 1'b1;
                    irq_reason_o <= IRQ_REASON_BYTES;
                end else begin
                    irq_cqe_count_q <= irq_count_after_commit;
                    irq_byte_count_q <= irq_bytes_after_commit;
                    irq_timer_q <= {{(TIMEOUT_W-1){1'b0}}, 1'b1};
                end
            end else if (irq_cqe_count_q != {COUNT_W{1'b0}}) begin
                if (irq_timeout_threshold_hit) begin
                    irq_cqe_count_q <= {COUNT_W{1'b0}};
                    irq_byte_count_q <= {BYTE_W{1'b0}};
                    irq_timer_q <= {TIMEOUT_W{1'b0}};
                    irq_pulse_o <= 1'b1;
                    irq_reason_o <= IRQ_REASON_TIMEOUT;
                end else begin
                    irq_timer_q <= irq_timer_q + {{(TIMEOUT_W-1){1'b0}}, 1'b1};
                end
            end
        end
    end

endmodule
