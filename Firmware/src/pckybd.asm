.export _kb_input
.export _kb_init
.export _kb_rdy
.export _kb_check

.setcpu "65C02"
.include "io.inc65"
;.include "macros.inc65"
;.include "zeropage.inc65"

.smart		on
.autoimport	on
; I/O Port definitions
.segment "DATA"

;
; I/O Port definitions
kb_data_or      =     VIA2_ORA
kb_data_ddr     =     VIA2_DDRA
kb_stat_or      =     VIA2_ORB            ; 6522 IO port register B
kb_stat_ddr     =     VIA2_DDRB             ; 6522 IO data direction register B
;kb status
kb_rdy          =     $FE
kb_ack          =     $FF

.segment "CODE"

_kb_init:     LDA #$2
              STA kb_stat_ddr           ;set VIA2_PB1 to output
              JSR _delay
              LDA #$FF
              STA kb_stat_or
              JSR _delay
              LDA #$00
              STA kb_data_ddr
              JSR _delay
              RTS

_kb_input:    JSR _kb_rdy
              CMP #$FF
              BNE @end
              LDX kb_data_or
              JSR _delay
              LDA #$00
              STA kb_stat_or
              JSR _delay
              LDA #$FF
              STA kb_stat_or
              JSR _delay
              TXA
              JMP _delay
@end:         LDA #$00
              JMP _delay


_kb_check:    LDA VIA2_ORA
              BNE @end
              RTS
@end:         LDA #$FF
              RTS


_kb_rdy:      LDA kb_stat_or
              CMP #$FE
              BEQ @end1
              LDA #$0
@end:         RTS
@end1:        LDA #$FF
              RTS

_delay:         PHX
                LDX #$4
_delay_2:       DEX
                BNE _delay_2
                PLX
                RTS

_delay2:				LDX #$FF
                LDY #$FF
_delay3:				DEX
                BNE _delay3
                DEY
                BEQ @end
                LDX #$FF
                JMP _delay3

@end:           RTS
