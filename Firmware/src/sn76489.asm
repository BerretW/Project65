.include "io.inc65"
;.include "macros_65C02.inc65"

.zeropage
song_addr:			.res 2
_song_pos:			.res 2
.smart		on
.autoimport	on
.case		on
.debuginfo	off
.importzp	sp, sreg, regsave, regbank
.importzp	tmp1, tmp2, tmp3, tmp4, ptr1, ptr2, ptr3, ptr4
.macpack	longbranch


.export _sn_init
.export _sn_write_data




.data
.import __delay2
.code

_sn_init:
            LDA #$FF
            STA SN_VIA_DDRA
            STA SN_VIA_DDRB
            LDA #%11111111
            STA SN_VIA_PORTB

            LDA #$9F
          	JSR _sn_write_data
						LDA #$BF
						JSR _sn_write_data
						LDA #$DF
          	JSR _sn_write_data
						LDA #$FF
						JSR _sn_write_data
            RTS

_sn_write_data:
						STA SN_VIA_PORTA
						LDA #%11110111
						STA SN_VIA_PORTB
						JSR __delay2
						LDA #%11110111
						STA SN_VIA_PORTB
            RTS
