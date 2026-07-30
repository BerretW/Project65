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

.ifndef AUDIO_INC
AUDIO_INC = 1

; --- Hardwarové porty audio řadiče ---
AUD_BASE = $CE00
AUD_ADDR = AUD_BASE + 5     ; Registrová adresa ($CF05)
AUD_DATA = AUD_BASE + 6     ; Registrová data ($CF06)

; --- Konstanty typů vlnových průběhů (Waveforms) ---
WAVE_SQUARE   = 0   ; Obdélníková vlna
WAVE_TRIANGLE = 1   ; Trojúhelníková vlna
WAVE_SAWTOOTH = 2   ; Pilový průběh
WAVE_SINE     = 3   ; Sinusoida
WAVE_TRAPEZOID = 4  ; Trapézový / lichoběžníkový průběh

; --- Konstanty pro řízení obálky a tónu ---
ADSR_OFF = $00
ADSR_ON  = $08      ; Povolení ADSR obálky (bit 3)
GATE_OFF = $00
GATE_ON  = $10      ; Spuštění tónu / Note On (bit 4)

; --- Frekvenční tabulka tónů (16-bit DDS doplňovací slova) ---
; Vypočteno jako: S = f_out * 65536 / 48828.125 = f_out * 1.342177

; 3. oktáva (basová)
TONE_C3  = $00B0    ; 130.81 Hz
TONE_CS3 = $00BA    ; 138.59 Hz
TONE_D3  = $00C5    ; 146.83 Hz
TONE_DS3 = $00D1    ; 155.56 Hz
TONE_E3  = $00DD    ; 164.81 Hz
TONE_F3  = $00EA    ; 174.61 Hz
TONE_FS3 = $00F8    ; 185.00 Hz
TONE_G3  = $0107    ; 196.00 Hz
TONE_GS3 = $0116    ; 207.65 Hz
TONE_A3  = $0127    ; 220.00 Hz
TONE_AS3 = $0138    ; 233.08 Hz
TONE_B3  = $014B    ; 246.94 Hz

; 4. oktáva (jednočárkovaná - komorní A = 440 Hz)
TONE_C4  = $015F    ; 261.63 Hz (střední C)
TONE_CS4 = $0174    ; 277.18 Hz
TONE_D4  = $018A    ; 293.66 Hz
TONE_DS4 = $01A2    ; 311.13 Hz
TONE_E4  = $01BA    ; 329.63 Hz
TONE_F4  = $01D5    ; 349.23 Hz
TONE_FS4 = $01F1    ; 369.99 Hz
TONE_G4  = $020E    ; 392.00 Hz
TONE_GS4 = $022D    ; 415.30 Hz
TONE_A4  = $024F    ; 440.00 Hz
TONE_AS4 = $0272    ; 466.16 Hz
TONE_B4  = $0297    ; 493.88 Hz

; 5. oktáva (dvoučárkovaná)
TONE_C5  = $02BE    ; 523.25 Hz
TONE_CS5 = $02E8    ; 554.37 Hz
TONE_D5  = $0314    ; 587.33 Hz
TONE_DS5 = $0343    ; 622.25 Hz
TONE_E5  = $0375    ; 659.25 Hz
TONE_F5  = $03A9    ; 698.46 Hz
TONE_FS5 = $03E1    ; 739.99 Hz
TONE_G5  = $041C    ; 783.99 Hz
TONE_GS5 = $045B    ; 830.61 Hz
TONE_A5  = $049D    ; 880.00 Hz
TONE_AS5 = $04E3    ; 932.33 Hz
TONE_B5  = $052E    ; 987.77 Hz

; 6. oktáva (tříčárkovaná)
TONE_C6  = $057D    ; 1046.50 Hz
TONE_D6  = $0628    ; 1174.66 Hz
TONE_E6  = $06EA    ; 1318.51 Hz
TONE_F6  = $0752    ; 1396.91 Hz
TONE_G6  = $0837    ; 1567.98 Hz
TONE_A6  = $093B    ; 1760.00 Hz
TONE_B6  = $0A5D    ; 1975.53 Hz

; Pauza (vypnutá hlasitost / ticho)
TONE_REST = $0000

; --- Makra a pomocné definice pro ADSR hodnoty ---
; Rychlosti Attack/Decay/Release (0-15: 0=nejpomalé, 15=okamžité)
; Úroveň Sustain (0-15: 0=ticho, 15=plná hlasitost)
; Formát registru ADSR_AD: [7:4] Attack Rate, [3:0] Decay Rate
; Formát registru ADSR_SR: [7:4] Sustain Level, [3:0] Release Rate


; --- Dočasná proměnná pro výpočty v nulové stránce ---
audio_tmp = $62

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

.endif ; AUDIO_INC
