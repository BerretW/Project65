.zeropage

.smart		on
.autoimport	on
.case		on
.debuginfo	off
.importzp	sp, sreg, regsave, regbank
.importzp	tmp1, tmp2, tmp3, tmp4, ptr1, ptr2, ptr3, ptr4
.macpack	longbranch

.export	_RST
.export	_INTEN
.export	_INTDI
.export	_JPUTC
.export	_JGETS
.export	_JGETC
.export	_JSCAN
.export	_JPUTNL
.export	_JPRINTNL
.export	_JPRTBYTE
.export	_JINSCAN
.export	_JGETINP
.export	_JDELAY
.export	_JACIA_INIT
.export	_JIRQ_INIT
.export	_JNMI_INIT
.export	_JINIT_VEC


.segment "JMPTBL"

; ---------------------------------------------------------------------------
; Tabulka skoků na pevných adresách — každá položka je 3 bajty (JMP abs).
; Programy mohou JSR/JMP přímo na tyto adresy bez importu symbolů.
; Viz jumptable.inc65 pro pojmenované konstanty.
; ---------------------------------------------------------------------------

_RST:        JMP _main            ; $FF00  Restart / návrat do bootloaderu
_INTEN:      JMP _INTE            ; $FF03  Povolení přerušení (CLI)
_INTDI:      JMP _INTD            ; $FF06  Zakázání přerušení (SEI)
_JPUTC:      JMP _acia_putc       ; $FF09  Odešli znak v A na sériový port
_JGETS:      JMP _acia_puts       ; $FF0C  Odešli řetězec (ptr A/X, null-term)
_JGETC:      JMP _acia_getc       ; $FF0F  Čekej a přijmi znak -> A
_JSCAN:      JMP _acia_scan       ; $FF12  Neblokovací příjem -> A (0 = nic)
_JPUTNL:     JMP _acia_put_newline ; $FF15 Odešli CR+LF
_JPRINTNL:   JMP _acia_print_nl   ; $FF18  Odešli řetězec + CR+LF
_JPRTBYTE:   JMP _print_byte      ; $FF1B  Tisk A jako 2 hex znaky na serial
_JINSCAN:    JMP _input_scan      ; $FF1E  Scan klávesnice nebo sériového portu -> A
_JGETINP:    JMP _get_input       ; $FF21  Čekej na vstup (kbd nebo serial) -> A
_JDELAY:     JMP _delay           ; $FF24  Softwarové zpoždění (délka v A)
_JACIA_INIT: JMP _acia_init       ; $FF27  Inicializace ACIA (19200 8N1)
_JIRQ_INIT:  JMP _irq_init        ; $FF2A  Inicializace IRQ timeru (VIA2)
_JNMI_INIT:  JMP _nmi_init        ; $FF2D  Inicializace NMI timeru (VIA1)
_JINIT_VEC:  JMP _init_vec        ; $FF30  Nastav IRQ/NMI vektory na ISR


.segment "CODE"
; ---------------------------------------------------------------------------
; Non-maskable interrupt (NMI) service routine

_nmi_int:     JMP (_nmi_vec)
                                 ; Return from all NMI interrupts

; ---------------------------------------------------------------------------
; Maskable interrupt (IRQ) service routine
_irq_int:     JMP (_irq_vec)


.segment  "VECTORS"

.addr      _nmi_int    ; NMI vector
.addr      _init     ; Reset vector
.addr      _irq_int    ; IRQ/BRK vector
