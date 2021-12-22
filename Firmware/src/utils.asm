.include "io.inc65"
.include "macros_65C02.inc65"

.zeropage
_delay_lo:				.res 1
_delay_hi:				.res 1
TQ:               .res 1
B:                .res 1

.setcpu		"65C02"
.smart		on
.autoimport	on
.case		on
.debuginfo	off
.importzp	sp, sreg, regsave, regbank, _in_char , BANK_BASE
.importzp	tmp1, tmp2, tmp3, tmp4, ptr1, ptr2, ptr3, ptr4
.macpack	longbranch

.export __delay2
.export _delay
.export _via_test
.export _echo_test
.export _write_to_RAM
.export _start_ram
.export _init_vec
.export _input_scan
.export _get_input
.export _print_byte
.export _irq_init
.export _nmi_init
.export _divide
.export TQ
.export B

.segment	"RODATA"
gong:
.byte $9F,$BF,$DF,$FF,$90,$8D,$17,$9F,00

.segment "CODE"

_input_scan:lda     #$00
            jsr     pusha
            jsr     _kb_input
            sta     (sp)
            ldx     #$00
            lda     (sp)
            bne     L0001
            jsr     _acia_scan
            sta     (sp)
            ldx     #$00
            L0001:	lda     (sp)
            jmp     incsp1

_get_input: lda     #$00
            jsr     pusha
            bra     L0004
L0002:	    jsr     _input_scan
            sta     (sp)
L0004:	    ldx     #$00
            lda     (sp)
            beq     L0002
            jmp     incsp1

_irq_init:        ;LDA #$FF
                  ;STA VIA1_T1C_H      ;set hibyte of Timer1 counter
                  ;LDA #$40
                  ;STA VIA1_ACR        ;setup continuous interrupts without PB7
                  ;LDA #$C0
                  ;STA VIA1_IER        ;enable TIMER1 interrupt
                  RTS

_nmi_init:        LDA #$FF
                  STA VIA2_T1C_H      ;set hibyte of Timer1 counter
                  LDA #$40
                  STA VIA2_ACR        ;setup continuous interrupts without PB7
                  LDA #$C0
                  STA VIA2_IER        ;enable TIMER1 interrupt
                  RTS


_divide:          LDA #0
                  LDX #8
                  ASL TQ
@L1:              ROL
                  CMP B
                  BCC @L2
                  SBC B
@L2:              ROL TQ
                  DEX
                  BNE @L1
                  RTS



_print_byte:      PHA ;Save A for LSD.
                  LSR
                  LSR
                  LSR ;MSD to LSD position.
                  LSR
                  JSR _PRHEX       ;Output hex digit.
                  PLA ;Restore A.
_PRHEX:           AND #$0F        ;Mask LSD for hex print.
                  ORA #$B0        ;Add "0".
                  CMP #$BA        ;Digit?
                  BCC @ECHO        ;Yes, output it.
                  ADC #$06        ;Add offset for letter.
@ECHO:             PHA ;*Save A
                  AND #$7F        ;*Change to "standard ASCII"
                  JSR _acia_putc    ;*ACIA not done yet, wait.
                  PLA ;*Restore A
                  RTS ;*Done, over and out...



_init_vec:          LDA #<_IRQ_ISR
                    STA _irq_vec
                    LDA #>_IRQ_ISR
                    STA _irq_vec + 1
                    LDA #<_NMI_ISR
                    STA _nmi_vec
                    LDA #>_NMI_ISR
                    STA _nmi_vec + 1
                    RTS





_echo_test:
@lll:               JSR _get_input
                    JSR _VDP_print_char

                    JMP @lll



_start_ram:         PLA
                    JMP (RAMDISK_RESET_VECTOR)

_via_test:	LDA #$FF
						STA VIA2_DDRA
						LDA #$55
						STA VIA2_ORA
						JSR _delay
						LDA #$AA
						STA VIA2_ORA
						JSR _delay
						JMP _via_test






_write_to_RAM:
        				        LDY #0
        				        LDA #<(RAMDISK_START)
        				        LDX #>(RAMDISK_START)
        				        STA ptr1
        				        STX ptr1 + 1

@write:			    JSR _acia_getc
                ;JSR _lcd_putc
                STA (ptr1), Y
                INY
                CPY #$0
                BNE @end
                INX
                STX ptr1 + 1
                CPX #>(RAMDISK_END+1)
                BNE @end
                JMP (RAMDISK_RESET_VECTOR)
@end:			      JMP @write




_delay:
  STA _delay_lo  ; save state
  LDA #$00
  STA _delay_hi  ; high byte
delayloop:
  ADC #01
  BNE delayloop
  CLC
  INC _delay_hi
  BNE delayloop
  CLC
  ; exit
  LDA _delay_lo  ; restore state
  RTS

__delay2:				LDX #$2
__delay3:				DEX
                BNE __delay3
                RTS
