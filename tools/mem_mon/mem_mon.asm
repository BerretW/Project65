; mem_mon.asm — Monitor paměti inspirovaný MS-DOS DEBUG
;
; Příkazy:
;   D [AAAA]         — výpis 128 bajtů (16 řádků × 8 B) od AAAA nebo pokrač.
;   W AAAA BB [BB…]  — zápis bajtů na adresu
;   Q                — návrat do shellu
;
; Sestavení:
;   ca65 -t none mem_mon.asm -o mem_mon.o
;   ld65 -t none -S '$3200' mem_mon.o -o mem_mon.bin   # PowerShell
;   ld65 -t none -S $3200 mem_mon.o -o mem_mon.bin     # bash/cmd
;   python ../ihex_gen.py mem_mon.bin 3200 mem_mon.hex
;
; AppartusOS:
;   LOAD → SAVE MON 3200 0200 → RUN MON

ROM_PUTS    = $FF0C   ; print null-terminated string (A=lo, X=hi)
ROM_PRINTNL = $FF18   ; print string + CR+LF (A=lo, X=hi)
ROM_PUTC    = $FF09   ; print char in A
ROM_GETINP  = $FF21   ; wait for keyboard or serial → A
ROM_PUTNL   = $FF15   ; send CR+LF
ROM_PRTBYTE = $FF1B   ; print A as 2 hex digits

IBUF    = $0300       ; input line buffer (64 B, page 3 — volná RAM)
IBUF_SZ = 64

; ZP $F0–$F7 (mimo OS ZP $40–$53 a EWOZ $24–$30)
ZP_ARLO = $F0         ; aktuální adresa lo
ZP_ARHI = $F1         ; aktuální adresa hi
ZP_TMP  = $F2         ; scratch byte (výsledek try_hex2)
ZP_CNT  = $F3         ; čítač řádků dump
ZP_PTR  = $F4         ; 2-byte pointer pro (zp),Y čtení ($F4=lo, $F5=hi)
ZP_SAV  = $F6         ; uložená adresa pro restore v try_hex4 ($F6=lo, $F7=hi)

.org $3200

; ============================================================
start:
    LDA #<msg_banner
    LDX #>msg_banner
    JSR ROM_PRINTNL
    LDA #<msg_help
    LDX #>msg_help
    JSR ROM_PRINTNL
    LDA #$00
    STA ZP_ARLO
    STA ZP_ARHI

; ── hlavní smyčka ────────────────────────────────────────────
main_loop:
    LDA #<msg_prompt
    LDX #>msg_prompt
    JSR ROM_PUTS
    JSR get_line
    LDA IBUF
    BEQ main_loop

    ; uppercase prvního znaku
    CMP #'a'
    BCC @notlc
    CMP #'z'+1
    BCS @notlc
    SEC
    SBC #$20
    STA IBUF
@notlc:
    CMP #'D'
    BEQ cmd_dump
    CMP #'W'
    BEQ cmd_write
    CMP #'Q'
    BEQ cmd_quit
    LDA #<msg_unk
    LDX #>msg_unk
    JSR ROM_PRINTNL
    JMP main_loop

cmd_quit:
    RTS               ; návrat do shellu

; ── D [AAAA] ─────────────────────────────────────────────────
cmd_dump:
    LDX #1
    JSR skip_sp
    JSR try_hex4      ; C=1 = žádná adresa → pokrač. od aktuální

    LDA #16
    STA ZP_CNT
@drow:
    JSR dump_row
    DEC ZP_CNT
    BNE @drow
    JMP main_loop

; ── W AAAA BB [BB…] ──────────────────────────────────────────
cmd_write:
    LDX #1
    JSR skip_sp
    JSR try_hex4
    BCS @werr
    JSR skip_sp
    LDY #0
@wloop:
    LDA IBUF,X
    BEQ @wdone
    JSR try_hex2      ; → ZP_TMP, C=0 ok
    BCS @wdone
    LDA ZP_TMP
    STA (ZP_ARLO),Y   ; Y=0, standardní 6502 (zp),Y
    INC ZP_ARLO
    BNE @wskp
    INC ZP_ARHI
@wskp:
    JSR skip_sp
    JMP @wloop
@wdone:
    JMP main_loop
@werr:
    LDA #<msg_badaddr
    LDX #>msg_badaddr
    JSR ROM_PRINTNL
    JMP main_loop

; ── dump_row: jeden řádek AAAA: BB BB BB BB BB BB BB BB  ....
dump_row:
    LDA ZP_ARLO
    STA ZP_PTR
    LDA ZP_ARHI
    STA ZP_PTR+1

    ; adresa
    LDA ZP_ARHI
    JSR ROM_PRTBYTE
    LDA ZP_ARLO
    JSR ROM_PRTBYTE
    LDA #':'
    JSR ROM_PUTC
    LDA #' '
    JSR ROM_PUTC

    ; hex bajty
    LDY #0
@hex:
    LDA (ZP_PTR),Y
    JSR ROM_PRTBYTE
    LDA #' '
    JSR ROM_PUTC
    INY
    CPY #8
    BNE @hex

    LDA #' '
    JSR ROM_PUTC
    LDA #' '
    JSR ROM_PUTC

    ; ASCII
    LDY #0
@asc:
    LDA (ZP_PTR),Y
    CMP #$20
    BCC @dot
    CMP #$7F
    BCC @pr
@dot:
    LDA #'.'
@pr:
    JSR ROM_PUTC
    INY
    CPY #8
    BNE @asc

    JSR ROM_PUTNL

    ; posun adresy o 8
    LDA ZP_ARLO
    CLC
    ADC #8
    STA ZP_ARLO
    BCC @done
    INC ZP_ARHI
@done:
    RTS

; ── get_line: čte řádek do IBUF, null-terminuje ─────────────
get_line:
    LDX #0
@ch:
    JSR ROM_GETINP
    CMP #$0D
    BEQ @done
    CMP #$0A
    BEQ @done
    CMP #$08          ; BS
    BEQ @bs
    CMP #$7F          ; DEL
    BEQ @bs
    CPX #IBUF_SZ-1
    BCS @ch           ; buffer plný
    STA IBUF,X
    INX
    JSR ROM_PUTC      ; echo
    JMP @ch
@bs:
    CPX #0
    BEQ @ch
    DEX
    LDA #$08
    JSR ROM_PUTC
    LDA #' '
    JSR ROM_PUTC
    LDA #$08
    JSR ROM_PUTC
    JMP @ch
@done:
    LDA #0
    STA IBUF,X
    JSR ROM_PUTNL
    RTS

; ── skip_sp: přeskočí mezery v IBUF od X ────────────────────
skip_sp:
    LDA IBUF,X
    BEQ @done
    CMP #' '
    BNE @done
    INX
    JMP skip_sp
@done:
    RTS

; ── try_hex4: AAAA z IBUF+X → ZP_ARHI:ZP_ARLO ───────────────
; C=0 ok (X+=4), C=1 fail (adresa nezměněna)
try_hex4:
    LDA ZP_ARLO       ; ulož aktuální adresu pro případ selhání
    STA ZP_SAV
    LDA ZP_ARHI
    STA ZP_SAV+1

    JSR hex_nib
    BCS @fail
    ASL A
    ASL A
    ASL A
    ASL A
    STA ZP_ARHI
    INX
    JSR hex_nib
    BCS @fail
    ORA ZP_ARHI
    STA ZP_ARHI
    INX
    JSR hex_nib
    BCS @fail
    ASL A
    ASL A
    ASL A
    ASL A
    STA ZP_ARLO
    INX
    JSR hex_nib
    BCS @fail
    ORA ZP_ARLO
    STA ZP_ARLO
    INX
    CLC
    RTS
@fail:
    LDA ZP_SAV        ; obnov adresu
    STA ZP_ARLO
    LDA ZP_SAV+1
    STA ZP_ARHI
    SEC
    RTS

; ── try_hex2: BB z IBUF+X → ZP_TMP ─────────────────────────
; C=0 ok (X+=2), C=1 fail
try_hex2:
    JSR hex_nib
    BCS @fail
    ASL A
    ASL A
    ASL A
    ASL A
    STA ZP_TMP
    INX
    JSR hex_nib
    BCS @fail
    ORA ZP_TMP
    STA ZP_TMP
    INX
    CLC
    RTS
@fail:
    SEC
    RTS

; ── hex_nib: IBUF[X] → nibble v A. C=0 ok, C=1 chyba ────────
hex_nib:
    LDA IBUF,X
    CMP #'0'
    BCC @bad
    CMP #'9'+1
    BCC @digit
    AND #$DF            ; uppercase
    CMP #'A'
    BCC @bad
    CMP #'F'+1
    BCS @bad
    SEC
    SBC #'A'-10         ; 'A'→10 … 'F'→15  (s C=1: A - 55)
    CLC
    RTS
@digit:
    SEC
    SBC #'0'            ; C=1 zde: A - '0'
    CLC
    RTS
@bad:
    SEC
    RTS

; ── stringy ───────────────────────────────────────────────────
msg_banner:  .byte "P65 Memory Monitor", 0
msg_help:    .byte "D [AAAA]  W AAAA BB..  Q", 0
msg_prompt:  .byte "M> ", 0
msg_unk:     .byte "? neznamy prikaz", 0
msg_badaddr: .byte "? chybna adresa", 0
