.zeropage

.smart		on
.autoimport	on
.case		on
.debuginfo	off
.importzp	sp, sreg, regsave, regbank
.importzp	tmp1, tmp2, tmp3, tmp4, ptr1, ptr2, ptr3, ptr4
.macpack	longbranch

.export _INTE
.export _INTD

.segment "CODE"

_INTE:  CLI
        RTS

_INTD:  SEI
        RTS
