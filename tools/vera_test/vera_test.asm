; vera_test.asm — VERA text display test
; Layer 0, 1bpp tile mode, 80×60 text (640×480 VGA, 8×8 font z font.asm)
; Výstup: ACIA sériový port + VERA VGA display (souběžně, bez ROM gr_put_byte)
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

; --- ACIA R6551 (přímý zápis, bez ROM hook) ---
ACIA_DATA   = $C800    ; TX/RX data register
ACIA_STATUS = $C801    ; bit 4 = TDRE (Transmit Data Register Empty)

; --- VERA registry (base $C000, spec v0.9) ---
VERA_ADDRLO  = $C000
VERA_ADDRMI  = $C001
VERA_ADDRHI  = $C002   ; [7:4]=incr step, [3]=DECR, [0]=addr bit 16
VERA_DATA0   = $C003
VERA_CTRL    = $C005   ; [7]=RESET, [1]=DCSEL, [0]=ADDRSEL

VERA_DC_VIDEO   = $C009   ; DCSEL=0: [6]=sprites, [5]=L1, [4]=L0, [1:0]=mode
VERA_DC_HSCALE  = $C00A
VERA_DC_VSCALE  = $C00B
VERA_DC_BORDER  = $C00C

VERA_L0_CONFIG   = $C00D  ; [7:6]=MapH, [5:4]=MapW, [3]=T256C, [2]=bitmap, [1:0]=depth
VERA_L0_MAPBASE  = $C00E  ; addr bits 16:9 of tile map base
VERA_L0_TILEBASE = $C00F  ; [7:2]=addr bits 16:11, [1]=TileH, [0]=TileW

; --- ZP scratch (mimo OS $40–$4E) ---
ZP_PTR  = $F0   ; 2 B — ukazatel na řetězec
ZP_CNT  = $F2   ; 1 B — outer loop counter
ZP_ROW  = $F3   ; 1 B — VERA cursor řádek
ZP_COL  = $F4   ; 1 B — VERA cursor sloupec

.org $3100

; ============================================================
start:
    ; --- Tisk titulku na ACIA (VERA ještě neinicializována) ---
    LDA #<msg_title
    STA ZP_PTR
    LDA #>msg_title
    STA ZP_PTR+1
    JSR acia_puts

    ; --- 1. Palette init: barva 0=černá, barva 1=bílá ---
    ; Palette VRAM base $1FA00, entry formát: byte0=[G:B], byte1=[0:R]
    LDA #$00
    STA VERA_ADDRLO
    LDA #$FA
    STA VERA_ADDRMI
    LDA #$11            ; increment=1, bit16=1 ($1FA00 je nad $FFFF)
    STA VERA_ADDRHI
    LDA #$00
    STA VERA_DATA0      ; barva 0: G=0, B=0
    STA VERA_DATA0      ; barva 0: R=0  → černá
    LDA #$FF
    STA VERA_DATA0      ; barva 1: G=$F, B=$F
    LDA #$0F
    STA VERA_DATA0      ; barva 1: R=$F → bílá

    ; --- 2. Display composer: VGA 1:1 pixel, border černý ---
    LDA #$80            ; HSCALE=128 → 640px/8px=80 sloupců
    STA VERA_DC_HSCALE
    STA VERA_DC_VSCALE  ; VSCALE=128 → 480px/8px=60 řádků
    LDA #$00
    STA VERA_DC_BORDER

    ; --- 3. Layer 0: 1bpp tile mode, mapa 128×64 ---
    ; L0_CONFIG = %01 10 0 0 00 = $60
    LDA #$60
    STA VERA_L0_CONFIG
    LDA #$00
    STA VERA_L0_MAPBASE     ; tile mapa na VRAM $00000 (bits 16:9 = 0)
    LDA #$20                ; VRAM $04000: bits[16:11]=8 → reg[7:2]=8<<2=$20
    STA VERA_L0_TILEBASE

    ; --- 4. Upload fontu → VRAM $04000 (128 chars × 8 B = 1024 B) ---
    LDA #$00
    STA VERA_ADDRLO
    LDA #$40            ; ADDRMI=$40 → VRAM $04000
    STA VERA_ADDRMI
    LDA #$10            ; increment=1, bit16=0
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
    BNE upload_font
    INC ZP_PTR+1
    DEX
    BNE upload_font

    LDA #<msg_font
    STA ZP_PTR
    LDA #>msg_font
    STA ZP_PTR+1
    JSR acia_puts

    ; --- 5. Smaž tile mapu: 128×64×2 B (space + barva $01) ---
    LDA #$00
    STA VERA_ADDRLO
    STA VERA_ADDRMI
    LDA #$10
    STA VERA_ADDRHI

    LDA #$40            ; 64 řádků (outer)
    STA ZP_CNT
clear_row:
    LDX #$80            ; 128 sloupců (inner)
clear_col:
    LDA #$20            ; ASCII space
    STA VERA_DATA0
    LDA #$01            ; barva: fg=1 bílá, bg=0 černá
    STA VERA_DATA0
    DEX
    BNE clear_col
    DEC ZP_CNT
    BNE clear_row

    ; --- 6. Vypiš text do VERA a ACIA (display ještě vypnutý) ---
    LDA #0
    STA ZP_ROW
    STA ZP_COL

    LDA #<msg_vera
    STA ZP_PTR
    LDA #>msg_vera
    STA ZP_PTR+1
    JSR acia_puts       ; → ACIA sériový port
    JSR vera_puts       ; → VERA tile mapa (row 0, col 0)
    INC ZP_ROW

    LDA #<msg_line2
    STA ZP_PTR
    LDA #>msg_line2
    STA ZP_PTR+1
    JSR acia_puts
    JSR vera_puts       ; → VERA tile mapa (row 1, col 0)
    INC ZP_ROW

    ; --- 7. Zapni display: Layer0 + VGA (text se zobrazí najednou) ---
    LDA #$11            ; Layer0 enable, Output Mode=1 (VGA)
    STA VERA_DC_VIDEO

@halt:
    JMP @halt           ; halt — nevrací se do OS

; ============================================================
; vera_puts — null-terminated string → VERA tile mapa
; Vstup:  ZP_PTR = adresa řetězce, ZP_ROW = řádek, ZP_COL = sloupec
; Barva:  fg=1 (bílá), bg=0 (černá)
; Ničí:   A, Y
; ============================================================
vera_puts:
    LDA ZP_ROW
    STA VERA_ADDRMI     ; ADDRMI = row (× 256 díky pozici bajtu)
    LDA ZP_COL
    ASL A               ; col × 2 (každá tile entry = 2 B)
    STA VERA_ADDRLO
    LDA #$10
    STA VERA_ADDRHI     ; increment=1, bit16=0
    LDY #0
@loop:
    LDA (ZP_PTR),Y
    BEQ @done
    STA VERA_DATA0      ; char index
    LDA #$01
    STA VERA_DATA0      ; barva
    INY
    BNE @loop
@done:
    RTS

; ============================================================
; acia_putc — pošle jeden znak na ACIA R6551 (poll TDRE)
; Vstup:  A = znak
; Ničí:   A (zachovává X, Y)
; ============================================================
acia_putc:
    PHA
@wait:
    LDA ACIA_STATUS
    AND #$10            ; bit 4 = TDRE
    BEQ @wait
    PLA
    STA ACIA_DATA
    RTS

; ============================================================
; acia_puts — null-terminated string + CR LF → ACIA
; Vstup:  ZP_PTR = adresa řetězce
; Ničí:   A, Y
; ============================================================
acia_puts:
    LDY #0
@loop:
    LDA (ZP_PTR),Y
    BEQ @crlf
    JSR acia_putc
    INY
    BNE @loop
@crlf:
    LDA #$0D
    JSR acia_putc
    LDA #$0A
    JSR acia_putc
    RTS

; ============================================================
; Stringy — ACIA status zprávy
msg_title:  .byte "=== VERA Text Display Test ===", 0
msg_font:   .byte "Font uploaded to VRAM $04000.", 0

; Stringy — VERA + ACIA výstup
msg_vera:   .byte "HELLO VERA!", 0
msg_line2:  .byte "PROJECT65 SBC 65C02", 0

; ============================================================
; Font data — 128 znaků × 8 B, ASCII 0–127 (z font.asm)
; ============================================================
.include "font.asm"
