`default_nettype none

// Reset synchronizer: asynchronous assertion, synchronous deassertion
// Each clock domain needs its own instance.
// Pattern from references/synthesis/cdc-guidelines.md with ASYNC_REG attributes.

module reset_synchronizer (
    input  wire clk_i,
    input  wire rst_ni,    // async active-low reset input
    output wire rst_o       // synchronized active-high reset
);

    // Synchronizer flip-flops must be kept adjacent by synthesis
    // Vivado/Quartus attribute: ASYNC_REG = "TRUE"
    // Synopsys: syn_keep = 1 prevents optimization
    (* ASYNC_REG = "TRUE" *)
    reg rst_meta_q;
    (* ASYNC_REG = "TRUE" *)
    reg rst_sync_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rst_meta_q <= 1'b0;
            rst_sync_q <= 1'b0;
        end else begin
            rst_meta_q <= 1'b1;
            rst_sync_q <= rst_meta_q;
        end
    end

    // Active-high synchronized reset
    assign rst_o = ~rst_sync_q;

endmodule

`default_nettype wire
