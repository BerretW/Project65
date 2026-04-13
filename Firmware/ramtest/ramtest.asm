; ramtest.asm - RAM test pro P65 SBC 65C02 BigBoard
;
; Nahravam bootloaderem prikazem 'w' (8192 B → $6000–$7FFF).
; Po nahrání automaticky skočí na RAMDISK_RESET_VECTOR ($7FFC) → start.
; Po dokončení testů skočí na ROM_RST ($FF00) → restart bootloaderu.
;
; Testovaná oblast: volitelná stránka (hex byte, Enter=vše $0200–$5FFF)
;
; Testy:
;   1. Pattern $AA  – zápis, čtení, verifikace
;   2. Pattern $55  – zápis, čtení, verifikace
;   3. Adresový test – bajt = lo-byte adresy (detekce zkratů adresní sběrnice)
;
; I/O rutiny jsou volány přes ROM jump table (jumptable.inc65).
; ACIA je inicializována přes ROM_ACIA_INIT (19200 8N1).

.setcpu "65C02"

.include "jumptable.inc65"

TEST_FULL_START = $0200
TEST_FULL_END   = $5FFF

; Zero page proměnné
; $00–$1F  cc65 runtime
; $24–$30  EWOZ
; $31–$6F  volné – zde náš page_mode
; $70–$74  naše proměnné (původní rozsah, ověřen funkční)
; $7A      tstart_hi (ověřen funkční)
; $10      slowmode (tmp1 cc65 – ale cc65 runtime se v ramtestu nevolá)
;
; page_mode:  $00 = full test ($0200–$5FFF, inc_ptr porovnává s hardcoded $60)
;             $01 = single page (inc_ptr porovnává ptr+1 s tstart_hi)
page_mode = $32   ; bezpečné ZP (mimo cc65/EWOZ/ROM oblasti)
ptr       = $70   ; 2 bajty – pracovní ukazatel do RAM
errcnt    = $72   ; chyby v aktuálním testu (sytí na $FF)
totfail   = $73   ; počet neúspěšných testů celkem
pattern   = $74   ; aktuální testovací vzor
tstart_hi = $7A   ; hi-byte začátku testované oblasti (lo vždy $00)
slowmode  = $10   ; $FF = pomalý režim (tečka+delay každou stránku), $00 = rychlý


; ===========================================================================
.segment "CODE"
; ===========================================================================

start:
    sei
    cld
    stz errcnt
    stz totfail

    ; Inicializace ACIA – 19200 8N1
    jsr ROM_ACIA_INIT

    lda #<str_banner
    ldx #>str_banner
    jsr ROM_GETS

    ; Dotaz na stránku → nastaví tstart_hi + page_mode
    jsr ask_page

    ; Vypiš vybraný rozsah
    jsr print_range

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
    lda #<str_pass
    ldx #>str_pass
    jsr ROM_GETS
    jmp ROM_RST

@fail:
    lda #<str_fail
    ldx #>str_fail
    jsr ROM_GETS
    jmp ROM_RST


; ---------------------------------------------------------------------------
; ask_page – zeptá se uživatele na číslo stránky (2 hex znaky nebo Enter=vše).
; Nastaví: tstart_hi, page_mode ($00=full, $01=single page).
; ---------------------------------------------------------------------------
ask_page:
    lda #<str_prompt
    ldx #>str_prompt
    jsr ROM_GETS

    jsr ROM_GETC            ; přečti první znak
    cmp #$0D                ; Enter → celý rozsah
    bne @hex1

    ; Enter → full test $0200–$5FFF
    jsr ROM_PUTNL
    lda #>TEST_FULL_START   ; $02
    sta tstart_hi
    stz page_mode           ; $00 = full
    rts

@hex1:
    jsr ROM_PUTC            ; echo prvního znaku
    jsr to_nibble           ; A = horní nibble (0–15)
    asl A
    asl A
    asl A
    asl A
    sta tstart_hi           ; dočasné uložení horního nibble

    jsr ROM_GETC            ; přečti druhý znak
    jsr ROM_PUTC            ; echo
    jsr to_nibble           ; A = dolní nibble (0–15)
    ora tstart_hi           ; kombinuj oba nibble
    sta tstart_hi           ; finální číslo stránky
    lda #$01
    sta page_mode           ; $01 = single page
    jsr ROM_PUTNL
    rts


; ---------------------------------------------------------------------------
; to_nibble – převede ASCII hex znak v A na číslo 0–15.
; Nevalidní znaky vrátí 0. Akceptuje 0–9, A–F, a–f.
; ---------------------------------------------------------------------------
to_nibble:
    cmp #'0'
    bcc @ret0
    cmp #'9'+1
    bcc @digit
    ora #$20                ; toLower
    cmp #'a'
    bcc @ret0
    cmp #'f'+1
    bcs @ret0
    sec
    sbc #'a'-10             ; 'a'→10, …, 'f'→15
    rts
@digit:
    sec
    sbc #'0'                ; '0'→0, …, '9'→9
    rts
@ret0:
    lda #0
    rts


; ---------------------------------------------------------------------------
; print_range – tiskne "Rozsah: $XX00-$XXFF\r\n\r\n"
; ---------------------------------------------------------------------------
print_range:
    lda #<str_range_a
    ldx #>str_range_a
    jsr ROM_GETS            ; "Rozsah: $"
    lda tstart_hi
    jsr ROM_PRTBYTE         ; XX (hi-byte startu)
    lda #'0'
    jsr ROM_PUTC
    lda #'0'
    jsr ROM_PUTC            ; "00"
    lda #'-'
    jsr ROM_PUTC
    lda #'$'
    jsr ROM_PUTC
    ; hi-byte konce: full=$5F, single=tstart_hi
    lda page_mode
    bne @single
    lda #>TEST_FULL_END     ; $5F
    bra @print_end
@single:
    lda tstart_hi           ; single page konec = stejná stránka
@print_end:
    jsr ROM_PRTBYTE         ; XX (hi-byte konce)
    lda #<str_range_b
    ldx #>str_range_b
    jsr ROM_GETS            ; "FF\r\n\r\n"
    rts


; ---------------------------------------------------------------------------
; run_pattern_test – A=vzor, X=lo-byte popisu testu, Y=hi-byte popisu testu
; Zapíše vzor do celé oblasti, přečte zpět a spočítá chyby.
; Pokud pattern=$55: slowmode=$FF – tečka + delay každou stránku.
; Jinak:            slowmode=$00 – tečka každých 4 KB (normální rychlost).
; ---------------------------------------------------------------------------
run_pattern_test:
    sta pattern
    cmp #$55
    bne @fast
    lda #$FF
    sta slowmode
    bra @go
@fast:
    stz slowmode
@go:
    phy                     ; ulož Y (hi) na stack
    txa                     ; A = lo-byte řetězce
    plx                     ; X = hi-byte řetězce
    jsr ROM_GETS

    ; --- fáze zápisu ---
    lda #$00
    sta ptr
    lda tstart_hi
    sta ptr+1
@pw:
    lda pattern
    sta (ptr)
    jsr inc_ptr
    bcs @pw_done
    lda ptr
    bne @pw                 ; čekáme na lo-byte == 0 (hranice stránky)
    ; jsme na hranici stránky ($xx00)
    lda slowmode
    bne @pw_dot
    lda ptr+1
    and #$0F
    bne @pw
@pw_dot:
    lda #'.'
    jsr ROM_PUTC
    lda slowmode
    beq @pw
    jsr ROM_DELAY
    bra @pw
@pw_done:

    ; --- fáze čtení + verifikace ---
    lda #$00
    sta ptr
    lda tstart_hi
    sta ptr+1
    stz errcnt
@pv:
    lda (ptr)
    cmp pattern
    beq @pok
    inc errcnt
    bne @pok
    dec errcnt
@pok:
    jsr inc_ptr
    bcs @pv_done
    lda ptr
    bne @pv
    lda slowmode
    bne @pv_dot
    lda ptr+1
    and #$0F
    bne @pv
@pv_dot:
    lda #'.'
    jsr ROM_PUTC
    lda slowmode
    beq @pv
    jsr ROM_DELAY
    bra @pv
@pv_done:

    jmp print_result


; ---------------------------------------------------------------------------
; run_addr_test – X=lo-byte popisu testu, Y=hi-byte popisu testu
; ---------------------------------------------------------------------------
run_addr_test:
    phy
    txa
    plx
    jsr ROM_GETS

    ; --- fáze zápisu ---
    lda #$00
    sta ptr
    lda tstart_hi
    sta ptr+1
@aw:
    lda ptr
    sta (ptr)
    jsr inc_ptr
    bcs @aw_done
    lda ptr
    bne @aw
    lda ptr+1
    and #$0F
    bne @aw
    lda #'.'
    jsr ROM_PUTC
    bra @aw
@aw_done:

    ; --- fáze čtení + verifikace ---
    lda #$00
    sta ptr
    lda tstart_hi
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
    jsr ROM_PUTC
    bra @av
@av_done:

    jmp print_result


; ---------------------------------------------------------------------------
; print_result – tiskne "OK\r\n" nebo "NN err\r\n" dle errcnt
; ---------------------------------------------------------------------------
print_result:
    lda errcnt
    bne @bad
    lda #<str_ok
    ldx #>str_ok
    jsr ROM_GETS
    rts

@bad:
    inc totfail
    lda errcnt
    jsr ROM_PRTBYTE
    lda #<str_err
    ldx #>str_err
    jsr ROM_GETS
    rts


; ---------------------------------------------------------------------------
; inc_ptr – ptr++, C=1 pokud oblast vyčerpána
;
; page_mode = $00 (full):   porovnává ptr+1 s hardcoded #$60 (= >TEST_FULL_END+1)
; page_mode ≠ $00 (single): porovnává ptr+1 s tstart_hi; hotovo když ptr+1 > tstart_hi
; ---------------------------------------------------------------------------
inc_ptr:
    inc ptr
    bne @chk
    inc ptr+1
@chk:
    lda page_mode
    bne @single
    ; --- full range: ptr+1 < $60? ---
    lda ptr+1
    cmp #>TEST_FULL_END + 1     ; = $60
    bcc @cont
    sec
    rts
@single:
    ; --- single page: ptr+1 == tstart_hi → still on page ---
    lda ptr+1
    cmp tstart_hi
    beq @cont                   ; stejná stránka → pokračuj
    sec                         ; jiná stránka → konec
    rts
@cont:
    clc
    rts


; ===========================================================================
.segment "RODATA"
; ===========================================================================

str_banner:  .byte $0D,$0A
             .byte "==============================",$0D,$0A
             .byte "       P65 RAM Test",$0D,$0A
             .byte "==============================",$0D,$0A,0

str_prompt:  .byte "Stranka (hex, Enter=vse): ",0

str_range_a: .byte "Rozsah: $",0
str_range_b: .byte "FF",$0D,$0A,$0D,$0A,0

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
; ===========================================================================
.segment "RAMVEC"
    .addr start            ; $7FFC–$7FFD = adresa start ($6000)
    .addr start            ; $7FFE–$7FFF = (nepoužito, vyplněno)
