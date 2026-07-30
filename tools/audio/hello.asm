; ==============================================================================
; VGA_BUS AUDIO DEMO FOR Project65 (65C02 SBC)
; ==============================================================================
; Tento program demonstruje použití nového zvukového ovladače "audio.inc"
; na kartě vga_bus. Program postupně:
; 1. Inicializuje zvukový subsystém
; 2. Přehraje jednoduchou polyfonní znělku (Sinusová hlavní melodie + Trojúhelníkový bas)
; 3. Předvede hru akordu na 3 kanálech současně s ADSR obálkami
; 4. Přehraje ukázkové systémové pípnutí (beep)
; 5. Ukončí se a vrátí řízení systému
; ==============================================================================

.setcpu "65C02"

; Adresa spuštění programu (kompilace pro $3000)
.org $3000

jmp start

; --- Import ROM rutin pro výpis na sériový port ---
ROM_PRINTLN = $FF18
ROM_PUTNL   = $FF15

; --- Dočasné proměnné v Zero Page ---
tmp_duration = $60
tmp_y        = $61

; --- Vložení audio ovladače ---
.include "audio.inc"

; --- Textové zprávy ---
msg_welcome: .byte "VGA_BUS Audio Demo - Project65", 13, 10, 0
msg_playing: .byte "Prehravam Ódu na radost...", 13, 10, 0
msg_chord:   .byte "Prehravam akord C-dur s ADSR obalkou...", 13, 10, 0
msg_beep:    .byte "Prehravam systemove pipnuti (beep)...", 13, 10, 0
msg_done:    .byte "Hotovo. Vracim rizeni.", 13, 10, 0
msg_checkpoint: .byte "Checkpoint reached.", 13, 10, 0

start:
    ; 1. Vytisknout uvítací zprávu
    LDA #<msg_welcome
    LDX #>msg_welcome
    JSR ROM_PRINTLN

    ; 2. Inicializace zvukového čipu
    JSR audio_init
    lda #<msg_checkpoint
    ldx #>msg_checkpoint
    JSR ROM_PRINTLN
    ; 3. Nastavení parametrů pro hlavní melodii (Kanál 0)
    ; Wave: Sinus, Hlasitost: 160, ADSR: Attack=okamžitý (F), Decay=krátký (4), Sustain=plný (F), Release=rychlý (4)
    LDA #0              ; Kanál 0
    LDX #160            ; Hlasitost (max 255)
    JSR audio_set_vol
    lda #<msg_checkpoint
    ldx #>msg_checkpoint
    JSR ROM_PRINTLN
    LDA #0
    LDX #$F4            ; Attack = F (okamžitý), Decay = 4 (krátký)
    LDY #$F4            ; Sustain = F (plný), Release = 4 (rychlý)
    JSR audio_set_adsr
    lda #<msg_checkpoint
    ldx #>msg_checkpoint
    JSR ROM_PRINTLN
    ; Kontrolní registr: Sine (3) + ADSR povolit ($08) + Gate Note Off ($00) = $0B
    LDA #0
    LDX #(WAVE_SINE | ADSR_ON)
    JSR audio_set_ctrl
    lda #<msg_checkpoint
    ldx #>msg_checkpoint
    JSR ROM_PRINTLN
    ; 4. Nastavení parametrů pro doprovodný bas (Kanál 1)
    ; Wave: Trojúhelník, Hlasitost: 120, ADSR vypnuto (flat zvuk)
    LDA #1              ; Kanál 1
    LDX #120            ; Hlasitost
    JSR audio_set_vol
    lda #<msg_checkpoint
    ldx #>msg_checkpoint
    JSR ROM_PRINTLN
    LDA #1
    LDX #(WAVE_TRIANGLE | ADSR_OFF)
    JSR audio_set_ctrl
    lda #<msg_checkpoint
    ldx #>msg_checkpoint
    JSR ROM_PRINTLN
    ; 5. Přehrání melodie (Óda na radost)
    LDA #<msg_playing
    LDX #>msg_playing
    JSR ROM_PRINTLN

    LDY #0              ; Index v tabulce melodie
play_loop:
    ; Načtení frekvence tónu (Freq Lo)
    LDA melody_data, Y
    CMP #$FF
    BNE @not_end
    INY
    LDA melody_data, Y
    CMP #$FF
    BEQ end_melody       ; Pokud je tón $FFFF -> konec melodie
    DEY

@not_end:
    TAX                 ; X = Freq Lo
    INY
    LDA melody_data, Y
    PHA                 ; Ulož Freq Hi na zásobník
    INY
    LDA melody_data, Y  ; A = délka tónu * 10 ms
    STA tmp_duration
    INY
    STY tmp_y           ; Uložit index Y

    ; --- Spustit hlavní tón (Kanál 0) ---
    LDA #0              ; Kanál 0
    PLY                 ; Y = Freq Hi
    JSR audio_set_freq
    LDA #0
    JSR audio_play_note

    ; --- Spustit basový doprovod na Kanálu 1 (podle hlavního tónu, o oktávu níž) ---
    ; Basový doprovod hrajeme jen na vybrané tóny (např. začátky taktů),
    ; nebo jednoduše doplňujeme tón o oktávu níž pro plnější zvuk.
    ; Pro basový tón jednoduše vezmeme hlavní frekvenci a posuneme ji o 1 bit doprava (f/2)
    TYA                 ; A = Freq Hi
    LSR                 ; Rotace doprava
    TAY                 ; Y = nová Freq Hi
    TXA                 ; A = Freq Lo
    ROR                 ; Rotace s přenosem z high bytu
    TAX                 ; X = nová Freq Lo
    
    LDA #1              ; Kanál 1
    JSR audio_set_freq
    LDA #1
    JSR audio_play_note ; Spustit basový doprovod

    ; --- Čekání po dobu délky tónu ---
@duration_loop:
    LDX #10             ; 10 ms
    LDY #0
    JSR audio_delay_ms
    DEC tmp_duration
    BNE @duration_loop

    ; --- Zastavit tóny (Note Off) ---
    LDA #0              ; Kanál 0
    JSR audio_stop_note
    LDA #1              ; Kanál 1
    JSR audio_stop_note

    ; Krátká mezera pro zřetelné oddělení tónů (artikulace)
    LDX #30
    LDY #0
    JSR audio_delay_ms

    ; Obnovit index a pokračovat
    LDY tmp_y
    JMP play_loop

end_melody:
    JSR audio_init      ; Umlčet kanály po dohrání

    ; 6. Přehrání akordu C-dur (Kanál 0: C4, Kanál 1: E4, Kanál 2: G4)
    ; Ukázka polyfonní hry s pomalým náběhem (Pad / Brass sound)
    LDA #<msg_chord
    LDX #>msg_chord
    JSR ROM_PRINTLN

    ; Nastavení parametrů ADSR: Pomalý náběh (Attack=4), střední Decay=8, Sustain=A (cca 60%), dlouhé doznění (Release=6)
    ; ADSR_AD = $48, ADSR_SR = $A6
    ; Wave: Sawtooth (Pila - dává bohatý harmonický zvuk vhodný pro akordy)
    
    ; Kanál 0 (C4)
    LDA #0
    LDX #<TONE_C4
    LDY #>TONE_C4
    JSR audio_set_freq
    LDA #0
    LDX #150
    JSR audio_set_vol
    LDA #0
    LDX #$48
    LDY #$A6
    JSR audio_set_adsr
    LDA #0
    LDX #(WAVE_SAWTOOTH | ADSR_ON | GATE_ON)
    JSR audio_set_ctrl

    ; Kanál 1 (E4)
    LDA #1
    LDX #<TONE_E4
    LDY #>TONE_E4
    JSR audio_set_freq
    LDA #1
    LDX #150
    JSR audio_set_vol
    LDA #1
    LDX #$48
    LDY #$A6
    JSR audio_set_adsr
    LDA #1
    LDX #(WAVE_SAWTOOTH | ADSR_ON | GATE_ON)
    JSR audio_set_ctrl

    ; Kanál 2 (G4)
    LDA #2
    LDX #<TONE_G4
    LDY #>TONE_G4
    JSR audio_set_freq
    LDA #2
    LDX #150
    JSR audio_set_vol
    LDA #2
    LDX #$48
    LDY #$A6
    JSR audio_set_adsr
    LDA #2
    LDX #(WAVE_SAWTOOTH | ADSR_ON | GATE_ON)
    JSR audio_set_ctrl

    ; Držíme akord po dobu 2.5 sekundy
    LDX #250            ; 250 * 10 ms = 2500 ms
@chord_hold:
    PHA
    LDX #10
    LDY #0
    JSR audio_delay_ms
    PLA
    DEX
    BNE @chord_hold

    ; Uvolníme klávesy (Note Off) - tóny plynule doznějí díky Release fázi (Release=6)
    LDA #0
    JSR audio_stop_note
    LDA #1
    JSR audio_stop_note
    LDA #2
    JSR audio_stop_note

    ; Počkáme 1.5 sekundy na kompletní doznění zvuku
    LDX #150            ; 150 * 10 ms = 1500 ms
@chord_fade:
    PHA
    LDX #10
    LDY #0
    JSR audio_delay_ms
    PLA
    DEX
    BNE @chord_fade

    JSR audio_init      ; Umlčení

    ; 7. Přehrajeme systémové pípnutí (beep)
    LDA #<msg_beep
    LDX #>msg_beep
    JSR ROM_PRINTLN

    JSR audio_beep

    ; 8. Konec programu
    LDA #<msg_done
    LDX #>msg_done
    JSR ROM_PRINTLN
    JSR ROM_PUTNL

    RTS                 ; Návrat zpět do operačního systému / monitoru

; --- Hudební data Ódy na radost ---
; Každá nota má formát: .word [Frekvenční konstanta], .byte [Délka v desítkách ms]
melody_data:
    ; Takt 1
    .word TONE_E4, 40
    .word TONE_E4, 40
    .word TONE_F4, 40
    .word TONE_G4, 40
    ; Takt 2
    .word TONE_G4, 40
    .word TONE_F4, 40
    .word TONE_E4, 40
    .word TONE_D4, 40
    ; Takt 3
    .word TONE_C4, 40
    .word TONE_C4, 40
    .word TONE_D4, 40
    .word TONE_E4, 40
    ; Takt 4
    .word TONE_E4, 60
    .word TONE_D4, 20
    .word TONE_D4, 80
    ; Takt 5
    .word TONE_E4, 40
    .word TONE_E4, 40
    .word TONE_F4, 40
    .word TONE_G4, 40
    ; Takt 6
    .word TONE_G4, 40
    .word TONE_F4, 40
    .word TONE_E4, 40
    .word TONE_D4, 40
    ; Takt 7
    .word TONE_C4, 40
    .word TONE_C4, 40
    .word TONE_D4, 40
    .word TONE_E4, 40
    ; Takt 8
    .word TONE_D4, 60
    .word TONE_C4, 20
    .word TONE_C4, 80

    ; Konec melodie
    .word $FFFF
