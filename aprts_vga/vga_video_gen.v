// =============================================================
// VGA_VIDEO_GEN - VGA Text & Graphics Pixel Generator
// =============================================================
// Manages display memory addresses, contains internal Font RAM (1024 bytes),
// handles character fetching/rendering, and produces RGB pixel outputs.
// =============================================================

module vga_video_gen (
    input clk,
    input reset,

    // Timing Inputs
    input [9:0] h_cnt,
    input [9:0] v_cnt,
    input video_on,

    // Control Registers
    input [7:0] mode,
    input [7:0] reg_bg_color,
    input clear_busy,

    // Font RAM CPU Programming Interface
    input font_write_en,
    input [9:0] font_addr,
    input [7:0] font_write_data,
    output reg [7:0] font_read_data,

    // SRAM Interface
    input [7:0] sram_data,
    output [18:0] active_vga_addr,

    // RGB Outputs
    output reg [2:0] red,
    output reg [2:0] green,
    output reg [2:0] blue
);

    // Font memory: 128 characters × 8 rows = 1024 bytes
    reg [7:0] font_mem [0:1023];

    // Read font data for CPU
    always @(posedge clk) begin
        font_read_data <= font_mem[font_addr];
    end

    // Write font data from CPU
    always @(posedge clk) begin
        if (font_write_en) begin
            font_mem[font_addr] <= font_write_data;
        end
    end

    // TEXT MODE timing extraction: 80 columns x 60 rows (8x8 characters)
    wire [6:0] text_col  = h_cnt[9:3];      // 0..79 (character column)
    wire [5:0] text_row  = v_cnt[8:3];      // 0..59 (character row)
    wire [2:0] char_line = v_cnt[2:0];      // 0..7  (pixel row inside character)

    // Linear SRAM address for Text Mode (row * 80 + col)
    wire [18:0] text_sram_addr = ({13'd0, text_row} * 7'd80) + {12'd0, text_col};

    // Graphics mode VGA linear address counter
    reg [18:0] vga_addr = 19'd0;

    always @(posedge clk) begin
        if (reset) begin
            vga_addr <= 19'd0;
        end else if (h_cnt == 10'd0 && v_cnt == 10'd0) begin
            vga_addr <= 19'd0;
        end else if (video_on) begin
            vga_addr <= vga_addr + 19'd1;
        end
    end

    // Address multiplexer for the SRAM read cycle
    assign active_vga_addr = ((mode == 8'h01 || mode == 8'h02) && video_on) ? text_sram_addr : vga_addr;

    // Font RAM read cycle for text rendering (1-cycle delay)
    reg [7:0] current_font_row_data = 8'h00;
    always @(posedge clk) begin
        current_font_row_data <= font_mem[{sram_data[6:0], char_line[2:0]}];
    end

    // Cursor Blink Counter (~2 Hz)
    reg [25:0] blink_cnt = 26'd0;
    wire cursor_visible_blink = blink_cnt[24];

    always @(posedge clk) begin
        if (reset)
            blink_cnt <= 26'd0;
        else
            blink_cnt <= blink_cnt + 26'd1;
    end

    // VGA Pixel Generator (RGB logic)
    always @(posedge clk) begin
        if (mode == 8'h0F) begin
            // Mode 15 (0x0F): Toggle / Blank screen (all black)
            red   <= 3'b000;
            green <= 3'b000;
            blue  <= 3'b000;
        end else if (video_on && !clear_busy) begin
            if (mode == 8'h01 || mode == 8'h02) begin
                // TEXT MODE (01 & 02): Render pixel from current font row
                if (current_font_row_data[7 - h_cnt[2:0]]) begin
                    red   <= 3'b111;
                    green <= 3'b111;
                    blue  <= 3'b111;
                end else begin
                    red   <= reg_bg_color[7:5];
                    green <= reg_bg_color[4:2];
                    blue  <= {reg_bg_color[1:0], 1'b0};
                end
            end else begin
                // GRAPHICS MODE
                if (sram_data == 8'h00) begin
                    red   <= reg_bg_color[7:5];
                    green <= reg_bg_color[4:2];
                    blue  <= {reg_bg_color[1:0], 1'b0};
                end else begin
                    red   <= sram_data[7:5];
                    green <= sram_data[4:2];
                    blue  <= {sram_data[1:0], 1'b0};
                end
            end
        end else begin
            red   <= 3'b000;
            green <= 3'b000;
            blue  <= 3'b000;
        end
    end

endmodule
