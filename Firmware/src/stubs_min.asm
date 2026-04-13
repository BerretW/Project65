; stubs_min.asm
; Nahradni (prazdne) implementace pro minimalni build.
; Nahradi PS2 klavesnici a VDP - zadne z techto zarizeni neni v minimal FW pouzito.

.setcpu     "65C02"
.smart      on
.autoimport on

.export _kb_input
.export _kb_poll
.export gr_put_byte
.export _VDP_print_char

.segment "CODE"

; char kb_input()
; V minimalnim buildu presmeruje na _acia_scan (neblokovaci cteni ze serioveho portu).
; Pokud je v bufferu ACIA znak, vrati ho; jinak vrati 0.
; Pouzivano z ewoz.asm (NEXTCHAR smycka) a utils.asm (_input_scan).
_kb_input:  JMP _acia_scan

; void kb_poll()
; V minimalnim buildu neni pouzivano (NMI_Event je prazdna).
_kb_poll:   RTS

; gr_put_byte - vystup jednoho znaku na VDP.
; V minimalnim buildu ignoruj (VDP neni zapojeno).
gr_put_byte:
; void _VDP_print_char(char c)
; Totez - bez VDP pouze zahoz znak.
_VDP_print_char:
            RTS
