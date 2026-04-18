.export _kb_input
.export _kb_init
.export _kb_rdy
.export _kb_check
.export _kb_poll

.setcpu "65C02"
.include "io.inc65"
;.include "macros.inc65"
;.include "zeropage.inc65"

.smart		on
.autoimport	on
; I/O Port definitions
.segment "DATA"

KB_BUF_SIZE = 16                  ; velikost bufferu, MUSI byt mocnina 2

kb_buf:   .res KB_BUF_SIZE        ; kruhovy buffer klaves
kb_head:  .res 1                  ; index pro zapis (producent = NMI)
kb_tail:  .res 1                  ; index pro cteni (konzument = hlavni smycka)

;
; I/O Port definitions
kb_data_or      =     VIA1_ORA
kb_data_ddr     =     VIA1_DDRA
kb_stat_or      =     VIA1_ORB            ; 6522 IO port register B
kb_stat_ddr     =     VIA1_DDRB             ; 6522 IO data direction register B
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

; void kb_poll()
; Zkontroluje klavesnici a pokud je k dispozici znak, ulozi ho do kruhoveho bufferu.
; Vola se z NMI handleru (pravideny casovac).
_kb_poll:     JSR _kb_rdy
              CMP #$FF
              BNE @done           ; zadny znak
              LDX kb_data_or      ; precti znak z VIA2 port A
              JSR _delay
              LDA #$00
              STA kb_stat_or      ; potvrdi prijem (ACK - PB1 low)
              JSR _delay
              LDA #$FF
              STA kb_stat_or      ; uvolni ACK
              JSR _delay
              ; zkontroluj jestli buffer neni plny: (head+1) % SIZE == tail
              LDA kb_head
              INC A
              AND #(KB_BUF_SIZE - 1)
              CMP kb_tail
              BEQ @done           ; buffer plny, znak zahod
              ; uloz znak na pozici head
              TXA
              LDY kb_head
              STA kb_buf, Y
              ; posuv head
              LDA kb_head
              INC A
              AND #(KB_BUF_SIZE - 1)
              STA kb_head
@done:        RTS

; char kb_input()
; Vrati dalsi znak z kruhoveho bufferu, nebo 0 pokud je prazdny.
_kb_input:    LDA kb_tail
              CMP kb_head
              BEQ @empty          ; tail == head = buffer je prazdny
              TAY
              LDA kb_buf, Y       ; nacti znak
              PHA
              LDA kb_tail
              INC A
              AND #(KB_BUF_SIZE - 1)
              STA kb_tail         ; posuv tail
              PLA
              RTS
@empty:       LDA #$00
              RTS


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
