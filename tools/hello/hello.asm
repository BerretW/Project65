; hello.asm — ukázkový program pro AppartusOS
; Načtení:  LOAD  (pošli hello.hex přes serial)
; Uložení:  SAVE HELLO 3000 0042
; Spuštění: RUN HELLO
;
; Sestavení (ca65):
;   ca65 -t none hello.asm -o hello.o
;   ld65 -t none -S $3000 hello.o -o hello.bin
;   python ihex_gen.py hello.bin 3000 > hello.hex

; ROM jump table (z kernel_api.inc)
ROM_PRINTNL = $FF18     ; print null-terminated string + CR+LF (A=lo, X=hi)

.org $3000

start:
    LDA #<msg_hello
    LDX #>msg_hello
    JSR ROM_PRINTNL

    LDA #<msg_bye
    LDX #>msg_bye
    JSR ROM_PRINTNL

    RTS                 ; návrat do shellu

msg_hello:  .byte "Hello from Project65!", 0
msg_bye:    .byte "Program OK. Return to shell.", 0

; Velikost: $3042 - $3000 = $42 = 66 bajtů
; SAVE HELLO 3000 0042
