AUD_BASE = $CE00
AUD_ADDR = AUD_BASE + 5
AUD_DATA = AUD_BASE + 6

play_chord:
    ; 1. Vynulujeme index vnitřního registru
    LDA #0
    STA AUD_ADDR

    ; 2. NASTAVENÍ FREKVENCÍ A MAXIMÁLNÍCH HLASITOSTÍ (0x00 až 0x0B)
    
    ; Kanál 0: tón C4 (261 Hz, hodnota S = 351 = $015F), Max hlasitost 255 (100%)
    LDA #$5F
    STA AUD_DATA        ; 0x00 -> Freq Lo 0, posun na 0x01
    LDA #$01
    STA AUD_DATA        ; 0x01 -> Freq Hi 0, posun na 0x02
    LDA #255
    STA AUD_DATA        ; 0x02 -> Vol 0, posun na 0x03


    ; 3. NASTAVENÍ TVARŮ VLN, ADSR ENABLE A TRIGGER GATE (0x0C až 0x0F)
    ; Reg Ctrl bity: [2:0] Wave (0=Square, 1=Triangle, 2=Sawtooth, 3=Sine, 4=Trapezoid)
    ;                [3]   ADSR Enable (1 = Zapnuto, 0 = Vypnuto)
    ;                [4]   Gate (1 = Note On / Attack, 0 = Note Off / Release)

    
    LDA #$0C
    STA AUD_ADDR       
    ; Kanál 0: Sine (3) + ADSR Enable (8) + Gate Note On (16) = 3 + 8 + 16 = 27 = $1B
    LDA #$1B
    STA AUD_DATA        ; 0x0C -> Ctrl 0, posun na 0x0D



    ; 4. NASTAVENÍ ČASŮ ADSR (0x10 až 0x17)
    ; Reg ADSR AD (Attack / Decay): [7:4] Attack (0=Slowest, F=Fastest), [3:0] Decay (0=Slowest, F=Fastest)
    ; Reg ADSR SR (Sustain / Release): [7:4] Sustain Level (0=Mute, F=Full), [3:0] Release (0=Slowest, F=Fastest)
    LDA #$10
    STA AUD_ADDR        
    ; Kanál 0 (Sine): Pomalý náběh (Attack=4), střední Decay=8, střední Sustain=10 ($A), rychlý doznění (Release=12=$C)
    LDA #$48
    STA AUD_DATA        ; 0x10 -> Attack/Decay Ch0, posun na 0x11
    LDA #$AC
    STA AUD_DATA        ; 0x11 -> Sustain/Release Ch0, posun na 0x12


    RTS