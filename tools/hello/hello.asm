; hello.asm — ukázkový program pro AppartusOS
; Načtení:  LOAD  (pošli hello.hex přes serial)
; Uložení:  SAVE HELLO 3000 0042
; Spuštění: RUN HELLO
;
; Sestavení (ca65):
;   ca65 -t none hello.asm -o hello.o
;   ld65 -t none -S $3000 hello.o -o hello.bin
;   python ../ihex_gen.py hello.bin 3000 hello.hex

; ROM jump table (z kernel_api.inc)
.setcpu "65C02"
ROM_PRINTNL = $FF18     ; print null-terminated string + CR+LF (A=lo, X=hi)
VGA_BASE = $CE00

.org $3000

reset:
    lda #$00        ; Začneme s nulou
loop:
    sta VGA_BASE     ; Zápis do prvního registru FPGA
    inc VGA_BASE     ; Zkusíme zapsat i do druhého ($CF01)
    
    ; Malý delay, aby to neblikalo moc rychle
    ldx #$FF
d1: ldy #$FF
d2: dey
    bne d2
    dex
    bne d1

    clc
    adc #$01        ; Zvětšíme hodnotu pro příští zápis
    jmp loop



msg_hello:  .byte "Hello from Project65!", 0
msg_bye:    .byte "Program OK. Return to shell.", 0

; Velikost: $3042 - $3000 = $42 = 66 bajtů
; SAVE HELLO 3000 0042
