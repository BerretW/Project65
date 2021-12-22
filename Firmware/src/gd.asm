.include "io.inc65"
.include "gd.inc65"
.include "macros_65C02.inc65"
.include "zeropage.inc65"


	.fopt		compiler,"cc65 v 2.19 - Git a861d84"
	.setcpu		"65C02"
	.smart		on
	.autoimport	on
	.case		on
	.debuginfo	off
	.importzp	sp, sreg, regsave, regbank, _spr, tmpstack
	.importzp	tmp1, tmp2, tmp3, tmp4, ptr1, ptr2, ptr3, ptr4
	.macpack	longbranch
	.export _GD_WR_8
	.export _GD_WR_16
	.export _GD_RD_8





	;.exportzp _in_char


.segment	"CODE"






; ---------------------------------------------------------------
; void GD_wr_8(char * addr, char data)
; ldx     #$28	HiByte of address
; lda     #$09	LoByte of address
; jsr     pushax
; lda     #$01		data to write
; jsr     _GD_wr
; in A = data to write
; ---------------------------------------------------------------
_GD_WR_8: 		jsr     pusha
							ldy     #$02
							jsr     ldaxysp
							jsr     __wstart
							lda     (sp)
							jsr     _spi_write
							jsr     __end
							jmp     incsp3

; --------------------------------------------------------------
; void GD_wr_16(char * addr, char data)
; ldx     #$28	HiByte of address
; lda     #$09	LoByte of address
; jsr     pushax
; lda     #$01		HiByte of data to write
; ldx			#$00		LoByte of data to write
; jsr     _GD_wr_16
; in A = data to write
; ---------------------------------------------------------------
_GD_WR_16: 			jsr     pushax
								ldy     #$03
								jsr     ldaxysp
								jsr     __wstart
								jsr     ldax0sp
								jsr     _spi_write_16_data
								jsr     __end
								jmp     incsp4
; ---------------------------------------------------------------
;	GD_rd
; in X = Hibyte of address
; in A = Lobyte of address
; out A = return byte
; return
; ---------------------------------------------------------------
_GD_RD_8:		TAY
						LDA #14
						JSR _spi_begin
						TYA

						JSR _spi_write_16_addr

						LDA #$0
						JSR _spi_read
						STA ptr1
						JSR _spi_end
						LDA ptr1
						RTS
