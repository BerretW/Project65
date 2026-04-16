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
                  STA VIA1_T1C_H    ; Bug #2 fix: NMI generuje VIA1 (IC18), ne VIA2
@end:             PLY
                  PLX
                  PLA
                  RTI


_IRQ_ISR:         PHA
                  PHX
                  PHY
                  ;LDA #$FF
                  ;STA VIA1_T1C_H
                  JSR _IRQ_Event
                  PLY
                  PLX
                  PLA
                  RTI         ; RTI obnoví I-flag ze zásobníku — CLI před RTI bylo špatně
