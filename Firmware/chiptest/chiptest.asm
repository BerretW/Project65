; chiptest.asm - TMS9918A VDP + SAA1099 test, P65 SBC 65C02 BigBoard
;
; Nahravam bootloaderem prikazem 'w' (8192 B -> $6000-$7FFF).
; Po nahrani automaticky skoci na RAMDISK_RESET_VECTOR ($7FFC) -> start.
; Po dokonceni testu skoci na ROM_RST ($FF00) -> restart bootloaderu.
;
; Testy TMS9918A ($C000/$C001 = !VERA_CS oblast, IC9 Y0):
;   1. STATUS registr - cte, musi byt != $FF (chip pritomen a odpovida)
;   2. VRAM zapis/cteni vzoru $55 na adrese VRAM $0000
;   3. VRAM zapis/cteni vzoru $AA na adrese VRAM $0000
;
; Test SAA1099 ($CD00/$CD01 = ISA DEV0, IC9 sek.2 Y1):
;   4. Reset + inicializace SAA1099
;      Zahraje 6-tonovou stupnici C-D-E-F-G-A na kanalu 0 (sluchovy test)
;      Uzivatel potvrzuje slysen zvuk stisknutim y/n
;
; I/O rutiny volany pres ROM jump table (jumptable.inc65).
; ACIA inicializovana pres ROM_ACIA_INIT (19200 8N1).
;
; Adresni mapa (HW oprava Bug #4):
;   TMS9918A ISA karta: MODE0=$C000, MODE1=$C001  (!VERA_CS, $C000-$C3FF)
;   SAA1099  ISA karta: DATA=$CD00,  REG=$CD01    (!DEV0_CS, $CD00-$CDFF)

.setcpu "65C02"

.include "jumptable.inc65"

; ---------------------------------------------------------------------------
; Adresy cipu
; ---------------------------------------------------------------------------
VDP_DATA    = $C000     ; TMS9918A MODE0 - VRAM data    (!VERA_CS, IC9 Y0)
VDP_CTRL    = $C001     ; TMS9918A MODE1 - status/reg   (!VERA_CS, IC9 Y0)

SAA_DATA    = $CD00     ; SAA1099 datovy port (write-only)  (!DEV0_CS)
SAA_REG     = $CD01     ; SAA1099 adresovaci port (write-only) (!DEV0_CS)

; SAA1099 registry
SAA_AM0     = $00       ; Amplituda kanal 0 (hi nib = levy, lo nib = pravy)
SAA_AM1     = $01       ; Amplituda kanal 1
SAA_AM2     = $02
SAA_AM3     = $03
SAA_AM4     = $04
SAA_AM5     = $05       ; Amplituda kanal 5
SAA_FQ0     = $08       ; Frekvence kanal 0 (0-255)
SAA_FQ1     = $09
SAA_FQ2     = $0A
SAA_FQ3     = $0B
SAA_FQ4     = $0C
SAA_FQ5     = $0D       ; Frekvence kanal 5
SAA_OC10    = $10       ; Oktava kanalu 0 (lo nib) + kanalu 1 (hi nib)
SAA_OC32    = $11       ; Oktava kanalu 2+3
SAA_OC54    = $12       ; Oktava kanalu 4+5
SAA_FQE     = $14       ; Povoleni frekvencniho generatoru (bit n = kanal n)
SAA_NOE     = $15       ; Povoleni sum generatoru
SAA_SOE     = $1C       ; Sound enable: $01=zap, $02=SW reset, $00=vyp

; ---------------------------------------------------------------------------
; Zero page - bezpecna oblast ($70-$75, mimo cc65/EWOZ/ROM oblasti)
; ---------------------------------------------------------------------------
ptr         = $70       ; 2 B - scratch pointer (precteny bajt z VRAM)
totfail     = $72       ; pocet neuspesnych testu celkem
tmp         = $73       ; scratch byte (vzor / status)
note_idx    = $74       ; index aktualniho tonu SAA (0-5)

; ---------------------------------------------------------------------------
.segment "CODE"
; ---------------------------------------------------------------------------

start:
    sei
    cld
    stz totfail

    jsr ROM_ACIA_INIT

    ; Inicializace VDP displeje — světle modrá = testování probíhá
    lda #$51            ; fg=5 light blue, bg=1 black
    jsr vdp_setup_screen

    lda #<str_banner
    ldx #>str_banner
    jsr ROM_GETS

    ; ===== TMS9918A testy =====

    lda #<str_tms_hdr
    ldx #>str_tms_hdr
    jsr ROM_GETS

    ; Test 1: STATUS registr
    lda #<str_tms_t1
    ldx #>str_tms_t1
    jsr ROM_GETS
    jsr tms_test_status

    ; Test 2: VRAM write/read $55
    lda #<str_tms_t2
    ldx #>str_tms_t2
    jsr ROM_GETS
    lda #$55
    jsr tms_test_vram

    ; Test 3: VRAM write/read $AA
    lda #<str_tms_t3
    ldx #>str_tms_t3
    jsr ROM_GETS
    lda #$AA
    jsr tms_test_vram

    ; ===== SAA1099 test =====

    lda #<str_saa_hdr
    ldx #>str_saa_hdr
    jsr ROM_GETS

    jsr saa_test_scale

    ; ===== Celkovy vysledek =====

    lda totfail
    bne @fail

    lda #$21            ; fg=2 medium green = PASS
    jsr vdp_setup_screen
    lda #<str_pass
    ldx #>str_pass
    jsr ROM_GETS
    jmp ROM_RST

@fail:
    lda #$81            ; fg=8 medium red = FAIL
    jsr vdp_setup_screen
    lda #<str_fail_a
    ldx #>str_fail_a
    jsr ROM_GETS
    lda totfail
    jsr ROM_PRTBYTE
    lda #<str_fail_b
    ldx #>str_fail_b
    jsr ROM_GETS
    jmp ROM_RST


; ---------------------------------------------------------------------------
; tms_test_status
; Precte VDP STATUS registr (VDP_CTRL = $C001, read = status).
; TMS9918A po power-on vraci typicky $9F nebo $1F (F-flag + sprite counter).
; $FF = chip nereaguje nebo sbernicovy float.
; Tiskne: "STATUS=$xx -> OK/FAIL"
; ---------------------------------------------------------------------------
tms_test_status:
    lda #$20
    jsr ROM_DELAY       ; kratky delay - chip mozna chvili po power-on

    lda VDP_CTRL        ; cteni STATUS registru
    sta tmp

    lda #<str_stat_pre
    ldx #>str_stat_pre
    jsr ROM_GETS        ; "STATUS=$"
    lda tmp
    jsr ROM_PRTBYTE     ; vytiskni xx
    lda #' '
    jsr ROM_PUTC

    lda tmp
    cmp #$FF
    beq @fail           ; $FF = bus float nebo chip chybi

    lda #<str_ok_nl
    ldx #>str_ok_nl
    jsr ROM_GETS
    rts

@fail:
    inc totfail
    lda #<str_fail_nl
    ldx #>str_fail_nl
    jsr ROM_GETS
    rts


; ---------------------------------------------------------------------------
; tms_test_vram
; A = testovaci vzor.
; Zapise vzor do VRAM[0] (adresa $0000), precte zpet a porovna.
; Pouziva inline NOP delay misto vdp_delay promenne z ROM kodu.
; VDP_DATA = $C000 (!VERA_CS), VDP_CTRL = $C001.
; ---------------------------------------------------------------------------
tms_test_vram:
    sta tmp             ; uloz vzor

    sei                 ; zakaz IRQ behem VDP pristupu

    ; Nastav write adresu VRAM $0000
    lda #$00
    sta VDP_CTRL        ; lo byte adresy
    jsr vdp_nop         ; min. 2us setup
    lda #($00 | $40)    ; hi byte | $40 = rezim zapisu
    sta VDP_CTRL
    jsr vdp_nop

    ; Zapis vzoru na VRAM[0]
    lda tmp
    jsr vdp_nop
    sta VDP_DATA
    jsr vdp_nop_long    ; >8us po VRAM zapisu (TMS9918A timing)

    ; Nastav read adresu VRAM $0000
    lda #$00
    sta VDP_CTRL        ; lo byte
    jsr vdp_nop
    lda #$00            ; hi byte bez $40 = rezim cteni
    sta VDP_CTRL
    jsr vdp_nop_long    ; prodleva pro prechod do read modu

    ; Precti bajt z VRAM[0]
    jsr vdp_nop
    lda VDP_DATA
    sta ptr             ; uloz precteny bajt

    cli                 ; povol IRQ

    ; Tisk "wrt=$xx rd=$xx "
    lda #<str_wrt
    ldx #>str_wrt
    jsr ROM_GETS
    lda tmp
    jsr ROM_PRTBYTE
    lda #<str_rd
    ldx #>str_rd
    jsr ROM_GETS
    lda ptr
    jsr ROM_PRTBYTE
    lda #' '
    jsr ROM_PUTC

    ; Porovnej precteny bajt se vzorem
    lda ptr
    cmp tmp
    bne @fail

    lda #<str_ok_nl
    ldx #>str_ok_nl
    jsr ROM_GETS
    rts

@fail:
    inc totfail
    lda #<str_fail_nl
    ldx #>str_fail_nl
    jsr ROM_GETS
    rts


; ---------------------------------------------------------------------------
; saa_test_scale
; Resetuje SAA1099, nastavi parametry kanalu 0 a zahraje stupnici
; C D E F G A (6 tonu, oktava 1, ~0.4s kazdy ton).
; SAA1099 je write-only -> test je sluchovy.
; Uzivatel odpovida y/n, pri 'n' se incrementuje totfail.
; ---------------------------------------------------------------------------
saa_test_scale:
    lda #<str_saa_rst
    ldx #>str_saa_rst
    jsr ROM_GETS        ; "[4/4] SAA reset+init ... "

    ; --- Reset SAA1099 ---
    ; Sekvence dle saa1099.asm: SOE=$02 (SW reset), SOE=$01 (enable)
    lda #SAA_SOE
    sta SAA_REG
    jsr saa_nop
    lda #$02
    sta SAA_DATA
    jsr saa_nop
    lda #SAA_SOE
    sta SAA_REG
    jsr saa_nop
    lda #$00
    sta SAA_DATA
    jsr saa_nop

    ; Vynuluj amplitudy AM0-AM5
    ldx #SAA_AM0        ; = $00
@clr_am:
    stx SAA_REG
    jsr saa_nop
    lda #$00
    sta SAA_DATA
    jsr saa_nop
    inx
    cpx #(SAA_AM5 + 1)  ; = $06
    bne @clr_am

    ; Vynuluj frekvencni registry FQ0-FQ5
    ldx #SAA_FQ0        ; = $08
@clr_fq:
    stx SAA_REG
    jsr saa_nop
    lda #$00
    sta SAA_DATA
    jsr saa_nop
    inx
    cpx #(SAA_FQ5 + 1)  ; = $0E
    bne @clr_fq

    ; Nastav oktavu kanalu 0+1 = 1 (shodne s noteAdr/channelAdr v saa1099.asm)
    lda #SAA_OC10
    sta SAA_REG
    jsr saa_nop
    lda #$11            ; lo nib = kanal 0 oktava 1, hi nib = kanal 1 oktava 1
    sta SAA_DATA
    jsr saa_nop

    ; Povol frekvencni generator pro kanal 0 (FQE bit 0 = 1)
    lda #SAA_FQE
    sta SAA_REG
    jsr saa_nop
    lda #$01
    sta SAA_DATA
    jsr saa_nop

    ; Zapni SAA (SOE = $01)
    lda #SAA_SOE
    sta SAA_REG
    jsr saa_nop
    lda #$01
    sta SAA_DATA
    jsr saa_nop

    lda #<str_saa_play
    ldx #>str_saa_play
    jsr ROM_GETS        ; "OK\r\n     Hraji: C D E F G A ..."

    ; --- Zahraj 6 tonu ze stupnice ---
    stz note_idx

@note_loop:
    ldx note_idx
    lda note_freq, x    ; frekvencni hodnota pro dany ton

    ; Nastav frekvenci na FQ0
    pha
    lda #SAA_FQ0
    sta SAA_REG
    jsr saa_nop
    pla
    sta SAA_DATA
    jsr saa_nop

    ; Max hlasitost AM0 = $FF (levy + pravy kanal plno)
    lda #SAA_AM0
    sta SAA_REG
    jsr saa_nop
    lda #$FF
    sta SAA_DATA
    jsr saa_nop

    ; Delay ~0.4s (3x ROM_DELAY $FF)
    lda #$FF
    jsr ROM_DELAY
    lda #$FF
    jsr ROM_DELAY
    lda #$FF
    jsr ROM_DELAY

    ; Ztlum AM0 (ticho mezi tony)
    lda #SAA_AM0
    sta SAA_REG
    jsr saa_nop
    lda #$00
    sta SAA_DATA
    jsr saa_nop

    ; Kratka pauza mezi tony (~0.1s)
    lda #$80
    jsr ROM_DELAY

    inc note_idx
    lda note_idx
    cmp #6
    bne @note_loop

    ; --- Vypni SAA ---
    lda #SAA_SOE
    sta SAA_REG
    jsr saa_nop
    lda #$00
    sta SAA_DATA
    jsr saa_nop

    ; --- Sluchovy verdikt od uzivatele ---
    lda #<str_saa_ask
    ldx #>str_saa_ask
    jsr ROM_GETS

@wait_key:
    jsr ROM_GETC
    ora #$20            ; toLower
    cmp #'y'
    beq @heard
    cmp #'n'
    beq @not_heard
    bra @wait_key

@heard:
    lda #<str_saa_ok
    ldx #>str_saa_ok
    jsr ROM_GETS
    rts

@not_heard:
    inc totfail
    lda #<str_saa_fail
    ldx #>str_saa_fail
    jsr ROM_GETS
    rts


; ---------------------------------------------------------------------------
; vdp_setup_screen
; Nastavi VDP Graphics I: cela obrazovka plna tile 0 s danou fg barvou.
; Vstup: A = color byte pro color table[0]: hi nibble = fg, lo nibble = bg.
;        Tile 0 = solid blok ($FF), fg barva pokryva celou obrazovku.
; Priklady: $51=light blue (init), $21=green (PASS), $81=red (FAIL)
; ---------------------------------------------------------------------------
vdp_setup_screen:
    sta tmp
    sei

    ; Tile 0: solid block -- 8 x $FF na VRAM $0800 (pattern base R4=1 -> $0800)
    ; Pozor: TMS testy zapisuji do VRAM $0000 -- pattern musi byt jinde!
    lda #$00
    sta VDP_CTRL        ; adresa lo = $00
    jsr vdp_nop
    lda #$48            ; ($0800>>8)|$40 = $48, write mode
    sta VDP_CTRL
    jsr vdp_nop
    ldx #8
@vss_tile:
    lda #$FF
    sta VDP_DATA
    jsr vdp_nop
    dex
    bne @vss_tile

    ; Color table[0] -- 1 bajt na VRAM $2000 (R3=$80 -> $80<<6=$2000)
    lda #$00
    sta VDP_CTRL        ; $2000 lo = $00
    jsr vdp_nop
    lda #$60            ; ($2000>>8)|$40 = $60
    sta VDP_CTRL
    jsr vdp_nop
    lda tmp
    sta VDP_DATA        ; color[0]: hi=fg, lo=bg
    jsr vdp_nop

    ; Name table: 768 x tile $00 na VRAM $1400 (R2=$05 -> $05<<10=$1400)
    lda #$00
    sta VDP_CTRL        ; $1400 lo = $00
    jsr vdp_nop
    lda #$54            ; ($1400>>8)|$40 = $54
    sta VDP_CTRL
    jsr vdp_nop
    ldx #3              ; 3 stranky x 256 = 768 bajtu (32x24 name table)
@vss_pg:
    ldy #0
@vss_by:
    stz VDP_DATA        ; tile index 0
    iny
    bne @vss_by
    dex
    bne @vss_pg

    ; VDP registry:
    ; R0 = $00  Graphics I, bez externiho videa
    lda #$00
    sta VDP_CTRL
    jsr vdp_nop
    lda #$80
    sta VDP_CTRL
    jsr vdp_nop
    ; R1 = $C0  16K RAM, screen enabled
    lda #$C0
    sta VDP_CTRL
    jsr vdp_nop
    lda #$81
    sta VDP_CTRL
    jsr vdp_nop
    ; R2 = $05  name table = $1400
    lda #$05
    sta VDP_CTRL
    jsr vdp_nop
    lda #$82
    sta VDP_CTRL
    jsr vdp_nop
    ; R3 = $80  color table = $2000
    lda #$80
    sta VDP_CTRL
    jsr vdp_nop
    lda #$83
    sta VDP_CTRL
    jsr vdp_nop
    ; R4 = $01  pattern = $0800  (mimo oblast VRAM testu)
    lda #$01
    sta VDP_CTRL
    jsr vdp_nop
    lda #$84
    sta VDP_CTRL
    jsr vdp_nop

    cli
    rts

; ---------------------------------------------------------------------------
; vdp_nop - ~2us delay pro VDP adresovy setup
; TMS9918A: min. 2us mezi zapisy na MODE1, 8us po VRAM zapisu.
; @ 4 MHz (1 cyklus = 250 ns): 8 NOP = 2us, vdp_nop_long = 4x = 8us.
; ---------------------------------------------------------------------------
vdp_nop:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop                 ; 8 NOP + JSR/RTS overhead = ~14 cyklu ~3.5us @ 4MHz
    rts

vdp_nop_long:
    jsr vdp_nop         ; ~4x = min 32+ cyklu = 8us @ 4MHz
    jsr vdp_nop
    jsr vdp_nop
    jsr vdp_nop
    rts

; ---------------------------------------------------------------------------
; saa_nop - setup delay pro SAA1099 (~100 ns min. po zapisu adresy/dat)
; @ 4 MHz: 1 cyklus = 250 ns, 4 NOP = 1 us (s rezervou).
; ---------------------------------------------------------------------------
saa_nop:
    nop
    nop
    nop
    nop
    nop
    nop
    rts


; ===========================================================================
.segment "RODATA"
; ===========================================================================

; Frekvencni hodnoty pro SAA1099, kanal 0, oktava 1
; Prevzaty z noteAdr tabulky v saa1099.asm (12-tonova chromaticka stupnice)
; Indexy 0,2,4,5,7,9 = C D E F G A
note_freq:
    .byte   5           ; C (index 0 z noteAdr)
    .byte  60           ; D (index 2)
    .byte 110           ; E (index 4)
    .byte 132           ; F (index 5)
    .byte 173           ; G (index 7)
    .byte 210           ; A (index 9)

str_banner:
    .byte $0D,$0A
    .byte "================================",$0D,$0A
    .byte "  P65 Chip Test: TMS + SAA",$0D,$0A
    .byte "================================",$0D,$0A
    .byte "VDP: $C000 (!VERA_CS)",$0D,$0A
    .byte "SAA: $CD00 (!DEV0_CS)",$0D,$0A,0

str_tms_hdr:
    .byte $0D,$0A,"--- TMS9918A VDP ($C000) ---",$0D,$0A,0

str_tms_t1:   .byte "[1/4] STATUS ... ",0
str_tms_t2:   .byte "[2/4] VRAM $55 ... ",0
str_tms_t3:   .byte "[3/4] VRAM $AA ... ",0
str_stat_pre: .byte "STATUS=$",0
str_wrt:      .byte "wrt=$",0
str_rd:       .byte " rd=$",0

str_saa_hdr:
    .byte $0D,$0A,"--- SAA1099 Zvuk ($CD00) ---",$0D,$0A,0

str_saa_rst:
    .byte "[4/4] SAA reset+init ... ",0

str_saa_play:
    .byte "OK",$0D,$0A
    .byte "     Hraji: C D E F G A ...",0

str_saa_ask:
    .byte $0D,$0A
    .byte "     Slysel jsi 6 tonu? [y/n]: ",0

str_saa_ok:   .byte "y -> PASS",$0D,$0A,0
str_saa_fail: .byte "n -> FAIL",$0D,$0A,0

str_ok_nl:    .byte "OK",$0D,$0A,0
str_fail_nl:  .byte "FAIL",$0D,$0A,0

str_pass:
    .byte $0D,$0A
    .byte ">>> PASS - chipy OK <<<",$0D,$0A
    .byte "Navrat do bootloaderu...",$0D,$0A,0

str_fail_a:
    .byte $0D,$0A
    .byte ">>> FAIL: ",0

str_fail_b:
    .byte " testu selhalo <<<",$0D,$0A
    .byte "Navrat do bootloaderu...",$0D,$0A,0


; ===========================================================================
; RAMVEC - musi byt na $7FFC (offset $1FFC od $6000)
; Bootloader skoci na adresu ulozenu na $7FFC po nahrani.
; ===========================================================================
.segment "RAMVEC"
    .addr start         ; $7FFC-$7FFD = adresa start ($6000)
    .addr start         ; $7FFE-$7FFF (nepouz., vyplneno)
