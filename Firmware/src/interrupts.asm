.include "io.inc65"

.setcpu		"65C02"
.smart		on
.autoimport	on
.case		on

.export _IRQ_ISR
.export _NMI_ISR


.segment "CODE"

_NMI_ISR:         PHA
                  PHX
                  PHY
                  JSR _NMI_Event
                  LDA #$4D
                  STA VIA2_T1C_H
@end:             PLY
                  PLX
                  PLA
                  RTI


_IRQ_ISR:         SEI
                  PHA
                  PHX
                  PHY
                  ;LDA #$FF
                  ;STA VIA1_T1C_H
                  JSR _IRQ_Event
                  CLI
                  PLY
                  PLX
                  PLA
                  RTI
