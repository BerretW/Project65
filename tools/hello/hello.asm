; DETAILNÍ MANUÁL A MAPOVÁNÍ REGISTRŮ PRO 6502 PROGRAMÁTORA:
; =============================================================
; Připojení k sběrnici využívá 4bitovou adresu portu (lv_addr 4'h0 až 4'hF).

; 1. BARVA POZADÍ (Background Color) - Adresa: lv_addr = 4'h0
;    - Zápis 8bitové hodnoty určuje výchozí barvu pozadí obrazovky.
;    - Formát RGB: [7:5] Red (3 bity), [4:2] Green (3 bity), [1:0] Blue (2 bity, rozšiřují se na 3).

; 2. INTERNÍ ADRESA / POZICE KURZORU - Adresy: lv_addr = 4'h1, 4'h2, 4'h3
;    - 4'h1 (addr_hi): Vyšší bity adresy / kurzoru (reálně bity [2:0] pro SRAM, nebo [6:0] pro font).
;    - 4'h2 (addr_mid): Prostřední bity adresy / kurzoru.
;    - 4'h3 (addr_lo): Nejnižší bity adresy / kurzoru.
;    - V grafických režimech určují 24bitovou adresu (19 bitů aktivních) v externí SRAM.
;    - V textových režimech (01/02) slouží jako ukazatel pozice textového kurzoru v SRAM.
;    - POZNÁMKA: Po každém zápisu dat na port 4'h4 se tato adresa automaticky inkrementuje o +1.

; 3. DATOVÁ BRÁNA (Data Port) - Adresa: lv_addr = 4'h4
;    - Slouží pro zápis nebo čtení dat podle aktuálně nastaveného režimu (`mode`):
;      * Režim 0x0D (Editace fontu): Zápis/čtení definice fontu do interní paměti `font_mem`.
;        Adresa fontu je dána kombinací {addr_hi[6:0], addr_mid[2:0]} hi je číslo písmena a mid je řádek.
;      * Režim 0x01 / 0x02 (Textový režim): Zápis ASCII znaku na aktuální pozici kurzoru
;        do SRAM. Kurzoro-vá adresa (addr_hi/mid/lo) se sama posune o +1.
;      * Ostatní režimy (Grafické): Přímý zápis pixelů do externí SRAM na adresu `cpu_addr_full`.

; 4. REŽIMOVÝ REGISTR (Mode Register) - Adresa: lv_addr = 4'hD
;    - Zápis určuje chování řadiče:
;      * 0x00 až 0x0C: Grafické režimy (vykreslování pixelů přímo ze SRAM).
;      * 0x01: Textový režim (statický kurzor, vykreslování znaků přes font).
;      * 0x02: Textový režim s blikajícím kurzorem (~2 Hz).
;      * 0x0D: Režim programování/editace fontu (přístup k `font_mem`).
;      * 0x0F: Toggle / Blank screen (vypnutí obrazu – celá obrazovka zčerná).
;      * 0x0E: Hardwarový reset FPGA logiky (vyresetuje čítače a proměnné).
;    - Čtení z 4'hD vrací aktuální hodnotu registru `mode`.

; 5. STATUS A MAZÁNÍ PAMĚTI (Status & Clear) - Adresa: lv_addr = 4'hF
;    - Zápis (jakákoliv hodnota): Spustí hromadné vymazání celé externí SRAM (naplnění nulami).
;    - Čtení: Vrací stavový bajt `{7'b0, addr_ready}`. 
;      Bit 0 (`addr_ready`) je `1`, pokud je řadič připraven, a `0`, pokud právě probíhá 
;      mazání SRAM (`clear_busy`) nebo probíhá zápis. Před dalším zápisem je nutné testovat!
; =============================================================

.setcpu "65C02"
ROM_PRINTHEX = $FF1E
ROM_PRINTLN = $FF18
ROM_PUTNL = $FF15
; --- Definice registru FPGA ---
VGA_BASE   = $CE00
VGA_HI     = $CE01
VGA_MID    = $CE02
VGA_LO     = $CE03
VGA_DATA   = $CE04
VGA_MODE   = $CE0D
VGA_STATUS = $CE0F

VGA_MODE_BITMAP = $00
VGA_MODE_FONT   = $0D
VGA_MODE_TEXT   = $01
VGA_MODE_TEXT2  = $02
VGA_MODE_RESET = $0E

; --- Adresy v nulové stránce ---
ADDR_LO    = $20
ADDR_MID   = $21
ADDR_HI    = $22

BG_COLOR   = $23

.org $3000
JMP start

wait_done:      
                PHA
                PHX
                lda VGA_STATUS
                
                ; jsr ROM_PRINTHEX
                ; jsr ROM_PUTNL
                bit #$01
                beq wait_done
                PLX
                PLA
                rts

start:  

                ; LDA #$00
                ;  jsr ROM_PRINTHEX
                ; jsr ROM_PUTNL
                ; RTS
                ; 1. Smazat obrazovku
                LDA #VGA_MODE_RESET
                STA VGA_MODE
                JSR wait_done
                lda #<msg_clear
                ldx #>msg_clear
                jsr ROM_PRINTLN
                lda #$01
                sta VGA_STATUS
wait_clear:
                lda VGA_STATUS
                PHA
                jsr ROM_PRINTHEX
                jsr ROM_PUTNL
                PLA
                bit #$01
                beq wait_clear
                lda #<msg_status_OK
                ldx #>msg_status_OK
                jsr ROM_PRINTLN
                LDA #BG_COLOR
                STA VGA_BASE
                LDA #VGA_MODE_TEXT
                STA VGA_MODE
                JSR wait_done
                lda #<msg_text_mode
                ldx #>msg_text_mode
                jsr ROM_PRINTLN
                LDA #VGA_MODE_FONT
                STA VGA_MODE
                lda #<msg_font_mode
                ldx #>msg_font_mode
                jsr ROM_PRINTLN
                lda VGA_MODE
                JSR ROM_PRINTHEX
                jsr ROM_PUTNL
                
                
                LDA #$41
                STA ADDR_HI
write_a_start:  
                LDX #$00
                LDX #$00

write_a_loop:   LDA #$30
                LDA #$30
                STX ADDR_MID
                
                LDA #$30
                STA VGA_DATA
                INX
                PHX
                JSR wait_done
                TXA
                JSR ROM_PRINTHEX
                JSR ROM_PUTNL
                PLX
                CPX #$08
                BNE write_a_loop
            LDA #VGA_MODE_TEXT
            STA VGA_MODE
            JSR wait_done
            LDA #<msg_font_done
            LDX #>msg_font_done
            JSR ROM_PRINTLN
            LDA #$00
            LDA #$00
            STA ADDR_HI
            STA ADDR_MID
            STA ADDR_LO
            LDA #$41
            LDA #$41
            STA VGA_DATA
            JSR wait_done

RTS
msg_clear:  .byte "Mazu obrazovku", 0
msg_status_OK:    .byte "STATUS OK!", 0
msg_text_mode: .byte "Text mode", 0
msg_font_mode: .byte "Font mode", 0
msg_font_done: .byte "Font done", 0


