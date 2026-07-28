.setcpu "65C02"

; --- Definice registru FPGA ---
VGA_BASE   = $CE00
VGA_HI     = $CE01
VGA_MID    = $CE02
VGA_LO     = $CE03
VGA_DATA   = $CE04
VGA_STATUS = $CE0F

; --- Adresy v nulové stránce ---
ADDR_LO    = $20
ADDR_MID   = $21
ADDR_HI    = $22

.org $3000

start:
    ; 1. Smazat obrazovku
    lda #$01
    sta VGA_STATUS

wait_clear:
    lda VGA_STATUS
    bit #$01
    beq wait_clear

    ; 2. Nastavit tmavě modré pozadí (registr 0)
    lda #%00000100 
    sta VGA_BASE

    ; 3. Nastavit počáteční souřadnice čtverce ($020920)
    ; Uložíme si je do paměti procesoru pro začátky řádků
    lda #$20
    sta ADDR_LO
    lda #$09
    sta ADDR_MID
    lda #$02
    sta ADDR_HI

    ; X bude počítat řádky (výška 100 pixelů)
    ldx #100        

row_loop:
    ; Nastavit adresu na začátek aktuálního řádku do FPGA
    lda ADDR_HI
    sta VGA_HI
    lda ADDR_MID
    sta VGA_MID
    lda ADDR_LO
    sta VGA_LO

    ; Y bude počítat pixely v řádku (šířka 100 pixelů)
    ldy #100        
    lda #$FC        ; Žlutá barva

pixel_loop:
    sta VGA_DATA    ; Zápis do FPGA (díky pulse detekci zapíše jen 1 pixel)
    dey
    bne pixel_loop

    ; 4. Přičíst 640 (šířka obrazovky) k naší adrese pro další řádek
    ; 640 = $0280
    clc
    lda ADDR_LO
    adc #$80
    sta ADDR_LO
    
    lda ADDR_MID
    adc #$02
    sta ADDR_MID
    
    lda ADDR_HI
    adc #$00
    sta ADDR_HI

    ; Další řádek
    dex
    bne row_loop

    rts