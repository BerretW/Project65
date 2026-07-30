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

    output [2:0] red,
    output [2:0] green,
    output [2:0] blue,
    output hsync,
    output vsync,

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

    // =============================================================
    // INTERNAL REGISTERS & WIRES
    // =============================================================
    reg [7:0] reg_bg_color   = 8'h00;
    reg [7:0] mode           = 8'h00; 
    reg [7:0] addr_hi        = 8'h00;
    reg [7:0] addr_mid       = 8'h00;
    reg [7:0] addr_lo        = 8'h00;
    reg [7:0] write_val      = 8'h00;
    reg       write_req      = 1'b0;

    reg fpga_reset_req = 1'b0;

    // Full 19-bit address for CPU access to SRAM
    wire [18:0] cpu_addr_full = {addr_hi[2:0], addr_mid, addr_lo};

    // Edge detector for write cycles
    reg write_active_last = 1'b0;
    wire write_active = !lv_cs && !n_mem_w;
    wire write_en = write_active && !write_active_last;

    always @(posedge clk) begin
        write_active_last <= write_active;
    end

    // =============================================================
    // SUBMODULE INSTANTIATIONS
    // =============================================================

    // 1. VGA Sync & Timing Generator
    wire [9:0] h_cnt;
    wire [9:0] v_cnt;
    wire video_on;

    vga_timing u_vga_timing (
        .clk(clk),
        .reset(fpga_reset_req),
        .h_cnt(h_cnt),
        .v_cnt(v_cnt),
        .hsync(hsync),
        .vsync(vsync),
        .video_on(video_on)
    );

    // 2. VGA Video & Text Generator (Font memory & pixel routing)
    wire [18:0] active_vga_addr;
    wire font_write_en = (write_en && (mode == 8'h0D) && (lv_addr == 4'h4));
    wire [9:0] font_addr = {addr_hi[6:0], addr_mid[2:0]};
    wire [7:0] font_read_data;

    vga_video_gen u_vga_video_gen (
        .clk(clk),
        .reset(fpga_reset_req),
        .h_cnt(h_cnt),
        .v_cnt(v_cnt),
        .video_on(video_on),
        .mode(mode),
        .reg_bg_color(reg_bg_color),
        .clear_busy(clear_busy),
        .font_write_en(font_write_en),
        .font_addr(font_addr),
        .font_write_data(lv_data),
        .font_read_data(font_read_data),
        .sram_data(sram_data),
        .active_vga_addr(active_vga_addr),
        .red(red),
        .green(green),
        .blue(blue)
    );

    // 3. SRAM Controller & Memory Clear Engine
    wire clear_start = (write_en && (lv_addr == 4'hF));
    wire clear_busy;
    wire [7:0] sram_read_val;

    sram_controller u_sram_controller (
        .clk(clk),
        .reset(fpga_reset_req),
        .clear_start(clear_start),
        .clear_busy(clear_busy),
        .cpu_addr_full(cpu_addr_full),
        .write_req(write_req),
        .write_val(write_val),
        .lv_cs(lv_cs),
        .n_mem_r(n_mem_r),
        .lv_addr(lv_addr),
        .sram_read_val(sram_read_val),
        .video_on(video_on),
        .active_vga_addr(active_vga_addr),
        .sram_addr(sram_addr),
        .sram_data(sram_data),
        .sram_ce_n(sram_ce_n),
        .sram_oe_n(sram_oe_n),
        .sram_we_n(sram_we_n)
    );

    // 4. Audio Synthesizer (4-channel DDS / ADSR Engine & I2S transmitter)
    wire [7:0] audio_read_val;
    wire audio_write_en = write_en && (lv_addr == 4'h5 || lv_addr == 4'h6);

    aprts_audio u_aprts_audio (
        .clk(clk),
        .reset(fpga_reset_req),
        .write_en(audio_write_en),
        .lv_addr(lv_addr),
        .lv_data(lv_data),
        .audio_read_val(audio_read_val),
        .pcm_bck(pcm_bck),
        .pcm_din(pcm_din),
        .pcm_lrck(pcm_lrck),
        .pcm_sck(pcm_sck)
    );

    // =============================================================
    // CPU INTERFACE & REGISTER WRITES
    // =============================================================
    always @(posedge clk) begin
        fpga_reset_req <= 1'b0;

        if (write_en) begin
            case (lv_addr)
                4'h0: reg_bg_color <= lv_data;
                4'h1: addr_hi      <= lv_data;
                4'h2: addr_mid     <= lv_data;
                4'h3: addr_lo      <= lv_data;
                4'h4: begin
                    if (mode != 8'h0D) begin
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
                        write_req      <= 1'b0;
                        fpga_reset_req <= 1'b1;
                    end
                end
                default: ;
            endcase
        end

        // Auto-increment logic
        if (write_req && !clear_busy) begin
            write_req <= 1'b0;
            {addr_hi[2:0], addr_mid, addr_lo} <= cpu_addr_full + 19'd1;
        end
    end

    // =============================================================
    // REGISTER READS (COMBINATIONAL)
    // =============================================================
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
                    internal_read_val = font_read_data;
                end else begin
                    internal_read_val = sram_read_val;
                end
            end
            4'h5, 4'h6: internal_read_val = audio_read_val;
            4'hD: internal_read_val = mode;
            4'hF: internal_read_val = {7'b0, addr_ready};
            default: internal_read_val = 8'h00;
        endcase
    end

    // Drive CPU data bus during reads when CS is active
    assign lv_data = (!lv_cs && !n_mem_r) ? internal_read_val : 8'bz;

endmodule