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
    output        sram_we_n
);

    reg [7:0] reg_bg_color = 8'h00;
    reg [7:0] mode         = 8'h00; 
    reg [7:0] addr_hi      = 8'h00;
    reg [7:0] addr_mid     = 8'h00;
    reg [7:0] addr_lo      = 8'h00;
    reg [7:0] write_val    = 8'h00;

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

    // CPU interface & Register writes (Okamžitý zápis bez čekání na blanking)
    always @(posedge clk) begin
        fpga_reset_req <= 1'b0;
        font_data_reg <= font_mem[{addr_hi[6:0], addr_mid[2:0]}];

        if (!lv_cs && !n_mem_w) begin
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
                4'hD: begin
                    mode <= lv_data;
                    if (lv_data == 8'h0E) begin
                        reg_bg_color   <= 8'h00;
                        addr_hi        <= 8'h00;
                        addr_mid       <= 8'h00;
                        addr_lo        <= 8'h00;
                        write_val      <= 8'h00;
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
            4'hF: internal_read_val = {7'b0, addr_ready};
            4'hD: internal_read_val = mode;
            default: internal_read_val = 8'h00;
        endcase
    end

    assign lv_data = (!lv_cs && !n_mem_r) ? internal_read_val : 8'bz;

endmodule