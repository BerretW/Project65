; vera_test.asm — VERA VRAM write test
; Adapted from original author's code (Frank van den Hoef); VERA base $8000 → $C000
;
; Registers per VERA Programmer's Reference v0.9:
;   $00 ADDRx_L   $01 ADDRx_M   $02 ADDRx_H   $03 DATA0   $04 DATA1
;   $05 CTRL      $06 IEN       $07 ISR        $08 IRQLINE_L / SCANLINE_L
;   $09 DC_VIDEO  $0A DC_HSCALE $0B DC_VSCALE  $0C DC_BORDER
;
; Sestavení:
;   ca65 -t none vera_test.asm -o vera_test.o
;   ld65 -t none -S '$3100' vera_test.o -o vera_test.bin   # PowerShell
;   ld65 -t none -S $3100 vera_test.o -o vera_test.bin    # bash/cmd
;   python ../ihex_gen.py vera_test.bin 3100 vera_test.hex
;
; Použití v AppartusOS:
;   LOAD              ← pošli vera_test.hex
;   SAVE VERATEST 3100 0080
;   RUN VERATEST

; --- ROM API ---
ROM_PUTS    = $FF0C   ; print null-terminated string (A=lo, X=hi)
ROM_PRINTNL = $FF18   ; print string + CR+LF (A=lo, X=hi)
ROM_PUTC    = $FF09   ; print char in A
ROM_PRTBYTE = $FF1B   ; print A as 2 hex digits
ROM_PUTNL   = $FF15   ; send CR+LF

; --- VERA registry ($C000 base, dle spec v0.9) ---
VERA_ADDRLO  = $C000   ; VRAM address (7:0)
VERA_ADDRMI  = $C001   ; VRAM address (15:8)
VERA_ADDRHI  = $C002   ; [7:4]=Address Increment, [3]=DECR, [0]=addr bit 16
VERA_DATA0   = $C003   ; VRAM data port 0
VERA_DATA1   = $C004   ; VRAM data port 1
VERA_CTRL    = $C005   ; [7]=RESET, [1]=DCSEL, [0]=ADDRSEL
VERA_IEN     = $C006
VERA_ISR     = $C007

; Display composer registry (DCSEL=0, base+$09)
VERA_DC_VIDEO  = $C009   ; [6]=Sprites, [5]=L1, [4]=L0, [1:0]=OutMode (1=VGA)
VERA_DC_HSCALE = $C00A   ; 128 = 1:1
VERA_DC_VSCALE = $C00B

.org $3100

; ============================================================
; Test 1 — fill VRAM from address $000010:
;   256× (character=X, color=$6E) + loop2 spaces
;   (originální kod autora; ADDRHI=0 → auto-increment=0,
;    všechny zápisy míří na adresu $000010)
; ============================================================
start:
    LDA #<msg_title
    LDX #>msg_title
    JSR ROM_PRINTNL

    LDA #$10
    STA VERA_ADDRLO   ; VRAM low address = $10
    LDA #$00
    STA VERA_ADDRMI   ; VRAM mid address = $00
    STA VERA_ADDRHI   ; VRAM high + auto-increment = 0
    LDX #0
    LDA #$11
    STA VERA_DC_VIDEO
loop1:
    TXA
    STA VERA_DATA0    ; character = X
    LDA #$6E
    STA VERA_DATA0    ; color = $6E
    INX
    BNE loop1

    LDY #10
loop2:
    LDA #$20
    STA VERA_DATA0    ; space
    LDA #$6E
    STA VERA_DATA0    ; color
    INX
    BNE loop2

    LDA #<msg_t1
    LDX #>msg_t1
    JSR ROM_PRINTNL

; ============================================================
; Test 2 — write char $02 at $000010 twice
; ============================================================
    LDA #$10
    STA VERA_ADDRLO
    LDA #$00
    STA VERA_ADDRMI
    STA VERA_ADDRHI
    LDX #79           ; column (pro budoucí výpočet adresy)
    LDA #$02

    STA VERA_DATA0
    STA VERA_DATA0

    LDA #<msg_t2
    LDX #>msg_t2
    JSR ROM_PRINTNL

    RTS

; --- Stringy ---
msg_title: .byte "=== VERA VRAM Write Test ===", 0
msg_t1:    .byte "Test 1 OK: char+color pairs written.", 0
msg_t2:    .byte "Test 2 OK: char $02 written.", 0
