AUD_BASE = $CE00
AUD_ADDR = AUD_BASE + 5
AUD_DATA = AUD_BASE + 6

play_chord:
    ; 1. Vynulujeme index vnitřního registru
    LDA #0
    STA AUD_ADDR

    ; 2. Kanál 0: tón C4 (261 Hz, hodnota S = 351 = $015F), hlasitost 128 (50%)
    LDA #$5F
    STA AUD_DATA        ; Zapíše se do indexu 0x0 (reg_freq_lo_0), index se inkrementuje na 0x1
    LDA #$01
    STA AUD_DATA        ; Zapíše se do indexu 0x1 (reg_freq_hi_0), index se inkrementuje na 0x2
    LDA #128
    STA AUD_DATA        ; Zapíše se do indexu 0x2 (reg_vol_0), index se inkrementuje na 0x3

    ; ; 3. Kanál 1: tón E4 (329 Hz, hodnota S = 442 = $01BA), hlasitost 128 (50%)
    ; LDA #$BA
    ; STA AUD_DATA        ; Zapíše se do indexu 0x3 (reg_freq_lo_1), index se inkrementuje na 0x4
    ; LDA #$01
    ; STA AUD_DATA        ; Zapíše se do indexu 0x4 (reg_freq_hi_1), index se inkrementuje na 0x5
    ; LDA #128
    ; STA AUD_DATA        ; Zapíše se do indexu 0x5 (reg_vol_1), index se inkrementuje na 0x6

    ; ; 4. Kanál 2: tón G4 (392 Hz, hodnota S = 526 = $020E), hlasitost 128 (50%)
    ; LDA #$0E
    ; STA AUD_DATA        ; Zapíše se do indexu 0x6 (reg_freq_lo_2), index se inkrementuje na 0x7
    ; LDA #$02
    ; STA AUD_DATA        ; Zapíše se do indexu 0x7 (reg_freq_hi_2), index se inkrementuje na 0x8
    ; LDA #128
    ; STA AUD_DATA        ; Zapíše se do indexu 0x8 (reg_vol_2), index se inkrementuje na 0x9

    ; ; 5. Kanál 3: tón C5 (523 Hz, hodnota S = 702 = $02BE), hlasitost 128 (50%)
    ; LDA #$BE
    ; STA AUD_DATA        ; Zapíše se do indexu 0x9 (reg_freq_lo_3), index se inkrementuje na 0xA
    ; LDA #$02
    ; STA AUD_DATA        ; Zapíše se do indexu 0xA (reg_freq_hi_3), index se inkrementuje na 0xB
    ; LDA #128
    ; STA AUD_DATA        ; Zapíše se do indexu 0xB (reg_vol_3), index se inkrementuje na 0xC

    ; 6. Nastavení tvarů vln pro jednotlivé kanály
    ; Význam hodnot v reg_ctrl: 
    ; 0 = Obdélník, 1 = Trojúhelník, 2 = Pila, 3 = Sinus, 4 = Trapéz (modifikovaný trojúhelník)
    LDA #$0C
    STA AUD_ADDR        ; Nastaví se index vnitřního registru na 0xC (reg_ctrl_0)
    LDA #0
    STA AUD_DATA        ; Zapíše se do indexu 0xC (reg_ctrl_0 = Sinus), index -> 0xD
    ; LDA #1
    ; STA AUD_DATA        ; Zapíše se do indexu 0xD (reg_ctrl_1 = Trojúhelník), index -> 0xE
    ; LDA #2
    ; STA AUD_DATA        ; Zapíše se do indexu 0xE (reg_ctrl_2 = Pila), index -> 0xF
    ; LDA #4
    ; STA AUD_DATA        ; Zapíše se do indexu 0xF (reg_ctrl_3 = Trapéz), index -> 0x0 (přetečení)

    RTS