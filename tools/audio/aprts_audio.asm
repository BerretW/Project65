; ==============================================================================
; VGA_BUS AUDIO DRIVER FOR 6502 (ca65)
; ==============================================================================
; Ovladač (driver) pro 4-kanálový zvukový generátor integrovaný ve VGA kartě
; na sběrnici vga_bus desky Project65 (SBC 65C02 IRQ BigBoard).
;
; Hardwarová specifikace zvuku v FPGA:
; - 4 nezávislé kanály (0 až 3)
; - DDS generátor se vzorkovací frekvencí Fs = 48.828 kHz
; - Podpora vlnových průběhů: Obdélník, Trojúhelník, Pila, Sinus, Trapéz
; - Každý kanál má plnou hardwarovou ADSR obálku (Attack, Decay, Sustain, Release)
; - Registrově nepřímé rozhraní přes porty:
;   * AUD_ADDR ($CF05) - zápis vnitřní adresy registru (0-23)
;   * AUD_DATA ($CF06) - zápis/čtení hodnoty vybraného registru (auto-inkrement)
; ==============================================================================
          .setcpu		"65C02"
          .smart		on
          .autoimport	on

.include "audio.inc65"
          .export audio_init
          .export  audio_set_freq
          .export  audio_set_vol
          .export  audio_set_ctrl
          .export  audio_set_adsr
          .export  audio_play_note
          .export  audio_stop_note
          .export  audio_beep
          .export  audio_delay_ms


; ==============================================================================
; API FUNKCE DRIVERU
; ==============================================================================

; ------------------------------------------------------------------------------
; audio_init: Inicializace zvuku. Umlčí a vyresetuje všechny 4 kanály.
; Vstupy: Žádné
; Mění: A, X
; ------------------------------------------------------------------------------
audio_init:
    LDA #0
    STA AUD_ADDR        ; Nastav vnitřní ukazatel na první registr ($00)
    LDX #24             ; Máme celkem 24 vnitřních registrů ($00 až $17)
@init_loop:
    LDA #0
    STA AUD_DATA        ; Zapiš 0 (vynuluje nastavení, auto-inkrementuje adresu)
    DEX
    BNE @init_loop
    RTS

; ------------------------------------------------------------------------------
; audio_set_freq: Nastaví frekvenci pro zadaný kanál.
; Vstupy: A = index kanálu (0-3)
;         X = spodní byte frekvence (Freq Lo)
;         Y = horní byte frekvence (Freq Hi)
; Mění: A
; ------------------------------------------------------------------------------
audio_set_freq:
    STA audio_tmp       ; Uložit index kanálu
    ASL                 ; A * 2 (C je 0, protože A je max 3)
    ADC audio_tmp       ; A * 3
    STA AUD_ADDR        ; Nastav vnitřní adresu
    STX AUD_DATA        ; Zapiš Freq Lo (adresa se posune o +1)
    STY AUD_DATA        ; Zapiš Freq Hi
    RTS

; ------------------------------------------------------------------------------
; audio_set_vol: Nastaví hlasitost (Volume) pro zadaný kanál.
; Vstupy: A = index kanálu (0-3)
;         X = hlasitost (0 až 255)
; Mění: A
; ------------------------------------------------------------------------------
audio_set_vol:
    STA audio_tmp       ; Uložit index kanálu
    ASL                 ; A * 2
    ADC audio_tmp       ; A * 3
    CLC
    ADC #2              ; A * 3 + 2 (adresa registru Volume pro daný kanál)
    STA AUD_ADDR
    STX AUD_DATA        ; Zapiš hlasitost
    RTS

; ------------------------------------------------------------------------------
; audio_set_ctrl: Nastaví řídicí registr (Waveform, ADSR enable, Gate) pro kanál.
; Vstupy: A = index kanálu (0-3)
;         X = hodnota řídicího registru (bity [2:0] Wave, [3] ADSR, [4] Gate)
; Mění: A
; ------------------------------------------------------------------------------
audio_set_ctrl:
    CLC
    ADC #$0C            ; Adresy reg_ctrl jsou od $0C do $0F
    STA AUD_ADDR
    STX AUD_DATA        ; Zapiš hodnotu
    RTS

; ------------------------------------------------------------------------------
; audio_set_adsr: Nastaví hardwarové obálky ADSR pro zadaný kanál.
; Vstupy: A = index kanálu (0-3)
;         X = Attack/Decay rychlost (horní 4 bity Attack, spodní 4 bity Decay)
;         Y = Sustain/Release nastavení (horní 4 bity Sustain Lvl, spodní 4 bity Release)
; Mění: A
; ------------------------------------------------------------------------------
audio_set_adsr:
    STA audio_tmp       ; Uložit index kanálu
    ASL                 ; A * 2
    CLC
    ADC #$10            ; Adresa adsr_ad začíná na $10 (pak $12, $14, $16)
    STA AUD_ADDR
    STX AUD_DATA        ; Zapiš Attack/Decay (adresa se posune na Sustain/Release)
    STY AUD_DATA        ; Zapiš Sustain/Release
    RTS

; ------------------------------------------------------------------------------
; audio_play_note (Note On): Spustí tón na zadaném kanálu (nastaví bit Gate na 1).
; Vstupy: A = index kanálu (0-3)
; Mění: A
; ------------------------------------------------------------------------------
audio_play_note:
    CLC
    ADC #$0C            ; Získat adresu reg_ctrl pro vybraný kanál ($0C až $0F)
    STA AUD_ADDR
    LDA AUD_DATA        ; Přečíst aktuální hodnotu (nedestruktivní z hlediska aud_addr)
    ORA #GATE_ON        ; Nastavit bit 4 (Gate = 1)
    STA AUD_DATA        ; Zapsat upravenou hodnotu zpět
    RTS

; ------------------------------------------------------------------------------
; audio_stop_note (Note Off): Zastaví tón na zadaném kanálu (vynuluje bit Gate).
; Vstupy: A = index kanálu (0-3)
; Mění: A
; ------------------------------------------------------------------------------
audio_stop_note:
    CLC
    ADC #$0C            ; Získat adresu reg_ctrl pro vybraný kanál
    STA AUD_ADDR
    LDA AUD_DATA        ; Přečíst aktuální hodnotu
    AND #<(~GATE_ON)    ; Vynulovat bit 4 (Gate = 0)
    STA AUD_DATA        ; Zapsat zpět
    RTS

; ------------------------------------------------------------------------------
; audio_beep: Přehraje krátké jednoduché pípnutí na kanálu 0 (bez nutnosti složitého nastavování).
; Vstupy: Žádné
; Mění: A, X, Y
; ------------------------------------------------------------------------------
audio_beep:
    JSR audio_init      ; Reset zvuku
    
    ; Nastavit frekvenci na A5 (880 Hz) pro kanál 0
    LDA #0
    LDX #<TONE_A5
    LDY #>TONE_A5
    JSR audio_set_freq
    
    ; Nastavit hlasitost kanálu 0 na max
    LDA #0
    LDX #180
    JSR audio_set_vol

    ; Nastavit ADSR obálku: Attack=okamžitý (F), Decay=střední (8) -> $F8
    ;                     Sustain=0 (pípnutí dohasne), Release=střední (8) -> $08
    LDA #0
    LDX #$F8
    LDY #$08
    JSR audio_set_adsr

    ; Spustit tón se zapnutou ADSR obálkou a vlnou Sinus (3)
    ; Ctrl: Sine (3) | ADSR_ON ($08) | GATE_ON ($10) = $1B
    LDA #0
    LDX #($03 | ADSR_ON | GATE_ON)
    JSR audio_set_ctrl

    ; Počkat cca 150 ms na doznění pípnutí
    LDX #150
    LDY #0
    JSR audio_delay_ms

    ; Zastavit tón (Release fáze)
    LDA #0
    JSR audio_stop_note

    RTS

; ------------------------------------------------------------------------------
; audio_delay_ms: Softwarové čekání po zadanou dobu (ms) pro CPU o taktu 1 MHz.
; Vstupy: X = spodní byte času (ms)
;         Y = horní byte času (ms)
; Mění: A, X, Y
; ------------------------------------------------------------------------------
audio_delay_ms:
    PHA
    PHX
    PHY                 ; Zachovat původní registry na zásobníku (65C02 instrukce)
@loop_ms:
    PHA
    LDA #198            ; Vnitřní smyčka na cca 1 ms (při 1 MHz CPU)
@inner:
    DEC
    BNE @inner          ; 198 * 5 = 990 taktů + režie = 1000 taktů (1 ms)
    PLA
    
    ; Snížení 16bitového čítače X/Y
    TXA                 ; Otestujeme zda X je 0
    BNE @dec_x          ; Pokud ne, snížíme X
    CPY #0              ; Pokud X je 0, otestujeme zda Y je 0
    BEQ @done           ; Pokud obě jsou 0, máme hotovo!
    DEY                 ; Snížíme Y
    LDX #$FF            ; Nastavíme X na $FF
    JMP @loop_ms
@dec_x:
    DEX
    JMP @loop_ms
@done:
    PLY                 ; Obnovit registry v opačném pořadí
    PLX
    PLA
    RTS

