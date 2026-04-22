; vera_test.asm — VERA text display test
; Layer 0, 1bpp tile mode, 80×60 text (640×480 VGA, 8×8 font z font.asm)
;
; VRAM layout:
;   $00000  tile map  — 128×64 entries × 2 B = $4000 B
;                       entry = [char_index, color]
;                       addr = (row × 128 + col) × 2  =  row × 256 + col × 2
;   $04000  font data — 128 chars × 8 B = $400 B
;
; Sestavení:
;   ca65 -t none vera_test.asm -o vera_test.o
;   ld65 -t none -S '$3100' vera_test.o -o vera_test.bin   # PowerShell
;   ld65 -t none -S $3100 vera_test.o -o vera_test.bin    # bash/cmd
;   python ../ihex_gen.py vera_test.bin 3100 vera_test.hex
;
; Použití v AppartusOS:
;   LOAD              ← pošli vera_test.hex
;   SAVE VERATEST 3100 0600
;   RUN VERATEST

; --- ROM API ---
ROM_PUTS    = $FF0C
ROM_PRINTNL = $FF18
ROM_PUTC    = $FF09
ROM_PRTBYTE = $FF1B
ROM_PUTNL   = $FF15

; --- VERA registry (base $C000, spec v0.9) ---
VERA_ADDRLO  = $C000
VERA_ADDRMI  = $C001
VERA_ADDRHI  = $C002   ; [7:4]=incr step (1→+1), [3]=DECR, [0]=addr bit 16
VERA_DATA0   = $C003
VERA_CTRL    = $C005   ; [7]=RESET, [1]=DCSEL, [0]=ADDRSEL

VERA_DC_VIDEO   = $C009   ; DCSEL=0: [6]=sprites, [5]=L1, [4]=L0, [1:0]=mode
VERA_DC_HSCALE  = $C00A   ; 128 = 1:1 pixel mapping
VERA_DC_VSCALE  = $C00B
VERA_DC_BORDER  = $C00C

VERA_L0_CONFIG   = $C00D  ; [7:6]=MapH, [5:4]=MapW, [3]=T256C, [2]=bitmap, [1:0]=depth
VERA_L0_MAPBASE  = $C00E  ; addr bits 16:9 of tile map
VERA_L0_TILEBASE = $C00F  ; [7:2]=addr bits 16:11, [1]=TileH, [0]=TileW

; --- ZP scratch (mimo OS $40–$4E) ---
ZP_PTR  = $F0   ; 2 B — ukazatel na řetězec
ZP_CNT  = $F2   ; 1 B — outer loop counter při mazání mapy
ZP_ROW  = $F3   ; 1 B — řádek pro vera_puts
ZP_COL  = $F4   ; 1 B — sloupec pro vera_puts

.org $3100

; ============================================================
start:
    LDA #<msg_title
    LDX #>msg_title
    JSR ROM_PRINTNL

    ; --- 1. VERA reset (zajistí čistý stav registrů a výchozí paletu) ---
    ;LDA #$80
    ;STA VERA_CTRL           ; RESET bit — FPGA se rekonfiguruje
    LDX #255                ; delay ~200 ms při 1 MHz
@rst_dly:
    LDY #255
@rst_dly2:
    DEY
    BNE @rst_dly2
    DEX
    BNE @rst_dly
    ;LDA #$00
    ;STA VERA_CTRL           ; DCSEL=0, ADDRSEL=0

    ; --- 1b. Explicitní inicializace palety ---
    ; Barva 0 = černá ($000), barva 1 = bílá ($FFF)
    ; Palette VRAM base $1FA00, entry formát: [G:B], [0:R]
    LDA #$00
    STA VERA_ADDRLO
    LDA #$FA
    STA VERA_ADDRMI
    LDA #$11                ; increment=1, bit16=1 (addr > $FFFF)
    STA VERA_ADDRHI
    LDA #$00
    STA VERA_DATA0          ; barva 0 byte0: G=0, B=0
    STA VERA_DATA0          ; barva 0 byte1: R=0  → černá
    LDA #$FF
    STA VERA_DATA0          ; barva 1 byte0: G=$F, B=$F
    LDA #$0F
    STA VERA_DATA0          ; barva 1 byte1: R=$F → bílá
    ;LDA #$00
    ;STA VERA_CTRL           ; obnov DCSEL=0 pro DC registry

    ; --- 2. Display composer: VGA 1:1, border černý ---
    LDA #$80            ; HSCALE = 128 → 640px / 8px = 80 sloupců
    STA VERA_DC_HSCALE
    STA VERA_DC_VSCALE  ; VSCALE = 128 → 480px / 8px = 60 řádků
    LDA #$00
    STA VERA_DC_BORDER

    ; --- 3. Layer 0: 1bpp tile mode, mapa 128×64 ---
    ; L0_CONFIG = %01 10 0 0 00 = $60
    ;   MapHeight=01(64 tiles), MapWidth=10(128 tiles), T256C=0, bitmap=0, depth=00(1bpp)
    LDA #$60
    STA VERA_L0_CONFIG
    LDA #$00
    STA VERA_L0_MAPBASE     ; tile mapa na VRAM $00000 (bits 16:9 = 0)
    ; font na VRAM $04000: addr bits 16:11 = 8 → register bits 7:2 = 8<<2 = $20
    ; TileWidth=0 (8px), TileHeight=0 (8px)
    LDA #$20
    STA VERA_L0_TILEBASE    ; tile data na VRAM $04000

    ; --- 4. Upload fontu do VRAM $04000 (128 chars × 8 B = 1024 B) ---
    LDA #$00
    STA VERA_ADDRLO
    LDA #$40            ; VRAM $04000 → ADDRMI=$40, ADDRLO=$00
    STA VERA_ADDRMI
    LDA #$10            ; auto-increment = 1
    STA VERA_ADDRHI

    LDA #<vdp_font
    STA ZP_PTR
    LDA #>vdp_font
    STA ZP_PTR+1
    LDX #4              ; 4 × 256 B = 1024 B
    LDY #0
upload_font:
    LDA (ZP_PTR),Y
    STA VERA_DATA0
    INY
    BNE upload_font     ; 256 B → ADDRMI inkrementujeme ručně
    INC ZP_PTR+1
    DEX
    BNE upload_font

    LDA #<msg_font
    LDX #>msg_font
    JSR ROM_PRINTNL
    LDA #<msg_done      ; tiskni před clear — clear přepíše vše na VERA
    LDX #>msg_done
    JSR ROM_PRINTNL

    ; --- 5. Smaž tile mapu: 128×64 × 2B = 16384 B (space + barva $01) ---
    LDA #$00
    STA VERA_ADDRLO
    STA VERA_ADDRMI
    LDA #$10
    STA VERA_ADDRHI

    LDA #$40            ; 64 řádků (outer loop)
    STA ZP_CNT
clear_row:
    LDX #$80            ; 128 sloupců (inner loop)
clear_col:
    LDA #$20            ; ASCII space
    STA VERA_DATA0
    LDA #$01            ; barva: fg=1 (bílá), bg=0 (černá)
    STA VERA_DATA0
    DEX
    BNE clear_col
    DEC ZP_CNT
    BNE clear_row

    ; --- 6. Zapni display: Layer0 + VGA ---
    LDA #$11            ; Layer0 enable, Output Mode = 1 (VGA)
    STA VERA_DC_VIDEO

    ; --- 7. Vypiš text na obrazovku ---
    LDA #2
    STA ZP_ROW
    LDA #4
    STA ZP_COL
    LDA #<msg_vera
    STA ZP_PTR
    LDA #>msg_vera
    STA ZP_PTR+1
    JSR vera_puts

    LDA #25
    STA ZP_ROW
    LDA #4
    STA ZP_COL
    LDA #<msg_line2
    STA ZP_PTR
    LDA #>msg_line2
    STA ZP_PTR+1
    JSR vera_puts

    RTS

; ============================================================
; vera_puts — vypíše null-terminated string do tile mapy
;
; Vstup:  ZP_PTR = adresa řetězce
;         ZP_ROW = řádek (0–59)
;         ZP_COL = sloupec (0–79)
; Barva:  $01 = bílá na černé
; Ničí:   A, X, Y
; ============================================================
vera_puts:
    ; VRAM addr = (row × 128 + col) × 2 = row × 256 + col × 2
    LDA ZP_ROW
    STA VERA_ADDRMI     ; ADDRMI = row (× 256 díky pozici bajtu)
    LDA ZP_COL
    ASL A               ; col × 2 (každá buňka = 2 B)
    STA VERA_ADDRLO
    LDA #$10
    STA VERA_ADDRHI     ; auto-increment = 1

    LDY #0
@loop:
    LDA (ZP_PTR),Y
    BEQ @done
    STA VERA_DATA0      ; character index
    LDA #$01            ; barva: fg=1 bílá, bg=0 černá
    STA VERA_DATA0
    INY
    BNE @loop
@done:
    RTS

; ============================================================
; Stringy (sériový výstup)
msg_title:  .byte "=== VERA Text Display Test ===", 0
msg_font:   .byte "Font uploaded to VRAM $04000.", 0
msg_done:   .byte "Display active - check VGA monitor.", 0

; Stringy na obrazovku (zobrazí se na VGA)
msg_vera:   .byte "HELLO VERA! PROJECT65 SBC 65C02", 0
msg_line2:  .byte "PROJECT65 SBC 65C02", 0

; ============================================================
; Font data — 128 znaků × 8 B, ASCII 0–127 (z font.asm)
; ============================================================
.include "font.asm"
