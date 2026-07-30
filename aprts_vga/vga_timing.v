// =============================================================
// VGA_TIMING - VGA Sync & Timing Generator
// =============================================================
// Generates standard 640x480 @ 60Hz timing signals using a 25 MHz pixel clock.
// =============================================================

module vga_timing (
    input clk,
    input reset,
    output reg [9:0] h_cnt,
    output reg [9:0] v_cnt,
    output reg hsync,
    output reg vsync,
    output video_on
);

    assign video_on = (h_cnt < 640) && (v_cnt < 480);

    always @(posedge clk) begin
        if (reset) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else if (h_cnt < 10'd799) begin
            h_cnt <= h_cnt + 10'd1;
        end else begin
            h_cnt <= 10'd0;
            if (v_cnt < 10'd524) begin
                v_cnt <= v_cnt + 10'd1;
            end else begin
                v_cnt <= 10'd0;
            end
        end

        hsync <= ~((h_cnt >= 10'd656) && (h_cnt < 10'd752));
        vsync <= ~((v_cnt >= 10'd490) && (v_cnt < 10'd492));
    end

endmodule
