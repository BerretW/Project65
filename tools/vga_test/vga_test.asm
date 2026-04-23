; VGA_test.asm — VERA text display test
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
;   ca65 -t none vga_test.asm -o vga_test.o
;   ld65 -t none -S '$3100' vga_test.o -o vga_test.bin   # PowerShell
;   ld65 -t none -S $3100 vga_test.o -o vga_test.bin    # bash/cmd
;   python ../ihex_gen.py vga_test.bin 3100 vga_test.hex

ROM_PRINTNL = $FF18 
VGA_BASE = $C000
REG_CTRL = $00
REG_TXT_PTR_LO = $01
REG_TXT_PTR_HI = $02
REG_TXT_DATA = $03
REG_FONT_PTR_LO = $04
REG_FONT_PTR_HI = $05
REG_FONT_DATA = $06


.org $3100

; ============================================================
start:
; Zapnout video
    LDA #$01
    STA VGA_BASE + REG_CTRL
    LDA #<msg_title
    LDX #>msg_title
    JSR ROM_PRINTNL
    LDA #$01
    STA VGA_BASE          ; zapni textový režim
    RTS

; ============================================================
; Stringy — ACIA status zprávy
msg_title:  .byte "=== VGA Test ===", 0


