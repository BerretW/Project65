// =============================================================
// APARTS_BUS - VGA & SRAM CONTROLLER FOR 6502 BUS
// =============================================================
//
// DETAILNÍ MANUÁL A MAPOVÁNÍ REGISTRŮ PRO 6502 PROGRAMÁTORA:
// =============================================================
// Připojení k sběrnici využívá 4bitovou adresu portu (lv_addr 4'h0 až 4'hF).
// 
// 1. BARVA POZADÍ (Background Color) - Adresa: lv_addr = 4'h0
//    - Zápis 8bitové hodnoty určuje výchozí barvu pozadí obrazovky.
//    - Formát RGB: [7:5] Red (3 bity), [4:2] Green (3 bity), [1:0] Blue (2 bity, rozšiřují se na 3).
//
// 2. INTERNÍ ADRESA / POZICE KURZORU - Adresy: lv_addr = 4'h1, 4'h2, 4'h3
//    - 4'h1 (addr_hi): Vyšší bity adresy / kurzoru (reálně bity [2:0] pro SRAM, nebo [6:0] pro font).
//    - 4'h2 (addr_mid): Prostřední bity adresy / kurzoru.
//    - 4'h3 (addr_lo): Nejnižší bity adresy / kurzoru.
//    - V grafických režimech určují 24bitovou adresu (19 bitů aktivních) v externí SRAM.
//    - V textových režimech (01/02) slouží jako ukazatel pozice textového kurzoru v SRAM.
//    - POZNÁMKA: Po každém zápisu dat na port 4'h4 se tato adresa automaticky inkrementuje o +1.
//
// 3. DATOVÁ BRÁNA (Data Port) - Adresa: lv_addr = 4'h4
//    - Slouží pro zápis nebo čtení dat podle aktuálně nastaveného režimu (`mode`):
//      * Režim 0x0D (Editace fontu): Zápis/čtení definice fontu do interní paměti `font_mem`.
//        Adresa fontu je dána kombinací {addr_hi[6:0], addr_mid[2:0]}.
//      * Režim 0x01 / 0x02 (Textový režim): Zápis ASCII znaku na aktuální pozici kurzoru
//        do SRAM. Kurzoro-vá adresa (addr_hi/mid/lo) se sama posune o +1.
//      * Ostatní režimy (Grafické): Přímý zápis pixelů do externí SRAM na adresu `cpu_addr_full`.
//
// 4. REŽIMOVÝ REGISTR (Mode Register) - Adresa: lv_addr = 4'hD
//    - Zápis určuje chování řadiče:
//      * 0x00 až 0x0C: Grafické režimy (vykreslování pixelů přímo ze SRAM).
//      * 0x01: Textový režim (statický kurzor, vykreslování znaků přes font).
//      * 0x02: Textový režim s blikajícím kurzorem (~2 Hz).
//      * 0x0D: Režim programování/editace fontu (přístup k `font_mem`).
//      * 0x0F: Toggle / Blank screen (vypnutí obrazu – celá obrazovka zčerná).
//      * 0x0E: Hardwarový reset FPGA logiky (vyresetuje čítače a proměnné).
//    - Čtení z 4'hD vrací aktuální hodnotu registru `mode`.
//
// 5. STATUS A MAZÁNÍ PAMĚTI (Status & Clear) - Adresa: lv_addr = 4'hF
//    - Zápis (jakákoliv hodnota): Spustí hromadné vymazání celé externí SRAM (naplnění nulami).
//    - Čtení: Vrací stavový bajt `{7'b0, addr_ready}`. 
//      Bit 0 (`addr_ready`) je `1`, pokud je řadič připraven, a `0`, pokud právě probíhá 
//      mazání SRAM (`clear_busy`) nebo probíhá zápis. Před dalším zápisem je nutné testovat!
// =============================================================

module aprts_bus (
    input n_reset,
    input n_mem_w,
    input n_mem_r,
    input lv_cs,
    input clk,
    input [3:0] lv_addr,
    inout [7:0] lv_data,

    output reg [2:0] red,
    output reg [2:0] green,
    output reg [2:0] blue,
    output reg hsync,
    output reg vsync,

    output [18:0] sram_addr,
    inout  [7:0]  sram_data,
    output        sram_ce_n,
    output        sram_oe_n,
    output        sram_we_n,

    // PCM5102A Audio Interface
    output        pcm_bck,
    output        pcm_din,
    output        pcm_lrck,
    output        pcm_sck
);

    reg [7:0] reg_bg_color = 8'h00;
    reg [7:0] mode         = 8'h00; 
    reg [7:0] addr_hi      = 8'h00;
    reg [7:0] addr_mid     = 8'h00;
    reg [7:0] addr_lo      = 8'h00;
    reg [7:0] write_val    = 8'h00;

    // Audio register-indirect interface (4 channels)
    reg [4:0] aud_addr      = 5'h00;
    reg [7:0] reg_freq_lo_0 = 8'h00;
    reg [7:0] reg_freq_hi_0 = 8'h00;
    reg [7:0] reg_vol_0     = 8'h00;
    reg [7:0] reg_freq_lo_1 = 8'h00;
    reg [7:0] reg_freq_hi_1 = 8'h00;
    reg [7:0] reg_vol_1     = 8'h00;
    reg [7:0] reg_freq_lo_2 = 8'h00;
    reg [7:0] reg_freq_hi_2 = 8'h00;
    reg [7:0] reg_vol_2     = 8'h00;
    reg [7:0] reg_freq_lo_3 = 8'h00;
    reg [7:0] reg_freq_hi_3 = 8'h00;
    reg [7:0] reg_vol_3     = 8'h00;
    reg [7:0] reg_ctrl_0    = 8'h00;
    reg [7:0] reg_ctrl_1    = 8'h00;
    reg [7:0] reg_ctrl_2    = 8'h00;
    reg [7:0] reg_ctrl_3    = 8'h00;
    reg [7:0] reg_adsr_ad_0 = 8'h00;
    reg [7:0] reg_adsr_sr_0 = 8'h00;
    reg [7:0] reg_adsr_ad_1 = 8'h00;
    reg [7:0] reg_adsr_sr_1 = 8'h00;
    reg [7:0] reg_adsr_ad_2 = 8'h00;
    reg [7:0] reg_adsr_sr_2 = 8'h00;
    reg [7:0] reg_adsr_ad_3 = 8'h00;
    reg [7:0] reg_adsr_sr_3 = 8'h00;

    reg [8:0] audio_div     = 9'd0;
    reg [15:0] phase_acc_0  = 16'd0;
    reg [15:0] phase_acc_1  = 16'd0;
    reg [15:0] phase_acc_2  = 16'd0;
    reg [15:0] phase_acc_3  = 16'd0;
    reg pcm_din_r           = 1'b0;

    reg clear_busy  = 1'b0;
    reg write_req   = 1'b0;
    reg clear_tick  = 1'b0;
    reg [18:0] clear_ptr = 19'h0;

    // Font memory: 128 characters × 8 rows = 1024 bytes
    reg [7:0] font_mem [0:1023];
    reg [7:0] font_data_reg = 8'h00;

    localparam CLEAR_LAST_ADDR = 19'h4AFFF;
    wire [18:0] cpu_addr_full = {addr_hi[2:0], addr_mid, addr_lo};

    reg [9:0] h_cnt = 10'd0;
    reg [9:0] v_cnt = 10'd0;
    reg fpga_reset_req = 1'b0;
    
    wire video_on = (h_cnt < 640) && (v_cnt < 480);
    reg [18:0] vga_addr = 19'd0;

    // Blikač pro kurzor (přibližně 2 Hz)
    reg [25:0] blink_cnt = 26'd0;
    wire cursor_visible_blink = blink_cnt[24]; 

    always @(posedge clk) begin
        if (fpga_reset_req)
            blink_cnt <= 26'd0;
        else
            blink_cnt <= blink_cnt + 26'd1;
    end

    // VGA timing logic
    always @(posedge clk) begin
        if (fpga_reset_req) begin
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


// TEXTOVÝ REŽIM: 80 sloupců x 60 řádků (při velikosti fontu 8x8 pixelů)current_font_row_data 
    wire [6:0] text_col  = h_cnt[9:3];      // 0..79 (sloupec znaku, šířka 8px)
    wire [5:0] text_row  = v_cnt[8:3];      // 0..59 (řádek znaku, výška 8px)
    wire [2:0] char_line = v_cnt[2:0];      // 0..7  (řádek pixelu uvnitř znaku, výška 8)
    
    // Lineární adresa v SRAM pro textový režim (row * 80 + col)
    wire [18:0] text_sram_addr = ({13'd0, text_row} * 7'd80) + {12'd0, text_col};

    always @(posedge clk) begin
        if (fpga_reset_req) begin
            vga_addr <= 19'd0;
        end else if (h_cnt == 10'd0 && v_cnt == 10'd0) begin
            vga_addr <= 19'd0;
        end else if (video_on) begin
            vga_addr <= vga_addr + 19'd1;
        end
    end

    // Čtení z font RAM na základě aktuálně vykresleného znaku ze SRAM a řádku pixelu
    reg [7:0] current_font_row_data = 8'h00;
    always @(posedge clk) begin
        current_font_row_data <= font_mem[{sram_data[6:0], char_line[2:0]}];
    end

    // Detekce náběžné hrany zápisového cyklu pro spolehlivý jednorázový zápis
    reg write_active_last = 1'b0;
    wire write_active = !lv_cs && !n_mem_w;
    wire write_en = write_active && !write_active_last;

    always @(posedge clk) begin
        write_active_last <= write_active;
    end

    // CPU interface & Register writes (Okamžitý zápis bez čekání na blanking)
    always @(posedge clk) begin
        fpga_reset_req <= 1'b0;
        font_data_reg <= font_mem[{addr_hi[6:0], addr_mid[2:0]}];

        if (write_en) begin
            case (lv_addr)
                4'h0: reg_bg_color <= lv_data;
                4'h1: addr_hi      <= lv_data;
                4'h2: addr_mid     <= lv_data;
                4'h3: addr_lo      <= lv_data;
                4'h4: begin
                    if (mode == 8'h0D) begin
                        font_mem[{addr_hi[6:0], addr_mid[2:0]}] <= lv_data;
                    end else begin
                        write_req <= 1'b1;
                        write_val <= lv_data;
                    end
                end
                4'h5: aud_addr <= lv_data[4:0];
                4'h6: begin
                    case (aud_addr)
                        5'h00: reg_freq_lo_0 <= lv_data;
                        5'h01: reg_freq_hi_0 <= lv_data;
                        5'h02: reg_vol_0     <= lv_data;
                        5'h03: reg_freq_lo_1 <= lv_data;
                        5'h04: reg_freq_hi_1 <= lv_data;
                        5'h05: reg_vol_1     <= lv_data;
                        5'h06: reg_freq_lo_2 <= lv_data;
                        5'h07: reg_freq_hi_2 <= lv_data;
                        5'h08: reg_vol_2     <= lv_data;
                        5'h09: reg_freq_lo_3 <= lv_data;
                        5'h0A: reg_freq_hi_3 <= lv_data;
                        5'h0B: reg_vol_3     <= lv_data;
                        5'h0C: reg_ctrl_0    <= lv_data;
                        5'h0D: reg_ctrl_1    <= lv_data;
                        5'h0E: reg_ctrl_2    <= lv_data;
                        5'h0F: reg_ctrl_3    <= lv_data;
                        5'h10: reg_adsr_ad_0 <= lv_data;
                        5'h11: reg_adsr_sr_0 <= lv_data;
                        5'h12: reg_adsr_ad_1 <= lv_data;
                        5'h13: reg_adsr_sr_1 <= lv_data;
                        5'h14: reg_adsr_ad_2 <= lv_data;
                        5'h15: reg_adsr_sr_2 <= lv_data;
                        5'h16: reg_adsr_ad_3 <= lv_data;
                        5'h17: reg_adsr_sr_3 <= lv_data;
                        default: ;
                    endcase
                    // Auto-increment selector index to make sequential setup of channels extremely fast and easy
                    if (aud_addr < 5'h17) begin
                        aud_addr <= aud_addr + 5'd1;
                    end else begin
                        aud_addr <= 5'h00;
                    end
                end
                4'hD: begin
                    mode <= lv_data;
                    if (lv_data == 8'h0E) begin
                        reg_bg_color   <= 8'h00;
                        addr_hi        <= 8'h00;
                        addr_mid       <= 8'h00;
                        addr_lo        <= 8'h00;
                        write_val      <= 8'h00;
                        aud_addr       <= 5'h00;
                        reg_freq_lo_0  <= 8'h00;
                        reg_freq_hi_0  <= 8'h00;
                        reg_vol_0      <= 8'h00;
                        reg_freq_lo_1  <= 8'h00;
                        reg_freq_hi_1  <= 8'h00;
                        reg_vol_1      <= 8'h00;
                        reg_freq_lo_2  <= 8'h00;
                        reg_freq_hi_2  <= 8'h00;
                        reg_vol_2      <= 8'h00;
                        reg_freq_lo_3  <= 8'h00;
                        reg_freq_hi_3  <= 8'h00;
                        reg_vol_3      <= 8'h00;
                        reg_ctrl_0     <= 8'h00;
                        reg_ctrl_1     <= 8'h00;
                        reg_ctrl_2     <= 8'h00;
                        reg_ctrl_3     <= 8'h00;
                        reg_adsr_ad_0  <= 8'h00;
                        reg_adsr_sr_0  <= 8'h00;
                        reg_adsr_ad_1  <= 8'h00;
                        reg_adsr_sr_1  <= 8'h00;
                        reg_adsr_ad_2  <= 8'h00;
                        reg_adsr_sr_2  <= 8'h00;
                        reg_adsr_ad_3  <= 8'h00;
                        reg_adsr_sr_3  <= 8'h00;
                        clear_busy     <= 1'b0;
                        clear_tick     <= 1'b0;
                        clear_ptr      <= 19'h0;
                        write_req      <= 1'b0;
                        fpga_reset_req <= 1'b1;
                    end
                end
                4'hF: begin
                    clear_busy <= 1'b1;
                    clear_ptr  <= 19'h0;
                    clear_tick <= 1'b0;
                end
            endcase
        end

        if (clear_busy) begin
            clear_tick <= ~clear_tick;
            if (clear_tick) begin
                if (clear_ptr == CLEAR_LAST_ADDR) begin
                    clear_busy <= 1'b0;
                end else begin
                    clear_ptr <= clear_ptr + 19'd1;
                end
            end
        end

        // Okamžitý posun adresy po zápisu (bez čekání na !video_on)
        if (write_req && !clear_busy) begin
            write_req <= 1'b0;
            {addr_hi[2:0], addr_mid, addr_lo} <= cpu_addr_full + 19'd1;
        end
    end

    wire [18:0] active_vga_addr = ((mode == 8'h01 || mode == 8'h02) && video_on) ? text_sram_addr : vga_addr;

    assign sram_ce_n = 1'b0;
    assign sram_oe_n = !((video_on && !clear_busy) || (!lv_cs && !n_mem_r && lv_addr == 4'h4));
    assign sram_we_n = !((clear_busy && !clear_tick) || (write_req && !clear_busy));

    assign sram_addr = clear_busy ? clear_ptr : (video_on ? active_vga_addr : cpu_addr_full);
    assign sram_data = (!sram_we_n) ? (clear_busy ? 8'h00 : write_val) : 8'bz;

    // Vykreslování pixelů na VGA
    always @(posedge clk) begin
        if (mode == 8'h0F) begin
            // Režim 15 (0x0F): Toggle / Blank screen (vypnuto)
            red   <= 3'b000;
            green <= 3'b000;
            blue  <= 3'b000;
        end else if (video_on && !clear_busy) begin
            if (mode == 8'h01 || mode == 8'h02) begin
                // TEXTOVÝ REŽIM (01 a 02): Vykreslení pixelu fontu
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
                // GRAFICKÝ REŽIM
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

    wire addr_ready = !clear_busy && !write_req;
    reg [7:0] internal_read_val;

    always @(*) begin
        case (lv_addr)
            4'h0: internal_read_val = reg_bg_color;
            4'h1: internal_read_val = addr_hi;
            4'h2: internal_read_val = addr_mid;
            4'h3: internal_read_val = addr_lo;
            4'h4: begin
                if (mode == 8'h0D) begin
                    internal_read_val = font_data_reg;
                end else begin
                    internal_read_val = sram_data;
                end
            end
            4'h5: internal_read_val = {3'b0, aud_addr};
            4'h6: begin
                case (aud_addr)
                    5'h00: internal_read_val = reg_freq_lo_0;
                    5'h01: internal_read_val = reg_freq_hi_0;
                    5'h02: internal_read_val = reg_vol_0;
                    5'h03: internal_read_val = reg_freq_lo_1;
                    5'h04: internal_read_val = reg_freq_hi_1;
                    5'h05: internal_read_val = reg_vol_1;
                    5'h06: internal_read_val = reg_freq_lo_2;
                    5'h07: internal_read_val = reg_freq_hi_2;
                    5'h08: internal_read_val = reg_vol_2;
                    5'h09: internal_read_val = reg_freq_lo_3;
                    5'h0A: internal_read_val = reg_freq_hi_3;
                    5'h0B: internal_read_val = reg_vol_3;
                    5'h0C: internal_read_val = reg_ctrl_0;
                    5'h0D: internal_read_val = reg_ctrl_1;
                    5'h0E: internal_read_val = reg_ctrl_2;
                    5'h0F: internal_read_val = reg_ctrl_3;
                    5'h10: internal_read_val = reg_adsr_ad_0;
                    5'h11: internal_read_val = reg_adsr_sr_0;
                    5'h12: internal_read_val = reg_adsr_ad_1;
                    5'h13: internal_read_val = reg_adsr_sr_1;
                    5'h14: internal_read_val = reg_adsr_ad_2;
                    5'h15: internal_read_val = reg_adsr_sr_2;
                    5'h16: internal_read_val = reg_adsr_ad_3;
                    5'h17: internal_read_val = reg_adsr_sr_3;
                    default: internal_read_val = 8'h00;
                endcase
            end
            4'hF: internal_read_val = {7'b0, addr_ready};
            4'hD: internal_read_val = mode;
            default: internal_read_val = 8'h00;
        endcase
    end

    assign lv_data = (!lv_cs && !n_mem_r) ? internal_read_val : 8'bz;

    // =============================================================
    // PCM5102A AUDIO CONTROLLER & MULTI-CHANNEL TONE GENERATOR
    // =============================================================
    // Generates a 4-channel mixed stereo square wave based on DDS logic.
    // Each channel is defined by a 16-bit frequency and 8-bit volume.
    // At clk = 25 MHz:
    // - audio_div is a 9-bit counter, running at 25 MHz.
    // - pcm_bck  = audio_div[3] (25 MHz / 16 = 1.5625 MHz)
    // - pcm_lrck = audio_div[8] (25 MHz / 512 = 48.828 kHz, typical Fs)
    // - 16-bit phase accumulators are updated when audio_div == 0.
    // - Output sample is the signed sum of all channel square waves weighted by their volumes.
    // =============================================================

    always @(posedge clk) begin
        if (fpga_reset_req) begin
            audio_div <= 9'd0;
        end else begin
            audio_div <= audio_div + 9'd1;
        end
    end

    always @(posedge clk) begin
        if (fpga_reset_req) begin
            phase_acc_0 <= 16'd0;
            phase_acc_1 <= 16'd0;
            phase_acc_2 <= 16'd0;
            phase_acc_3 <= 16'd0;
        end else if (audio_div == 9'd0) begin
            phase_acc_0 <= phase_acc_0 + {reg_freq_hi_0, reg_freq_lo_0};
            phase_acc_1 <= phase_acc_1 + {reg_freq_hi_1, reg_freq_lo_1};
            phase_acc_2 <= phase_acc_2 + {reg_freq_hi_2, reg_freq_lo_2};
            phase_acc_3 <= phase_acc_3 + {reg_freq_hi_3, reg_freq_lo_3};
        end
    end

    function [7:0] get_step_size;
        input [3:0] rate;
        case (rate)
            4'd0:  get_step_size = 8'd1;
            4'd1:  get_step_size = 8'd2;
            4'd2:  get_step_size = 8'd3;
            4'd3:  get_step_size = 8'd4;
            4'd4:  get_step_size = 8'd6;
            4'd5:  get_step_size = 8'd8;
            4'd6:  get_step_size = 8'd12;
            4'd7:  get_step_size = 8'd16;
            4'd8:  get_step_size = 8'd24;
            4'd9:  get_step_size = 8'd32;
            4'd10: get_step_size = 8'd48;
            4'd11: get_step_size = 8'd64;
            4'd12: get_step_size = 8'd96;
            4'd13: get_step_size = 8'd128;
            4'd14: get_step_size = 8'd192;
            4'd15: get_step_size = 8'd255;
        endcase
    endfunction

    // ADSR variables
    reg [17:0] adsr_div = 18'd0;
    
    // Channel states (0: IDLE, 1: ATTACK, 2: DECAY, 3: SUSTAIN, 4: RELEASE)
    localparam STATE_IDLE    = 3'd0;
    localparam STATE_ATTACK  = 3'd1;
    localparam STATE_DECAY   = 3'd2;
    localparam STATE_SUSTAIN = 3'd3;
    localparam STATE_RELEASE = 3'd4;

    reg [2:0] adsr_state_0 = STATE_IDLE;
    reg [7:0] envelope_vol_0 = 8'h00;
    reg gate_last_0 = 1'b0;

    reg [2:0] adsr_state_1 = STATE_IDLE;
    reg [7:0] envelope_vol_1 = 8'h00;
    reg gate_last_1 = 1'b0;

    reg [2:0] adsr_state_2 = STATE_IDLE;
    reg [7:0] envelope_vol_2 = 8'h00;
    reg gate_last_2 = 1'b0;

    reg [2:0] adsr_state_3 = STATE_IDLE;
    reg [7:0] envelope_vol_3 = 8'h00;
    reg gate_last_3 = 1'b0;

    always @(posedge clk) begin
        if (fpga_reset_req) begin
            adsr_div <= 18'd0;
        end else begin
            adsr_div <= adsr_div + 18'd1;
        end
    end

    always @(posedge clk) begin
        if (fpga_reset_req) begin
            adsr_state_0 <= STATE_IDLE;
            envelope_vol_0 <= 8'd0;
            gate_last_0 <= 1'b0;

            adsr_state_1 <= STATE_IDLE;
            envelope_vol_1 <= 8'd0;
            gate_last_1 <= 1'b0;

            adsr_state_2 <= STATE_IDLE;
            envelope_vol_2 <= 8'd0;
            gate_last_2 <= 1'b0;

            adsr_state_3 <= STATE_IDLE;
            envelope_vol_3 <= 8'd0;
            gate_last_3 <= 1'b0;
        end else begin
            // Instant gate state tracking to minimize latency
            gate_last_0 <= reg_ctrl_0[4];
            gate_last_1 <= reg_ctrl_1[4];
            gate_last_2 <= reg_ctrl_2[4];
            gate_last_3 <= reg_ctrl_3[4];

            // Immediate transition on Gate Edge
            if (reg_ctrl_0[3]) begin // ADSR Enabled
                if (reg_ctrl_0[4] && !gate_last_0) begin
                    adsr_state_0 <= STATE_ATTACK;
                end else if (!reg_ctrl_0[4] && gate_last_0 && adsr_state_0 != STATE_IDLE) begin
                    adsr_state_0 <= STATE_RELEASE;
                end
            end else begin
                adsr_state_0 <= STATE_IDLE;
                envelope_vol_0 <= 8'd0;
            end

            if (reg_ctrl_1[3]) begin // ADSR Enabled
                if (reg_ctrl_1[4] && !gate_last_1) begin
                    adsr_state_1 <= STATE_ATTACK;
                end else if (!reg_ctrl_1[4] && gate_last_1 && adsr_state_1 != STATE_IDLE) begin
                    adsr_state_1 <= STATE_RELEASE;
                end
            end else begin
                adsr_state_1 <= STATE_IDLE;
                envelope_vol_1 <= 8'd0;
            end

            if (reg_ctrl_2[3]) begin // ADSR Enabled
                if (reg_ctrl_2[4] && !gate_last_2) begin
                    adsr_state_2 <= STATE_ATTACK;
                end else if (!reg_ctrl_2[4] && gate_last_2 && adsr_state_2 != STATE_IDLE) begin
                    adsr_state_2 <= STATE_RELEASE;
                end
            end else begin
                adsr_state_2 <= STATE_IDLE;
                envelope_vol_2 <= 8'd0;
            end

            if (reg_ctrl_3[3]) begin // ADSR Enabled
                if (reg_ctrl_3[4] && !gate_last_3) begin
                    adsr_state_3 <= STATE_ATTACK;
                end else if (!reg_ctrl_3[4] && gate_last_3 && adsr_state_3 != STATE_IDLE) begin
                    adsr_state_3 <= STATE_RELEASE;
                end
            end else begin
                adsr_state_3 <= STATE_IDLE;
                envelope_vol_3 <= 8'd0;
            end

            // Run ADSR Clock Updates
            if (adsr_div == 18'd0) begin
                // Channel 0 ADSR Step
                if (reg_ctrl_0[3]) begin
                    case (adsr_state_0)
                        STATE_IDLE: begin
                            envelope_vol_0 <= 8'd0;
                        end
                        STATE_ATTACK: begin
                            if (envelope_vol_0 >= (8'd255 - get_step_size(reg_adsr_ad_0[7:4]))) begin
                                envelope_vol_0 <= 8'd255;
                                adsr_state_0   <= STATE_DECAY;
                            end else begin
                                envelope_vol_0 <= envelope_vol_0 + get_step_size(reg_adsr_ad_0[7:4]);
                            end
                        end
                        STATE_DECAY: begin
                            // Sustain level is S * 17
                            if (envelope_vol_0 <= ({reg_adsr_sr_0[7:4], reg_adsr_sr_0[7:4]} + get_step_size(reg_adsr_ad_0[3:0]))) begin
                                envelope_vol_0 <= {reg_adsr_sr_0[7:4], reg_adsr_sr_0[7:4]};
                                adsr_state_0   <= STATE_SUSTAIN;
                            end else begin
                                envelope_vol_0 <= envelope_vol_0 - get_step_size(reg_adsr_ad_0[3:0]);
                            end
                        end
                        STATE_SUSTAIN: begin
                            envelope_vol_0 <= {reg_adsr_sr_0[7:4], reg_adsr_sr_0[7:4]};
                        end
                        STATE_RELEASE: begin
                            if (envelope_vol_0 <= get_step_size(reg_adsr_sr_0[3:0])) begin
                                envelope_vol_0 <= 8'd0;
                                adsr_state_0   <= STATE_IDLE;
                            end else begin
                                envelope_vol_0 <= envelope_vol_0 - get_step_size(reg_adsr_sr_0[3:0]);
                            end
                        end
                    endcase
                end

                // Channel 1 ADSR Step
                if (reg_ctrl_1[3]) begin
                    case (adsr_state_1)
                        STATE_IDLE: begin
                            envelope_vol_1 <= 8'd0;
                        end
                        STATE_ATTACK: begin
                            if (envelope_vol_1 >= (8'd255 - get_step_size(reg_adsr_ad_1[7:4]))) begin
                                envelope_vol_1 <= 8'd255;
                                adsr_state_1   <= STATE_DECAY;
                            end else begin
                                envelope_vol_1 <= envelope_vol_1 + get_step_size(reg_adsr_ad_1[7:4]);
                            end
                        end
                        STATE_DECAY: begin
                            if (envelope_vol_1 <= ({reg_adsr_sr_1[7:4], reg_adsr_sr_1[7:4]} + get_step_size(reg_adsr_ad_1[3:0]))) begin
                                envelope_vol_1 <= {reg_adsr_sr_1[7:4], reg_adsr_sr_1[7:4]};
                                adsr_state_1   <= STATE_SUSTAIN;
                            end else begin
                                envelope_vol_1 <= envelope_vol_1 - get_step_size(reg_adsr_ad_1[3:0]);
                            end
                        end
                        STATE_SUSTAIN: begin
                            envelope_vol_1 <= {reg_adsr_sr_1[7:4], reg_adsr_sr_1[7:4]};
                        end
                        STATE_RELEASE: begin
                            if (envelope_vol_1 <= get_step_size(reg_adsr_sr_1[3:0])) begin
                                envelope_vol_1 <= 8'd0;
                                adsr_state_1   <= STATE_IDLE;
                            end else begin
                                envelope_vol_1 <= envelope_vol_1 - get_step_size(reg_adsr_sr_1[3:0]);
                            end
                        end
                    endcase
                end

                // Channel 2 ADSR Step
                if (reg_ctrl_2[3]) begin
                    case (adsr_state_2)
                        STATE_IDLE: begin
                            envelope_vol_2 <= 8'd0;
                        end
                        STATE_ATTACK: begin
                            if (envelope_vol_2 >= (8'd255 - get_step_size(reg_adsr_ad_2[7:4]))) begin
                                envelope_vol_2 <= 8'd255;
                                adsr_state_2   <= STATE_DECAY;
                            end else begin
                                envelope_vol_2 <= envelope_vol_2 + get_step_size(reg_adsr_ad_2[7:4]);
                            end
                        end
                        STATE_DECAY: begin
                            if (envelope_vol_2 <= ({reg_adsr_sr_2[7:4], reg_adsr_sr_2[7:4]} + get_step_size(reg_adsr_ad_2[3:0]))) begin
                                envelope_vol_2 <= {reg_adsr_sr_2[7:4], reg_adsr_sr_2[7:4]};
                                adsr_state_2   <= STATE_SUSTAIN;
                            end else begin
                                envelope_vol_2 <= envelope_vol_2 - get_step_size(reg_adsr_ad_2[3:0]);
                            end
                        end
                        STATE_SUSTAIN: begin
                            envelope_vol_2 <= {reg_adsr_sr_2[7:4], reg_adsr_sr_2[7:4]};
                        end
                        STATE_RELEASE: begin
                            if (envelope_vol_2 <= get_step_size(reg_adsr_sr_2[3:0])) begin
                                envelope_vol_2 <= 8'd0;
                                adsr_state_2   <= STATE_IDLE;
                            end else begin
                                envelope_vol_2 <= envelope_vol_2 - get_step_size(reg_adsr_sr_2[3:0]);
                            end
                        end
                    endcase
                end

                // Channel 3 ADSR Step
                if (reg_ctrl_3[3]) begin
                    case (adsr_state_3)
                        STATE_IDLE: begin
                            envelope_vol_3 <= 8'd0;
                        end
                        STATE_ATTACK: begin
                            if (envelope_vol_3 >= (8'd255 - get_step_size(reg_adsr_ad_3[7:4]))) begin
                                envelope_vol_3 <= 8'd255;
                                adsr_state_3   <= STATE_DECAY;
                            end else begin
                                envelope_vol_3 <= envelope_vol_3 + get_step_size(reg_adsr_ad_3[7:4]);
                            end
                        end
                        STATE_DECAY: begin
                            if (envelope_vol_3 <= ({reg_adsr_sr_3[7:4], reg_adsr_sr_3[7:4]} + get_step_size(reg_adsr_ad_3[3:0]))) begin
                                envelope_vol_3 <= {reg_adsr_sr_3[7:4], reg_adsr_sr_3[7:4]};
                                adsr_state_3   <= STATE_SUSTAIN;
                            end else begin
                                envelope_vol_3 <= envelope_vol_3 - get_step_size(reg_adsr_ad_3[3:0]);
                            end
                        end
                        STATE_SUSTAIN: begin
                            envelope_vol_3 <= {reg_adsr_sr_3[7:4], reg_adsr_sr_3[7:4]};
                        end
                        STATE_RELEASE: begin
                            if (envelope_vol_3 <= get_step_size(reg_adsr_sr_3[3:0])) begin
                                envelope_vol_3 <= 8'd0;
                                adsr_state_3   <= STATE_IDLE;
                            end else begin
                                envelope_vol_3 <= envelope_vol_3 - get_step_size(reg_adsr_sr_3[3:0]);
                            end
                        end
                    endcase
                end
            end
        end
    end

    function [7:0] get_sine;
        input [5:0] phase;
        case (phase)
            6'd0:  get_sine = 8'd128;
            6'd1:  get_sine = 8'd140;
            6'd2:  get_sine = 8'd153;
            6'd3:  get_sine = 8'd165;
            6'd4:  get_sine = 8'd177;
            6'd5:  get_sine = 8'd188;
            6'd6:  get_sine = 8'd199;
            6'd7:  get_sine = 8'd209;
            6'd8:  get_sine = 8'd218;
            6'd9:  get_sine = 8'd226;
            6'd10: get_sine = 8'd234;
            6'd11: get_sine = 8'd240;
            6'd12: get_sine = 8'd245;
            6'd13: get_sine = 8'd250;
            6'd14: get_sine = 8'd253;
            6'd15: get_sine = 8'd254;
            6'd16: get_sine = 8'd255;
            6'd17: get_sine = 8'd254;
            6'd18: get_sine = 8'd253;
            6'd19: get_sine = 8'd250;
            6'd20: get_sine = 8'd245;
            6'd21: get_sine = 8'd240;
            6'd22: get_sine = 8'd234;
            6'd23: get_sine = 8'd226;
            6'd24: get_sine = 8'd218;
            6'd25: get_sine = 8'd209;
            6'd26: get_sine = 8'd199;
            6'd27: get_sine = 8'd188;
            6'd28: get_sine = 8'd177;
            6'd29: get_sine = 8'd165;
            6'd30: get_sine = 8'd153;
            6'd31: get_sine = 8'd140;
            6'd32: get_sine = 8'd128;
            6'd33: get_sine = 8'd115;
            6'd34: get_sine = 8'd102;
            6'd35: get_sine = 8'd90;
            6'd36: get_sine = 8'd78;
            6'd37: get_sine = 8'd67;
            6'd38: get_sine = 8'd56;
            6'd39: get_sine = 8'd46;
            6'd40: get_sine = 8'd37;
            6'd41: get_sine = 8'd29;
            6'd42: get_sine = 8'd21;
            6'd43: get_sine = 8'd15;
            6'd44: get_sine = 8'd10;
            6'd45: get_sine = 8'd5;
            6'd46: get_sine = 8'd2;
            6'd47: get_sine = 8'd1;
            6'd48: get_sine = 8'd0;
            6'd49: get_sine = 8'd1;
            6'd50: get_sine = 8'd2;
            6'd51: get_sine = 8'd5;
            6'd52: get_sine = 8'd10;
            6'd53: get_sine = 8'd15;
            6'd54: get_sine = 8'd21;
            6'd55: get_sine = 8'd29;
            6'd56: get_sine = 8'd37;
            6'd57: get_sine = 8'd46;
            6'd58: get_sine = 8'd56;
            6'd59: get_sine = 8'd67;
            6'd60: get_sine = 8'd78;
            6'd61: get_sine = 8'd90;
            6'd62: get_sine = 8'd102;
            6'd63: get_sine = 8'd115;
            default: get_sine = 8'd128;
        endcase
    endfunction

    function [7:0] get_wave_val;
        input [15:0] phase;
        input [2:0] ctrl;
        case (ctrl)
            3'd0: begin // Square (Obdélník)
                get_wave_val = phase[15] ? 8'hFF : 8'h00;
            end
            3'd1: begin // Triangle (Trojúhelník)
                get_wave_val = phase[15] ? ~phase[14:7] : phase[14:7];
            end
            3'd2: begin // Sawtooth (Pila)
                get_wave_val = phase[15:8];
            end
            3'd3: begin // Sine (Sinus)
                get_wave_val = get_sine(phase[15:10]);
            end
            3'd4: begin // Modified Triangle / Trapezoid (Trapéz)
                if (!phase[15]) begin
                    get_wave_val = phase[14] ? 8'hFF : {phase[13:7], 1'b0};
                end else begin
                    get_wave_val = phase[14] ? 8'h00 : ~{phase[13:7], 1'b0};
                end
            end
            default: begin
                get_wave_val = phase[15] ? 8'hFF : 8'h00;
            end
        endcase
    endfunction

    // Generate waveforms based on channel control registers
    wire [7:0] wave_0 = get_wave_val(phase_acc_0, reg_ctrl_0[2:0]);
    wire [7:0] wave_1 = get_wave_val(phase_acc_1, reg_ctrl_1[2:0]);
    wire [7:0] wave_2 = get_wave_val(phase_acc_2, reg_ctrl_2[2:0]);
    wire [7:0] wave_3 = get_wave_val(phase_acc_3, reg_ctrl_3[2:0]);

    // Scaling factor computation
    wire [15:0] scaled_vol_0 = envelope_vol_0 * reg_vol_0;
    wire [15:0] scaled_vol_1 = envelope_vol_1 * reg_vol_1;
    wire [15:0] scaled_vol_2 = envelope_vol_2 * reg_vol_2;
    wire [15:0] scaled_vol_3 = envelope_vol_3 * reg_vol_3;

    // Effective volume (using ADSR envelope scaling or simple flat volume)
    wire [7:0] eff_vol_0 = reg_ctrl_0[3] ? scaled_vol_0[15:8] : reg_vol_0;
    wire [7:0] eff_vol_1 = reg_ctrl_1[3] ? scaled_vol_1[15:8] : reg_vol_1;
    wire [7:0] eff_vol_2 = reg_ctrl_2[3] ? scaled_vol_2[15:8] : reg_vol_2;
    wire [7:0] eff_vol_3 = reg_ctrl_3[3] ? scaled_vol_3[15:8] : reg_vol_3;

    // Channel volume weighting (8-bit wave * 8-bit effective volume -> 16-bit, shifted right by 8)
    wire [15:0] prod_0 = wave_0 * eff_vol_0;
    wire [15:0] prod_1 = wave_1 * eff_vol_1;
    wire [15:0] prod_2 = wave_2 * eff_vol_2;
    wire [15:0] prod_3 = wave_3 * eff_vol_3;

    wire [7:0] weighted_0 = prod_0[15:8];
    wire [7:0] weighted_1 = prod_1[15:8];
    wire [7:0] weighted_2 = prod_2[15:8];
    wire [7:0] weighted_3 = prod_3[15:8];

    // Channel mixing (unsigned sum of weighted channels)
    // Max sum is 255 * 4 = 1020, which fits in 10 bits.
    wire [9:0] mixed_unsigned = weighted_0 + weighted_1 + weighted_2 + weighted_3;

    // Convert unsigned [0..1020] range to signed 16-bit I2S format
    // Subtract 510 to center the waveform, then shift left by 6 to fit in signed 16-bit
    wire signed [9:0] mixed_signed = mixed_unsigned - 10'd510;
    wire [15:0] current_sample = {mixed_signed[9], mixed_signed[8:0], 6'b0};

    // I2S Shift register transmitter
    always @(posedge clk) begin
        if (fpga_reset_req) begin
            pcm_din_r <= 1'b0;
        end else if (audio_div[3:0] == 4'd15) begin
            case (audio_div[7:4])
                4'd0:  pcm_din_r <= current_sample[15];
                4'd1:  pcm_din_r <= current_sample[14];
                4'd2:  pcm_din_r <= current_sample[13];
                4'd3:  pcm_din_r <= current_sample[12];
                4'd4:  pcm_din_r <= current_sample[11];
                4'd5:  pcm_din_r <= current_sample[10];
                4'd6:  pcm_din_r <= current_sample[9];
                4'd7:  pcm_din_r <= current_sample[8];
                4'd8:  pcm_din_r <= current_sample[7];
                4'd9:  pcm_din_r <= current_sample[6];
                4'd10: pcm_din_r <= current_sample[5];
                4'd11: pcm_din_r <= current_sample[4];
                4'd12: pcm_din_r <= current_sample[3];
                4'd13: pcm_din_r <= current_sample[2];
                4'd14: pcm_din_r <= current_sample[1];
                4'd15: pcm_din_r <= current_sample[0];
            endcase
        end
    end

    assign pcm_bck  = audio_div[3];
    assign pcm_lrck = audio_div[8];
    assign pcm_din  = pcm_din_r;
    assign pcm_sck  = 1'b0; // Output 0 to use the internal PLL of the breakout board

endmodule