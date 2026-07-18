module vga_demo (
    input  wire        clk_25mhz, // Vstupní hodinový signál 25 MHz
    
    // VGA rozhraní (9-bit DAC)
    output reg  [2:0]  red,       
    output reg  [2:0]  green,     
    output reg  [2:0]  blue,      
    output reg         hsync,     
    output reg         vsync,     

    // SRAM rozhraní (slouží jako VRAM)
    output reg  [18:0] sram_addr, 
    inout  wire [7:0]  sram_data, 
    output reg         sram_ce_n, 
    output reg         sram_oe_n, 
    output reg         sram_we_n, 

    // 6502 CPU Interface (VERA-style registry)
    input  wire        lv_cs,     // Aktivní v nule (Chip Select)
    input  wire        lv_mem_r,  // Aktivní v nule (Read Enable)
    input  wire        lv_mem_w,  // Aktivní v nule (Write Enable)
    input  wire [3:0]  lv_addr,   // Adresní piny registrů (A0-A3)
    inout  wire [7:0]  lv_data    // Obousměrná datová sběrnice k CPU
);

    // Mapování paměti:
    // 0x00000 - 0x12BFF : Framebuffer (Bitmapa) nebo Video RAM pro text 80x60
    // 0x03000 - 0x037FF : Font RAM v textovém módu (CPU sem zapíše font)
    // 0x1F000 - 0x1F1FF : Palette RAM (256 barev x 2 bajty, uloženo interně v FPGA)

    // ==========================================
    // 1. REGISTRY PRO CPU (VERA INTERFACE)
    // ==========================================
    reg [7:0]  addr_l = 8'h00;
    reg [7:0]  addr_m = 8'h00;
    reg [7:0]  addr_h = 8'h00; 
    reg [7:0]  ctrl_reg = 8'h80; // [7] = Splash screen, [3:1] = Volba palety, [0] = Režim (0 = Text, 1 = Bitmapa)
    reg [7:0]  debug_ctrl_reg = 8'h00; // [0] = Debug overlay enable
    
    wire [18:0] current_vram_addr = {addr_h[2:0], addr_m, addr_l};
    wire [3:0]  step_sel = addr_h[7:4];
    reg  [18:0] step_value;

    always @(*) begin
        case (step_sel)
            4'd0:  step_value = 19'd0;
            4'd1:  step_value = 19'd1;
            4'd2:  step_value = 19'd2;
            4'd3:  step_value = 19'd4;
            4'd4:  step_value = 19'd8;
            4'd5:  step_value = 19'd16;
            4'd6:  step_value = 19'd32;
            4'd7:  step_value = 19'd64;
            4'd8:  step_value = 19'd128;
            4'd9:  step_value = 19'd256;
            default: step_value = 19'd1;
        endcase
    end

    // Synchronizace signálů z CPU
    reg [1:0] sync_cs, sync_r, sync_w;
    reg [3:0] sync_reg_addr;
    reg [7:0] sync_cpu_data_out;
    
    always @(posedge clk_25mhz) begin
        sync_cs    <= {sync_cs[0],    lv_cs};
        sync_r     <= {sync_r[0],     lv_mem_r};
        sync_w     <= {sync_w[0],     lv_mem_w};
        sync_reg_addr <= lv_addr;
        sync_cpu_data_out <= lv_data;
    end

    wire reg_write_pulse = (sync_cs[1] == 1'b0 && sync_w[1] == 1'b0 && sync_w[0] == 1'b1);
    wire reg_read_pulse  = (sync_cs[1] == 1'b0 && sync_r[1] == 1'b0 && sync_r[0] == 1'b1);

    reg        cpu_write_pending = 0;
    reg        cpu_read_pending  = 0;
    reg [7:0]  cpu_write_data;
    reg [7:0]  cpu_read_data;
    reg        palette_write_done_pulse = 0;

    always @(posedge clk_25mhz) begin
        palette_write_done_pulse <= 1'b0;

        if (reg_write_pulse) begin
            case (sync_reg_addr)
                4'd0: addr_l <= sync_cpu_data_out;
                4'd1: addr_m <= sync_cpu_data_out;
                4'd2: addr_h <= sync_cpu_data_out;
                4'd3: begin
                    ctrl_reg[7] <= 1'b0; // První zápis do paměti vypne BIST
                    if (is_palette_addr) begin
                        if (current_vram_addr[0] == 1'b0) begin
                            palette_ram_low[current_vram_addr[8:1]] <= sync_cpu_data_out;
                        end else begin
                            palette_ram_high[current_vram_addr[8:1]] <= sync_cpu_data_out[3:0];
                        end
                        palette_write_done_pulse <= 1'b1;
                    end else begin
                        cpu_write_data    <= sync_cpu_data_out;
                        cpu_write_pending <= 1; 
                    end
                end
                4'd4: begin
                    ctrl_reg <= sync_cpu_data_out;
                end
                4'd5: begin
                    debug_ctrl_reg <= sync_cpu_data_out;
                end
            endcase
        end else if (reg_read_pulse && sync_reg_addr == 4'd3) begin
            cpu_read_pending <= 1; 
        end

        if (cpu_write_done || palette_write_done_pulse) begin
            cpu_write_pending <= 0;
            {addr_h[2:0], addr_m, addr_l} <= current_vram_addr + step_value;
        end
        if (cpu_read_done) begin
            cpu_read_pending <= 0;
            {addr_h[2:0], addr_m, addr_l} <= current_vram_addr + step_value;
        end
    end

    assign lv_data = (lv_cs == 1'b0 && lv_mem_r == 1'b0) ? 
                     ((lv_addr == 4'd3) ? cpu_read_data :
                      (lv_addr == 4'd4) ? ctrl_reg :
                      (lv_addr == 4'd5) ? debug_ctrl_reg : 8'bz) : 8'bz;

    // Pri zapisu do externi SRAM musi FPGA aktivne ridit datovou sbernici.
    // Bez tohoto tri-state driveru by zapisy do VRAM neprobehly.
    assign sram_data = (sram_we_n == 1'b0) ? cpu_write_data : 8'bz;

    // ==========================================
    // 2. VNITŘNÍ PALETTE RAM (M9K)
    // ==========================================
    wire is_palette_addr = (current_vram_addr >= 19'h1F000 && current_vram_addr <= 19'h1F1FF);
    
    reg [7:0] palette_ram_low  [0:255];
    reg [3:0] palette_ram_high [0:255];
    
    reg [11:0] active_color;
    reg [7:0]  next_pixel_color; // Kombinační adresa pro čtení palety
    
    always @(posedge clk_25mhz) begin
        active_color[7:0]  <= palette_ram_low[next_pixel_color];
        active_color[11:8] <= palette_ram_high[next_pixel_color];
    end

    // ==========================================
    // 3. ČASOVÁNÍ VGA (640x480 @ 60 Hz)
    // ==========================================
    localparam H_ACTIVE      = 640;
    localparam H_FRONT_PORCH = 16;
    localparam H_SYNC        = 96;
    localparam H_BACK_PORCH  = 48;
    localparam H_TOTAL       = 800;

    localparam V_ACTIVE      = 480;
    localparam V_FRONT_PORCH = 10;
    localparam V_SYNC        = 2;
    localparam V_BACK_PORCH  = 33;
    localparam V_TOTAL       = 525;

    reg [9:0] h_cnt = 0;
    reg [9:0] v_cnt = 0;

    always @(posedge clk_25mhz) begin
        if (h_cnt < H_TOTAL - 1) begin
            h_cnt <= h_cnt + 1;
        end else begin
            h_cnt <= 0;
            if (v_cnt < V_TOTAL - 1) begin
                v_cnt <= v_cnt + 1;
            end else begin
                v_cnt <= 0;
            end
        end
    end

    wire hsync_node = (h_cnt >= (H_ACTIVE + H_FRONT_PORCH) && h_cnt < (H_ACTIVE + H_FRONT_PORCH + H_SYNC)) ? 1'b0 : 1'b1;
    wire vsync_node = (v_cnt >= (V_ACTIVE + V_FRONT_PORCH) && v_cnt < (V_ACTIVE + V_FRONT_PORCH + V_SYNC)) ? 1'b0 : 1'b1;
    wire display_on_node = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);

    // ==========================================
    // 4. SRAM ARBITER (DVOJREŽIMOVÝ)
    // ==========================================
    // Bitmap Mode adresa: (y * 320) + x
    wire [18:0] bitmap_pixel_addr = ({7'b0, v_cnt[8:1]} << 8) + ({9'b0, v_cnt[8:1]} << 6) + {9'b0, h_cnt[9:1]};
    
    // Text Mode adresa (80x60 znaků)
    wire [11:0] text_offset = (v_cnt[8:3] * 80) + h_cnt[9:3];

    reg [7:0] char_id_reg;
    reg [7:0] attr_reg;
    reg [7:0] font_row_reg;
    reg [7:0] bitmap_pixel_reg = 8'h00; // Pouze jeden řadič pro zápis bitmapy ze SRAM
    reg       cpu_write_done = 0;
    reg       cpu_read_done = 0;

    wire [2:0] vga_phase = h_cnt[2:0];
    wire       video_mode = ctrl_reg[0]; // 0 = Textový režim, 1 = Bitmapový režim

    always @(posedge clk_25mhz) begin
        sram_ce_n <= 1'b0;
        sram_oe_n <= 1'b1;
        sram_we_n <= 1'b1;
        cpu_write_done <= 0;
        cpu_read_done <= 0;

        if (video_mode) begin
            // BITMAPOVÝ REŽIM (TDM 1:1)
            if (h_cnt[0] == 1'b0) begin
                sram_addr <= bitmap_pixel_addr;
                sram_oe_n <= 1'b0;
            end else begin
                bitmap_pixel_reg <= sram_data; // Zde bezpečně načteme surová data pro bitmapu

                if (cpu_write_pending && !is_palette_addr) begin
                    sram_addr <= current_vram_addr;
                    sram_we_n <= 1'b0;
                    cpu_write_done <= 1;
                end else if (cpu_read_pending && !is_palette_addr) begin
                    sram_addr <= current_vram_addr;
                    sram_oe_n <= 1'b0;
                    cpu_read_data <= sram_data;
                    cpu_read_done <= 1;
                end
            end
        end else begin
            // TEXTOVÝ REŽIM (TDM 4-fázový)
            case (vga_phase)
                3'd0: begin
                    sram_addr <= {7'b0000000, text_offset} << 1; // Znak
                    sram_oe_n <= 1'b0;
                end
                3'd1: begin
                    char_id_reg <= sram_data;
                    sram_addr   <= ({7'b0000000, text_offset} << 1) + 1; // Atribut
                    sram_oe_n   <= 1'b0;
                end
                3'd2: begin
                    attr_reg  <= sram_data;
                    // Odstraněn Warning (10230) přesnou definicí 19bitových šířek operandů
                    sram_addr <= 19'h03000 + ({11'd0, char_id_reg} * 19'd8) + {16'd0, v_cnt[2:0]}; 
                    sram_oe_n <= 1'b0;
                end
                3'd3: begin
                    font_row_reg <= sram_data;
                end
                default: begin
                    // Volné sloty pro CPU
                    if (cpu_write_pending && !is_palette_addr) begin
                        sram_addr <= current_vram_addr;
                        sram_we_n <= 1'b0;
                        cpu_write_done <= 1;
                    end else if (cpu_read_pending && !is_palette_addr) begin
                        sram_addr <= current_vram_addr;
                        sram_oe_n <= 1'b0;
                        cpu_read_data <= sram_data;
                        cpu_read_done <= 1;
                    end
                end
            endcase
        end
    end

    // ==========================================
    // 5. GENEROVÁNÍ INICIALIZAČNÍHO OBRAZCE (BIST)
    // ==========================================
    reg [2:0] splash_r, splash_g, splash_b;

    always @(*) begin
        if (v_cnt < 240) begin
            if (h_cnt < 80) begin
                splash_r = 3'b111; splash_g = 3'b111; splash_b = 3'b111;
            end else if (h_cnt < 160) begin
                splash_r = 3'b111; splash_g = 3'b111; splash_b = 3'b000;
            end else if (h_cnt < 240) begin
                splash_r = 3'b000; splash_g = 3'b111; splash_b = 3'b111;
            end else if (h_cnt < 320) begin
                splash_r = 3'b000; splash_g = 3'b111; splash_b = 3'b000;
            end else if (h_cnt < 400) begin
                splash_r = 3'b111; splash_g = 3'b000; splash_b = 3'b111;
            end else if (h_cnt < 480) begin
                splash_r = 3'b111; splash_g = 3'b000; splash_b = 3'b000;
            end else if (h_cnt < 560) begin
                splash_r = 3'b000; splash_g = 3'b000; splash_b = 3'b111;
            end else begin
                splash_r = 3'b000; splash_g = 3'b000; splash_b = 3'b000;
            end
        end else begin
            splash_r = h_cnt[8:6];
            splash_g = h_cnt[8:6];
            splash_b = h_cnt[8:6];
        end
    end

    // ==========================================
    // 6. GENEROVÁNÍ VGA VÝSTUPU
    // ==========================================
    reg hsync_reg, vsync_reg, display_on_reg;
    reg splash_screen_active_reg;
    reg [2:0] splash_r_reg, splash_g_reg, splash_b_reg;
    reg        video_mode_reg;

    reg [2:0] debug_code = 3'd0;
    reg [21:0] debug_hold_counter = 22'd0;
    reg [2:0] debug_r, debug_g, debug_b;

    wire debug_overlay_on = debug_ctrl_reg[0] &&
                            display_on_reg &&
                            h_cnt >= 10'd608 && h_cnt < 10'd632 &&
                            v_cnt >= 10'd8 && v_cnt < 10'd32;

    always @(posedge clk_25mhz) begin
        if (!debug_ctrl_reg[0]) begin
            debug_code <= 3'd0;
            debug_hold_counter <= 22'd0;
        end else if (reg_write_pulse) begin
            debug_code <= 3'd1;        // CPU zapisuje do registru
            debug_hold_counter <= 22'h3fffff;
        end else if (reg_read_pulse) begin
            debug_code <= 3'd2;        // CPU cte z registru
            debug_hold_counter <= 22'h3fffff;
        end else if (palette_write_done_pulse) begin
            debug_code <= 3'd3;        // Zapis do internich palette RAM
            debug_hold_counter <= 22'h3fffff;
        end else if (cpu_write_done) begin
            debug_code <= 3'd4;        // Dokonceny zapis CPU do externi SRAM
            debug_hold_counter <= 22'h3fffff;
        end else if (cpu_read_done) begin
            debug_code <= 3'd5;        // Dokoncene cteni CPU z externi SRAM
            debug_hold_counter <= 22'h3fffff;
        end else if (debug_hold_counter != 22'd0) begin
            debug_hold_counter <= debug_hold_counter - 1'b1;
        end else if (sram_ce_n == 1'b0 && sram_oe_n == 1'b0) begin
            debug_code <= 3'd6;        // Video fetch / prace se SRAM
        end else begin
            debug_code <= 3'd0;
        end
    end

    always @(*) begin
        case (debug_code)
            3'd1: begin debug_r = 3'b111; debug_g = 3'b000; debug_b = 3'b000; end // CPU write
            3'd2: begin debug_r = 3'b111; debug_g = 3'b111; debug_b = 3'b000; end // CPU read
            3'd3: begin debug_r = 3'b111; debug_g = 3'b000; debug_b = 3'b111; end // Palette write
            3'd4: begin debug_r = 3'b000; debug_g = 3'b111; debug_b = 3'b000; end // SRAM write
            3'd5: begin debug_r = 3'b000; debug_g = 3'b111; debug_b = 3'b111; end // SRAM read
            3'd6: begin debug_r = 3'b000; debug_g = 3'b000; debug_b = 3'b111; end // Video SRAM fetch
            default: begin debug_r = 3'b111; debug_g = 3'b111; debug_b = 3'b111; end
        endcase
    end

    always @(posedge clk_25mhz) begin
        hsync_reg                <= hsync_node;
        vsync_reg                <= vsync_node;
        display_on_reg           <= display_on_node;
        splash_screen_active_reg <= ctrl_reg[7];
        video_mode_reg           <= video_mode;
        
        splash_r_reg             <= splash_r;
        splash_g_reg             <= splash_g;
        splash_b_reg             <= splash_b;

        hsync                    <= hsync_reg;
        vsync                    <= vsync_reg;
    end

    // Dekódování pixelu (text vs. bitmapa)
    wire       pixel_on = font_row_reg[3'd7 - h_cnt[2:0]];
    wire [2:0] palette_sel = ctrl_reg[3:1]; // CPU může přepínat aktivní paletu (0-7)

    // Výběr správného indexu do palety (kombinační logikou bez konfliktů)
    always @(*) begin
        if (video_mode_reg) begin
            next_pixel_color = bitmap_pixel_reg; // V bitmapovém režimu určuje barvu pixel přímo ze SRAM
        end else begin
            // V textovém režimu: horní 3 bity vybírají paletu, spodní 4 bity barvu
            // pixel_on určí, zda vykreslíme popředí [7:4] nebo pozadí [3:0]
            next_pixel_color = {1'b0, palette_sel, pixel_on ? attr_reg[7:4] : attr_reg[3:0]};
        end
    end

    // Převod 12-bitové barvy z palety na 9-bit DAC
    wire [2:0] dac_red   = active_color[11:9]; 
    wire [2:0] dac_green = active_color[7:5];  
    wire [2:0] dac_blue  = active_color[3:1];  

    always @(posedge clk_25mhz) begin
        if (display_on_reg) begin
            if (debug_overlay_on) begin
                red   <= debug_r;
                green <= debug_g;
                blue  <= debug_b;
            end else if (splash_screen_active_reg) begin
                red   <= splash_r_reg;
                green <= splash_g_reg;
                blue  <= splash_b_reg;
            end else begin
                red   <= dac_red;
                green <= dac_green;
                blue  <= dac_blue;
            end
        end else begin
            red   <= 3'b000;
            green <= 3'b000;
            blue  <= 3'b000;
        end
    end

endmodule