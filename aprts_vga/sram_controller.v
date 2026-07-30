// =============================================================
// SRAM_CONTROLLER - External SRAM Memory Controller & Clear Engine
// =============================================================
// Interfaces with physical SRAM, multiplexes access between CPU reads/writes,
// VGA rendering, and background memory clear operation.
// =============================================================

module sram_controller (
    input clk,
    input reset,

    // Control Interface
    input clear_start,
    output reg clear_busy,

    // CPU Interface
    input [18:0] cpu_addr_full,
    input write_req,
    input [7:0] write_val,
    input lv_cs,
    input n_mem_r,
    input [3:0] lv_addr,
    output [7:0] sram_read_val,

    // VGA Interface
    input video_on,
    input [18:0] active_vga_addr,

    // Physical SRAM Interface
    output [18:0] sram_addr,
    inout  [7:0]  sram_data,
    output        sram_ce_n,
    output        sram_oe_n,
    output        sram_we_n
);

    reg clear_tick = 1'b0;
    reg [18:0] clear_ptr = 19'h0;
    localparam CLEAR_LAST_ADDR = 19'h4AFFF;

    // Clear busy logic
    always @(posedge clk) begin
        if (reset) begin
            clear_busy <= 1'b0;
            clear_ptr  <= 19'h0;
            clear_tick <= 1'b0;
        end else if (clear_start) begin
            clear_busy <= 1'b1;
            clear_ptr  <= 19'h0;
            clear_tick <= 1'b0;
        end else if (clear_busy) begin
            clear_tick <= ~clear_tick;
            if (clear_tick) begin
                if (clear_ptr == CLEAR_LAST_ADDR) begin
                    clear_busy <= 1'b0;
                end else begin
                    clear_ptr <= clear_ptr + 19'd1;
                end
            end
        end
    end

    // Physical SRAM signals assignment
    assign sram_ce_n = 1'b0;
    assign sram_oe_n = !((video_on && !clear_busy) || (!lv_cs && !n_mem_r && lv_addr == 4'h4));
    assign sram_we_n = !((clear_busy && !clear_tick) || (write_req && !clear_busy));

    assign sram_addr = clear_busy ? clear_ptr : (video_on ? active_vga_addr : cpu_addr_full);
    assign sram_data = (!sram_we_n) ? (clear_busy ? 8'h00 : write_val) : 8'bz;

    // Data read by the CPU from SRAM
    assign sram_read_val = sram_data;

endmodule
