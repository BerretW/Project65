; ihex.asm – Intel HEX loader pro P65 minimal bootloader
;
; Formát záznamu:
;   :LLAAAATTDD...DDCC<CR><LF>
;   LL   = počet datových bajtů (1 bajt)
;   AAAA = cílová adresa big-endian (2 bajty)
;   TT   = typ: 00=data, 01=EOF, ostatní přeskočeny
;   DD…  = datové bajty (LL kusů)
;   CC   = checksum (dvoujedn. doplněk součtu LL+AAAH+AAAL+TT+DD…)
;
; Čte bajt po bajtu ze sériového portu (ACIA, blokující).
; Přijímá jakoukoli příchozí BOM / CR / LF / mezery – čeká na ':'.
; ESC ($1B) přeruší nahrávání a vrátí $FF.
;
; Výstup: A = 0  → OK (všechny záznamy OK)
;         A = 1..254 → počet záznamů s chybou checksumu
;         A = $FF    → přerušeno klávesou ESC
;
; Průběhový výpis na ACIA:
;   '.' za každý OK záznam
;   'X' za každý záznam s chybou checksumu
;   CR+LF před návratem
;
; ZP adresy (hardcoded, mimo cc65 $00–$20, EWOZ $24–$30, ramtest $70–$74):
;   ihex_errs  = $38   počet chyb checksumu (saturuje na $FF)
;   ihex_cksum = $39   průběžný součet bajtů aktuálního záznamu
;   ihex_cnt   = $3A   počet datových bajtů v záznamu (LL)
;   ihex_type  = $3B   typ záznamu (TT)
;   ihex_addrH = $3C   cílová adresa – high byte
;   ihex_addrL = $3D   cílová adresa – low byte
;   ihex_tmp   = $3E   dočasné uložení prvního nibblu
;
; Sledování rozsahu nahraných adres (pro LSAVE v AppartusOS):
ihex_minL  = $54   ; nejnižší zapsaná adresa lo  (sentinel $FF při init)
ihex_minH  = $55   ; nejnižší zapsaná adresa hi
ihex_maxL  = $56   ; adresa za posledním zapsaným bajtem lo (sentinel $00 při init)
ihex_maxH  = $57   ; adresa za posledním zapsaným bajtem hi
;
; ptr1 ($0F/$10, cc65 ZP) se použije jako write pointer.

.setcpu     "65C02"
.smart      on
.autoimport on
.case       on
.debuginfo  off

.importzp   ptr1

; ---- ZP adresy jako equates (bez .zeropage/.res – nekolidují s linkerem) ----
ihex_errs  = $38
ihex_cksum = $39
ihex_cnt   = $3A
ihex_type  = $3B
ihex_addrH = $3C
ihex_addrL = $3D
ihex_tmp   = $3E

.export _ihex_load

.segment "CODE"

; ============================================================
; _ihex_load – načte Intel HEX ze sériového portu
; ============================================================
_ihex_load:
        stz ihex_errs           ; nuluj počítač chyb
        lda #$FF
        sta ihex_minL
        sta ihex_minH           ; min = $FFFF (sentinel – bude aktualizováno dolů)
        lda #$00
        sta ihex_maxL
        sta ihex_maxH           ; max = $0000 (sentinel – bude aktualizováno nahoru)

; ---- čekáme na ':' (začátek záznamu) nebo ESC ----
@find_colon:
        jsr _acia_getc
        cmp #$1B                ; ESC = přerušení
        bne @not_esc
        jmp @done_esc
@not_esc:
        cmp #':'
        bne @find_colon         ; ignoruj CR, LF, mezery, …

; ---- nalezeno ':' – zpracování záznamu ----
        stz ihex_cksum          ; nuluj průběžný součet

        ; LL – počet datových bajtů
        jsr @rd_byte
        sta ihex_cnt

        ; AAAA – adresa (big-endian: nejprve high)
        jsr @rd_byte
        sta ihex_addrH

        jsr @rd_byte
        sta ihex_addrL

        ; TT – typ záznamu
        jsr @rd_byte
        sta ihex_type

        cmp #$01                ; EOF?
        beq @eof_record
        cmp #$00                ; Data?
        bne @skip_record        ; jiný typ → přeskočit datové bajty

; ---- záznam typu 00 (data) – zápis do RAM ----
        lda ihex_addrL
        sta ptr1
        lda ihex_addrH
        sta ptr1+1

        ldx ihex_cnt
        beq @verify             ; LL=0 → jen verifikace checksumu

        ; --- min: zapiš jen pro první záznam (sentinel = $FFFF) ---
        lda ihex_minH
        cmp #$FF
        bne @skip_min
        lda ihex_addrL
        sta ihex_minL
        lda ihex_addrH
        sta ihex_minH
@skip_min:

@data_loop:
        jsr @rd_byte
        sta (ptr1)
        inc ptr1
        bne @data_cnt
        inc ptr1+1
@data_cnt:
        dex
        bne @data_loop

        ; --- max: vždy aktualizuj na ptr1 (konec tohoto záznamu) ---
        lda ptr1
        sta ihex_maxL
        lda ptr1+1
        sta ihex_maxH
        bra @verify             ; → verifikace checksumu

; ---- záznam jiného typu (02, 03, 04, 05…) – přečíst a zahodit ----
@skip_record:
        ldx ihex_cnt
        beq @verify
@skip_loop:
        jsr @rd_byte            ; čteme a zahazujeme (stále přičítáme do checksumu)
        dex
        bne @skip_loop
        ; fall-through → @verify

; ---- verifikace checksumu záznamu ----
@verify:
        jsr @rd_byte            ; CC – checksum bajt (přičte se k ihex_cksum)
        lda ihex_cksum          ; výsledný součet musí být 0
        bne @cksum_err
        lda #'.'
        jsr _acia_putc          ; záznam OK
        jmp @find_colon         ; další záznam

@cksum_err:
        lda #'X'
        jsr _acia_putc          ; chyba checksumu
        inc ihex_errs           ; počítej chybu
        bne @cksum_next         ; ne $FF → pokračuj
        dec ihex_errs           ; saturace: zpět na $FE+1=$FF … undo wrap
@cksum_next:
        jmp @find_colon

; ---- záznam typu 01 (EOF) ----
@eof_record:
        ; EOF záznam má LL=00; přečteme checksum bajt a ověříme
        jsr @rd_byte            ; CC
        lda ihex_cksum
        beq @eof_ok
        inc ihex_errs           ; chyba v EOF záznamu
        bne @eof_ok
        dec ihex_errs           ; saturace
@eof_ok:
        lda #$0D                ; CR+LF před návratem
        jsr _acia_putc
        lda #$0A
        jsr _acia_putc
        lda ihex_errs           ; A=0 OK, A!=0 chyby
        rts

@done_esc:
        lda #$FF                ; ESC – přerušení
        rts


; ============================================================
; @rd_byte – přečte 2 ASCII hex znaky z ACIA → bajt v A
; Přičítá výsledek do ihex_cksum (průběžný checksum).
; Ničí: A, ihex_tmp
; ============================================================
@rd_byte:
        jsr _acia_getc
        jsr @hex_nib            ; A = hodnota prvního nibblu (0–15)
        asl
        asl
        asl
        asl
        sta ihex_tmp            ; uložíme high nibble × 16
        jsr _acia_getc
        jsr @hex_nib            ; A = hodnota druhého nibblu (0–15)
        and #$0F
        ora ihex_tmp            ; A = plný bajt
        pha                     ; uložíme bajt na zásobník
        clc
        adc ihex_cksum          ; přičteme k průběžnému checksumu
        sta ihex_cksum
        pla                     ; vrátíme bajt
        rts


; ============================================================
; @hex_nib – převede ASCII hex znak v A na hodnotu 0–15
; Vstup:  A = '0'–'9' nebo 'A'–'F' nebo 'a'–'f'
; Výstup: A = 0–15
; ============================================================
@hex_nib:
        cmp #'a'                ; lowercase?
        bcc @upper_or_digit
        and #$DF                ; lowercase → uppercase (clear bit 5)
@upper_or_digit:
        cmp #'A'
        bcc @digit              ; < 'A' → '0'–'9'
        sec
        sbc #'A' - 10           ; 'A'→10, 'B'→11, …, 'F'→15
        rts
@digit:
        sec
        sbc #'0'                ; '0'→0, …, '9'→9
        rts
