; ramtest.asm - RAM test pro P65 SBC 65C02 BigBoard
;
; Nahravam bootloaderem prikazem 'w' (8192 B → $6000–$7FFF).
; Po nahrání automaticky skočí na RAMDISK_RESET_VECTOR ($7FFC) → start.
; Po dokončení testů skočí na $FF00 (jumptable RST → restart bootloaderu).
;
; Testovaná oblast: $0200–$5FFF (pracovní RAM, mimo ZP a program samotný)
;
; Testy:
;   1. Pattern $AA  – zápis, čtení, verifikace
;   2. Pattern $55  – zápis, čtení, verifikace
;   3. Adresový test – bajt = lo-byte adresy (detekce zkratů adresní sběrnice)
;
; ACIA na $C800 se znovu neinicializuje – bootloader ji nastaví na 19200 Bd.

.setcpu "65C02"

ACIA_DATA     = $C800
ACIA_STATUS   = $C801
ACIA_CMD      = $C802      ; command register
ACIA_CTRL     = $C803      ; control register (baud, word length)
ACIA_TX_EMPTY = $10        ; bit 4 – transmitter empty
; 19200 Bd, 8N1, ext clock (1,8432 MHz):  CTRL=$1F, CMD=$0B
ACIA_CTRL_VAL = $1F        ; 8 bit, 1 stop, ext clock (baud = xtal/16)
ACIA_CMD_VAL  = $0B        ; no parity, normal, TX irq off, RX irq off, DTR low

TEST_START    = $0200
TEST_END      = $5FFF
BOOT_RST      = $FF00      ; jumptable: restart bootloaderu (JMP _main)

; Zero page proměnné – adresy $70–$75 jsou mimo cc65 ($00–$1F) i EWOZ ($24–$30)
ptr     = $70   ; 2 bajty – pracovní ukazatel do RAM
errcnt  = $72   ; chyby v aktuálním testu (sytí na $FF)
totfail = $73   ; počet neúspěšných testů celkem
pattern = $74   ; aktuální testovací vzor
slowmode= $75   ; $FF = pomalý režim (tečka+delay každou stránku), $00 = rychlý


; ===========================================================================
.segment "CODE"
; ===========================================================================

start:
    sei
    cld
    stz errcnt
    stz totfail

    ; Reset ACIA – zajistí čistý stav TX po přechodu z bootloaderu
    lda #$00
    sta ACIA_STATUS         ; software reset (zápis $00 do status reg)
    lda #ACIA_CTRL_VAL
    sta ACIA_CTRL           ; 8N1, ext clock
    lda #ACIA_CMD_VAL
    sta ACIA_CMD            ; no parity, TX/RX irq off

    ldx #<str_banner
    ldy #>str_banner
    jsr puts

    ; Test 1 – pattern $AA
    lda #$AA
    ldx #<str_t1
    ldy #>str_t1
    jsr run_pattern_test

    ; Test 2 – pattern $55
    lda #$55
    ldx #<str_t2
    ldy #>str_t2
    jsr run_pattern_test

    ; Test 3 – adresový test
    ldx #<str_t3
    ldy #>str_t3
    jsr run_addr_test

    ; Výsledek
    lda totfail
    bne @fail
    ldx #<str_pass
    ldy #>str_pass
    jsr puts
    jmp BOOT_RST

@fail:
    ldx #<str_fail
    ldy #>str_fail
    jsr puts
    jmp BOOT_RST


; ---------------------------------------------------------------------------
; run_pattern_test – A=vzor, X/Y=ukazatel na popis testu
; Zapíše vzor do celé oblasti, přečte zpět a spočítá chyby.
; Pokud pattern=$55: slowmode=$FF – tečka + delay každých 256 B (každou stránku).
; Jinak:            slowmode=$00 – tečka každých 4 KB (normální rychlost).
; ---------------------------------------------------------------------------
run_pattern_test:
    sta pattern
    ; nastav slowmode podle vzoru
    cmp #$55
    bne @fast
    lda #$FF
    sta slowmode
    bra @go
@fast:
    stz slowmode
@go:
    jsr puts               ; vytiskni popis testu

    ; --- fáze zápisu ---
    lda #<TEST_START
    sta ptr
    lda #>TEST_START
    sta ptr+1
@pw:
    lda pattern
    sta (ptr)
    jsr inc_ptr
    bcs @pw_done
    lda ptr
    bne @pw                ; čekáme na lo-byte == 0 (hranice stránky)
    ; jsme na hranici stránky ($xx00)
    lda slowmode
    bne @pw_dot            ; slowmode → tečka každou stránku
    ; rychlý režim → tečka jen každých 4 KB
    lda ptr+1
    and #$0F
    bne @pw
@pw_dot:
    lda #'.'
    jsr putc
    lda slowmode
    beq @pw                ; rychlý režim → bez delay
    jsr delay
    bra @pw
@pw_done:

    ; --- fáze čtení + verifikace ---
    lda #<TEST_START
    sta ptr
    lda #>TEST_START
    sta ptr+1
    stz errcnt
@pv:
    lda (ptr)
    cmp pattern
    beq @pok
    inc errcnt
    bne @pok               ; ochrana proti přetečení errcnt přes $FF
    dec errcnt             ; drž na $FF
@pok:
    jsr inc_ptr
    bcs @pv_done
    lda ptr
    bne @pv
    ; hranice stránky
    lda slowmode
    bne @pv_dot
    lda ptr+1
    and #$0F
    bne @pv
@pv_dot:
    lda #'.'
    jsr putc
    lda slowmode
    beq @pv
    jsr delay
    bra @pv
@pv_done:

    jmp print_result       ; vytiskni OK / NN err a vrať se


; ---------------------------------------------------------------------------
; run_addr_test – X/Y=ukazatel na popis testu
; Zapíše do každého bajtu lo-byte jeho adresy, přečte zpět.
; ---------------------------------------------------------------------------
run_addr_test:
    jsr puts

    ; --- fáze zápisu ---
    lda #<TEST_START
    sta ptr
    lda #>TEST_START
    sta ptr+1
@aw:
    lda ptr                ; lo-byte adresy
    sta (ptr)
    jsr inc_ptr
    bcs @aw_done
    lda ptr
    bne @aw
    lda ptr+1
    and #$0F
    bne @aw
    lda #'.'
    jsr putc
    bra @aw
@aw_done:

    ; --- fáze čtení + verifikace ---
    lda #<TEST_START
    sta ptr
    lda #>TEST_START
    sta ptr+1
    stz errcnt
@av:
    lda (ptr)
    cmp ptr
    beq @aok
    inc errcnt
    bne @aok
    dec errcnt
@aok:
    jsr inc_ptr
    bcs @av_done
    lda ptr
    bne @av
    lda ptr+1
    and #$0F
    bne @av
    lda #'.'
    jsr putc
    bra @av
@av_done:

    jmp print_result


; ---------------------------------------------------------------------------
; print_result – tiskne "OK\r\n" nebo "NN err\r\n" dle errcnt
; Spouští se přes JMP (chová se jako subrutin – volá se JMP, vrátí caller).
; ---------------------------------------------------------------------------
print_result:
    lda errcnt
    bne @bad
    ldx #<str_ok
    ldy #>str_ok
    jsr puts
    rts

@bad:
    inc totfail
    lda errcnt
    jsr prbyte             ; 2 hex cifry
    ldx #<str_err
    ldy #>str_err
    jsr puts
    rts


; ---------------------------------------------------------------------------
; inc_ptr – ptr++, C=1 pokud ptr překročil TEST_END ($5FFF → $6000)
; ---------------------------------------------------------------------------
inc_ptr:
    inc ptr
    bne @chk
    inc ptr+1
@chk:
    lda ptr+1
    cmp #>TEST_END + 1     ; = $60
    bcc @cont              ; ptr+1 < $60 → pokračuj
    sec
    rts
@cont:
    clc
    rts


; ---------------------------------------------------------------------------
; delay – krátká pauza (zachová A, X)
; ~128 × 256 = 32 768 iterací, každá ~8 cyklů ≈ 65 ms @ 4 MHz
; ---------------------------------------------------------------------------
delay:
    pha
    phx
    ldx #$80               ; 128 vnějších iterací
@outer:
    lda #$00               ; 256 vnitřních iterací (dec z 0 → 255 → … → 0)
@inner:
    dec
    bne @inner
    dex
    bne @outer
    plx
    pla
    rts


; ---------------------------------------------------------------------------
; putc – odešle znak z A přes ACIA (polling, bez timeout)
; ---------------------------------------------------------------------------
putc:
    pha
@wait:
    lda ACIA_STATUS
    and #ACIA_TX_EMPTY
    beq @wait
    pla
    sta ACIA_DATA
    rts


; ---------------------------------------------------------------------------
; puts – vytiskne řetězec ukončený $00
; Vstup: X = lo-byte adresy řetězce, Y = hi-byte adresy řetězce
; ---------------------------------------------------------------------------
puts:
    stx ptr
    sty ptr+1
    ldy #0
@lp:
    lda (ptr),y
    beq @done
    jsr putc
    iny
    bne @lp
@done:
    rts


; ---------------------------------------------------------------------------
; prbyte – vytiskne A jako 2 hex cifry (HH)
; ---------------------------------------------------------------------------
prbyte:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr prhex              ; hi nibble
    pla
    ; fall through

prhex:
    and #$0F
    ora #'0'
    cmp #':'               ; > '9' ?
    bcc @out
    adc #6                 ; A–F
@out:
    jmp putc               ; putc RTS → vrátí se volajícímu prbyte/prhex


; ===========================================================================
.segment "RODATA"
; ===========================================================================

str_banner: .byte $0D,$0A
            .byte "==============================",$0D,$0A
            .byte " P65 RAM Test  $0200-$5FFF",$0D,$0A
            .byte "==============================",$0D,$0A,0

str_t1:     .byte "[1/3] Pattern $AA ... ",0
str_t2:     .byte "[2/3] Pattern $55 ... ",0
str_t3:     .byte "[3/3] Addr lo-byte ... ",0

str_ok:     .byte "OK",$0D,$0A,0
str_err:    .byte " chyb  FAIL",$0D,$0A,0

str_pass:   .byte $0D,$0A
            .byte ">>> PASS - RAM OK <<<",$0D,$0A
            .byte "Navrat do bootloaderu...",$0D,$0A,0

str_fail:   .byte $0D,$0A
            .byte ">>> FAIL - RAM CHYBY <<<",$0D,$0A
            .byte "Navrat do bootloaderu...",$0D,$0A,0


; ===========================================================================
; Vektory RAM disku – musí být na $7FFC (offset $1FFC od začátku $6000)
; Bootloader čte: RAMDISK_RESET_VECTOR = $7FFC → skočí sem po 'w' nebo 's'
; ===========================================================================
.segment "RAMVEC"
    .addr start            ; $7FFC–$7FFD = adresa start ($6000)
    .addr start            ; $7FFE–$7FFF = (nepoužito, vyplněno)
