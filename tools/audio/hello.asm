AUD_BASE = $CE00
AUD_ADDR = AUD_BASE + 5
AUD_DATA = AUD_BASE + 6

play_chord:
    ; 1. Vynulujeme index vnitřního registru
    LDA #0
    STA AUD_ADDR

    ; 2. Kanál 0: tón C4 (261 Hz, hodnota S = 351 = $015F), hlasitost 128 (50%)
    LDA #$5F
    STA AUD_DATA        ; Zapíše se do indexu 0x0, index se inkrementuje na 0x1
    LDA #$01
    STA AUD_DATA        ; Zapíše se do indexu 0x1, index se inkrementuje na 0x2
    LDA #128
    STA AUD_DATA        ; Zapíše se do indexu 0x2, index se inkrementuje na 0x3

    ; 3. Kanál 1: tón E4 (329 Hz, hodnota S = 442 = $01BA), hlasitost 128 (50%)
    LDA #$BA
    STA AUD_DATA        ; Zapíše se do indexu 0x3 -> 0x4
    LDA #$01
    STA AUD_DATA        ; Zapíše se do indexu 0x4 -> 0x5
    LDA #128
    STA AUD_DATA        ; Zapíše se do indexu 0x5 -> 0x6

    ; 4. Kanál 2: tón G4 (392 Hz, hodnota S = 526 = $020E), hlasitost 128 (50%)
    LDA #$0E
    STA AUD_DATA        ; Zapíše se do indexu 0x6 -> 0x7
    LDA #$02
    STA AUD_DATA        ; Zapíše se do indexu 0x7 -> 0x8
    LDA #128
    STA AUD_DATA        ; Zapíše se do indexu 0x8 -> 0x9

    ; 5. Kanál 3: tón C5 (523 Hz, hodnota S = 702 = $02BE), hlasitost 128 (50%)
    LDA #$BE
    STA AUD_DATA        ; Zapíše se do indexu 0x9 -> 0xA
    LDA #$02
    STA AUD_DATA        ; Zapíše se do indexu 0xA -> 0xB
    LDA #128
    STA AUD_DATA        ; Zapíše se do indexu 0xB -> 0x0 (přetečení indexu)

    RTS