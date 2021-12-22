
;SPI registerss

SPI_DATA   = $C000
SPI_CSSEL		=	SPI_DATA + 3
SPI_STATUS	=	SPI_DATA + 1
SPI_DIV     = SPI_DATA + 2
SPI_CS			= $0			;CS0 = $E, CS1=$D, CS2=$B, CS3=$7


;.import popa, popax
.importzp tmp1, tmp2,tmp3


data = tmp1
adrH = tmp2
adrL = tmp3

;.export _spi_write_to
.export _spi_begin
.export _spi_end
.export _spi_write
.export _spi_write_16_addr
.export _spi_write_16_data
.export _spi_read
.export _spi_init
.export _spi_test
.code



; void spi_write_to(char * buffer, char c)
; @in A (n) char to write
; @in popax (buffer) address in SPI

;_spi_write_to:      STA tmp1
;										JSR popax
;										STA tmp3
;										STX tmp2
;										LDA #$7
;										STA SPI_CSSEL
;										LDA tmp2
;										ADC #$80
;										JSR _spi_write
;										LDA tmp3
;										JSR _spi_write
;										LDA tmp1
;										JSR _spi_write
;										LDA #$F
;										STA SPI_CSSEL
;                    RTS

_spi_test:				LDA SPI_DATA
									;CMP #$00
									BEQ @pass
									LDA #$0
									RTS
@pass:						LDA #$FF
 									RTS

_spi_init:					LDA #04
										STA SPI_STATUS
										JSR spi_delay
										;LDA #0
										;STA SPI_DIV
										RTS

_spi_write:					STA SPI_DATA
										JSR spi_delay
										;JSR spi_delay
										;JSR spi_delay
										RTS

_spi_write_16_addr:	PHA
										TXA
										JSR _spi_write
										PLA
										JSR _spi_write
										RTS
_spi_write_16_data:
										JSR _spi_write
										TXA
										;JSR spi_delay
										JSR _spi_write
										RTS

_spi_read:					JSR _spi_write
										LDA SPI_DATA
										JSR spi_delay
										RTS

_spi_begin:					;JSR _SPI_TRAN
										JSR spi_delay
										LDA #%11111110
										STA SPI_CSSEL
										JSR spi_delay
										RTS


_SPI_TRAN:					TAX
										SEC
										LDA #$FE
@p1:								DEX
										BEQ @end
										ROL
										JMP @p1
@end:								AND #$F
										CLC
										RTS


_spi_end:						PHA
										;LDA SPI_DATA
										LDA #$FF
										STA SPI_CSSEL
										PLA
										RTS

spi_delay:					;RTS
										LDY #$D4
@_delay_1:					DEY
										BNE @_delay_1
										RTS
