; vera_test.asm — Test přítomnosti VERA čipu v systému
;
; Detekce: write/readback pattern $A5/$5A na VERA registry.
; Při selhání vypíše číslo kroku, přečtenou hodnotu a očekávanou hodnotu.
;
; Sestavení:
;   ca65 -t none vera_test.asm -o vera_test.o
;   ld65 -t none -S '$3100' vera_test.o -o vera_test.bin   # PowerShell
;   ld65 -t none -S $3100 vera_test.o -o vera_test.bin    # bash/cmd
;   python ../ihex_gen.py vera_test.bin 3100 vera_test.hex
;
; Použití v AppartusOS:
;   LOAD              ← pošli vera_test.hex
;   SAVE VERATEST 3100 0100
;   RUN VERATEST

; --- ROM API ---
ROM_PUTS    = $FF0C   ; print null-terminated string (A=lo, X=hi)
ROM_PRINTNL = $FF18   ; print string + CR+LF (A=lo, X=hi)
ROM_PUTC    = $FF09   ; print char in A
ROM_PRTBYTE = $FF1B   ; print A as 2 hex digits
ROM_PUTNL   = $FF15   ; send CR+LF

; --- VERA registry ---
VERA_ADDRLO = $C300
VERA_ADDRMI = $C301
VERA_ADDRHI = $C302
VERA_DATA0  = $C303
VERA_DATA1  = $C304
VERA_CTRL   = $C305
VERA_IEN    = $C306
VERA_ISR    = $C307

; --- ZP scratch (mimo OS ZP $40–$53) ---
ZP_GOT      = $F0     ; přečtená hodnota
ZP_EXP      = $F1     ; očekávaná hodnota

.org $3100

; ============================================================
start:
    LDA #<msg_title
    LDX #>msg_title
    JSR ROM_PRINTNL

    ; ── Krok 1: soft-reset VERA, ADDRLO musí být $00 ─────────
    LDA #$80
    STA VERA_CTRL
    LDA #$00
    STA VERA_CTRL

    LDA VERA_ADDRLO
    STA ZP_GOT
    LDA #$00
    STA ZP_EXP
    LDA ZP_GOT
    BNE fail1

    ; ── Krok 2: ADDRLO write/readback $A5 ────────────────────
    LDA #$A5
    STA VERA_ADDRLO
    LDA VERA_ADDRLO
    STA ZP_GOT
    LDA #$A5
    STA ZP_EXP
    LDA ZP_GOT
    CMP #$A5
    BNE fail2

    ; ── Krok 3: ADDRLO write/readback $5A ────────────────────
    LDA #$5A
    STA VERA_ADDRLO
    LDA VERA_ADDRLO
    STA ZP_GOT
    LDA #$5A
    STA ZP_EXP
    LDA ZP_GOT
    CMP #$5A
    BNE fail3

    ; ── Krok 4: ADDRMI write/readback $A5 ────────────────────
    LDA #$A5
    STA VERA_ADDRMI
    LDA VERA_ADDRMI
    STA ZP_GOT
    LDA #$A5
    STA ZP_EXP
    LDA ZP_GOT
    CMP #$A5
    BNE fail4

    ; ── Krok 5: ADDRHI write/readback $03 ────────────────────
    LDA #$03
    STA VERA_ADDRHI
    LDA VERA_ADDRHI
    AND #$0F            ; ADDRHI: bity 7-4 jsou incr/dec, čteme jen spodní
    STA ZP_GOT
    LDA #$03
    STA ZP_EXP
    LDA ZP_GOT
    CMP #$03
    BNE fail5

; ── Vše prošlo ───────────────────────────────────────────────
detect_ok:
    LDA #<msg_ok
    LDX #>msg_ok
    JSR ROM_PRINTNL

    LDA #<msg_isr_lbl
    LDX #>msg_isr_lbl
    JSR ROM_PUTS
    LDA VERA_ISR
    JSR ROM_PRTBYTE
    JSR ROM_PUTNL

    ; Vyčisti adresní registry
    LDA #$00
    STA VERA_ADDRLO
    STA VERA_ADDRMI
    STA VERA_ADDRHI

    RTS

; ── Fail větve — každá nastaví msg_stepX a padne do debug_fail
fail1:
    LDA #<msg_s1
    LDX #>msg_s1
    JMP debug_fail
fail2:
    LDA #<msg_s2
    LDX #>msg_s2
    JMP debug_fail
fail3:
    LDA #<msg_s3
    LDX #>msg_s3
    JMP debug_fail
fail4:
    LDA #<msg_s4
    LDX #>msg_s4
    JMP debug_fail
fail5:
    LDA #<msg_s5
    LDX #>msg_s5
    JMP debug_fail

; ── Společný fail výpis ───────────────────────────────────────
debug_fail:
    JSR ROM_PUTS            ; vytiskne "FAIL krok N: "

    LDA #<msg_got
    LDX #>msg_got
    JSR ROM_PUTS
    LDA ZP_GOT
    JSR ROM_PRTBYTE         ; vytiskne přečtenou hodnotu jako hex

    LDA #<msg_exp
    LDX #>msg_exp
    JSR ROM_PUTS
    LDA ZP_EXP
    JSR ROM_PRTBYTE         ; vytiskne očekávanou hodnotu jako hex

    JSR ROM_PUTNL
    RTS

; ── Stringy ──────────────────────────────────────────────────
msg_title:   .byte "=== VERA Detection Test ===", 0
msg_ok:      .byte "VERA OK — chip detected and responding.", 0
msg_isr_lbl: .byte "  ISR = $", 0
msg_got:     .byte "  got=$", 0
msg_exp:     .byte " exp=$", 0

msg_s1: .byte "FAIL step 1 (reset ADDRLO != $00):", 0
msg_s2: .byte "FAIL step 2 (ADDRLO w/r $A5):", 0
msg_s3: .byte "FAIL step 3 (ADDRLO w/r $5A):", 0
msg_s4: .byte "FAIL step 4 (ADDRMI w/r $A5):", 0
msg_s5: .byte "FAIL step 5 (ADDRHI w/r $03):", 0
