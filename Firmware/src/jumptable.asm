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





.segment "JMPTBL"


_RST:	JMP	_main		;$FF1E	Restart to bootloader
_INTEN:	JMP	_INTE		;$FF33	Enable Interrupts
_INTDI:	JMP	_INTD		;$FF36	Disable Interrupts

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
