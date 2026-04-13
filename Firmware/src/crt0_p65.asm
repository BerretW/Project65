; crt0_p65.asm - P65 startup pro cc65 >= V2.19
;
; Poskytuje symbol _init ktery jumptable.asm vklada jako RESET vektor.
; Pouziva copydata/zerobss/callmain z none.lib.
; Kompatibilni s cc65 c_sp konvenci.
;
; Startup sekvence:
;   1. Nastav hw zasobnik ($01FF)
;   2. Nastav cc65 softwarovy zasobnik na __STACKSTART__
;   3. copydata  - inicializovana data z ROM -> RAM
;   4. zerobss   - nuluj BSS
;   5. callmain  - zavolej _main() pres cc65 konvenci (argc=0, argv=0)
;   6. Po navratu soft reset

.setcpu     "65C02"
.smart      on
.autoimport on
.case       on

.import     copydata, zerobss, callmain
.importzp   c_sp
.import     __STACKSTART__

.export     _init

.segment    "STARTUP"

_init:
        ; Inicializuj hw zasobnik 6502 na $01FF
        ldx     #$FF
        txs

        ; Nastav cc65 softwarovy zasobnik na vrchol RAM oblasti
        lda     #<(__STACKSTART__)
        sta     c_sp
        lda     #>(__STACKSTART__)
        sta     c_sp+1

        ; Zkopiruj inicializovana data z ROM do RAM
        jsr     copydata

        ; Nuluj BSS segment
        jsr     zerobss

        ; Zavolej _main() pres cc65 callmain (nastavi argc=0, argv=0)
        jsr     callmain

        ; Po navratu z main - soft restart (nemel by nastat)
        jmp     _init
