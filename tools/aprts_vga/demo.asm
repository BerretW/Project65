; aprts_vga demo pro SBC65C02
; Obvod je mapovany na $CFxx (A0-A3 -> registry)
;   $CF00 = ADDR_L
;   $CF01 = ADDR_M
;   $CF02 = ADDR_H (A18..A16 v bitech 2..0, krok v bitech 7..4)
;   $CF03 = DATA
;   $CF04 = CTRL (bit7 splash, bit0 mode: 0=text, 1=bitmap)
;   $CF05 = DEBUG/STATUS
;           write: bit0 debug enable, bit1 SRAM clear request, bits7..5 manual debug color
;           read:  bit7 write busy, bit6 read busy, bit5 SRAM clear busy, bit0 debug enable

	.setcpu "65C02"
	.include "../../Firmware/src/kernel_api.inc"

VGA_ADDR_L       = $CF00
VGA_ADDR_M       = $CF01
VGA_ADDR_H       = $CF02
VGA_DATA         = $CF03
VGA_CTRL         = $CF04
VGA_DEBUG        = $CF05

DBG_IDLE         = $01
DBG_CLEAR        = $23
DBG_PALETTE      = $41
DBG_FONT         = $61
DBG_SCREEN       = $81
DBG_TEXT         = $A1
DBG_DONE         = $C1

ZP_PTR_LO        = $20
ZP_PTR_HI        = $21
ZP_COUNT_LO      = $22
ZP_COUNT_HI      = $23
ZP_ATTR          = $24

	.segment "CODE"

start:
	jsr ROM_ACIA_INIT
	lda #<msg_start
	ldx #>msg_start
	jsr ROM_PRINTNL

	lda #<msg_clear_start
	ldx #>msg_clear_start
	jsr ROM_PRINTNL

	lda #DBG_CLEAR
	sta VGA_DEBUG
	jsr wait_sram_clear
	lda #<msg_clear_done
	ldx #>msg_clear_done
	jsr ROM_PRINTNL

	; Textovy rezim, paleta 0, splash off
	lda #$00
	sta VGA_CTRL
	lda #<msg_text_mode
	ldx #>msg_text_mode
	jsr ROM_PRINTNL

	lda #DBG_PALETTE
	sta VGA_DEBUG
	lda #<msg_palette
	ldx #>msg_palette
	jsr ROM_PRINTNL
	jsr init_palette0

	lda #DBG_FONT
	sta VGA_DEBUG
	lda #<msg_font
	ldx #>msg_font
	jsr ROM_PRINTNL
	jsr upload_font

	lda #DBG_SCREEN
	sta VGA_DEBUG
	lda #<msg_screen
	ldx #>msg_screen
	jsr ROM_PRINTNL
	jsr clear_text_screen

	lda #DBG_TEXT
	sta VGA_DEBUG
	lda #<msg_text
	ldx #>msg_text
	jsr ROM_PRINTNL

	; Radek 8, sloupec 22 -> offset (8*80+22)*2 = $042C
	lda #$2C
	ldx #$04
	ldy #$00
	jsr vga_set_addr_step1

	lda #<msg1
	sta ZP_PTR_LO
	lda #>msg1
	sta ZP_PTR_HI
	lda #$1E              ; zluta na modrem pozadi
	jsr write_string

	; Radek 10, sloupec 18 -> offset (10*80+18)*2 = $0664
	lda #$64
	ldx #$06
	ldy #$00
	jsr vga_set_addr_step1

	lda #<msg2
	sta ZP_PTR_LO
	lda #>msg2
	sta ZP_PTR_HI
	lda #$F1              ; bila na modrem pozadi
	jsr write_string

	lda #DBG_DONE
	sta VGA_DEBUG
	lda #<msg_done
	ldx #>msg_done
	jsr ROM_PRINTNL

	rts

; A=atribut, ZP_PTR_* ukazuje na 0-terminated text
write_string:
	sta ZP_ATTR
	ldy #$00
@loop:
	lda (ZP_PTR_LO),y
	beq @done
	jsr vga_write_data
	lda ZP_ATTR
	jsr vga_write_data
	iny
	bne @loop
@done:
	rts

vga_write_data:
	pha
@wait_ready:
	lda VGA_DEBUG
	bmi @wait_ready
	and #$20
	bne @wait_ready
	pla
	sta VGA_DATA
	rts

wait_sram_clear:
@wait_start:
	lda VGA_DEBUG
	and #$20
	beq @wait_start
	lda #<msg_clear_busy
	ldx #>msg_clear_busy
	jsr ROM_PUTS
	lda VGA_DEBUG
	jsr ROM_PRTBYTE
	jsr ROM_PUTNL
@wait_done:
	lda VGA_DEBUG
	and #$20
	bne @wait_done
	lda #<msg_clear_status
	ldx #>msg_clear_status
	jsr ROM_PUTS
	lda VGA_DEBUG
	jsr ROM_PRTBYTE
	jsr ROM_PUTNL
	rts

; Nastavi VGA adresu s krokem +1
; vstup: A=low, X=mid, Y=high(0..7)
vga_set_addr_step1:
	sta VGA_ADDR_L
	stx VGA_ADDR_M
	tya
	ora #$10
	sta VGA_ADDR_H
	rts

init_palette0:
	; Palette RAM start = $1F000
	lda #$00
	ldx #$F0
	ldy #$01
	jsr vga_set_addr_step1

	ldx #$00
@pal_loop:
	lda palette0_data,x
	jsr vga_write_data
	inx
	lda palette0_data,x
	jsr vga_write_data
	inx
	cpx #32
	bne @pal_loop
	rts

upload_font:
	; Font RAM start = $03000
	lda #$00
	ldx #$30
	ldy #$00
	jsr vga_set_addr_step1

	lda #<vdp_font
	sta ZP_PTR_LO
	lda #>vdp_font
	sta ZP_PTR_HI

	lda #$08              ; 8 * 256 B = 2048 B
	sta ZP_COUNT_HI
@page_loop:
	ldy #$00
@byte_loop:
	lda (ZP_PTR_LO),y
	jsr vga_write_data
	iny
	bne @byte_loop

	inc ZP_PTR_HI
	dec ZP_COUNT_HI
	bne @page_loop
	rts

clear_text_screen:
	; Text VRAM start = $00000
	lda #$00
	ldx #$00
	ldy #$00
	jsr vga_set_addr_step1

	; 80x60 bunek = 4800 znaku, kazda bunka 2 bajty
	lda #$C0              ; 4800 = $12C0
	sta ZP_COUNT_LO
	lda #$12
	sta ZP_COUNT_HI

@cell_loop:
	lda #$20              ; ' '
	jsr vga_write_data
	lda #$F1              ; bila na modrem pozadi
	jsr vga_write_data

	; 16bit dekrement counteru
	lda ZP_COUNT_LO
	bne @dec_lo
	dec ZP_COUNT_HI
@dec_lo:
	dec ZP_COUNT_LO

	lda ZP_COUNT_LO
	ora ZP_COUNT_HI
	bne @cell_loop
	rts

msg1:
	.asciiz "APRTS_VGA @ $CFxx"

msg2:
	.asciiz "TEXT MODE 80x60 / PALETTE 0"

msg_start:
	.asciiz "[VGA] demo start"

msg_clear_start:
	.asciiz "[VGA] SRAM clear request"

msg_clear_busy:
	.asciiz "[VGA] SRAM clear busy, status=$"

msg_clear_status:
	.asciiz "[VGA] SRAM clear done, status=$"

msg_clear_done:
	.asciiz "[VGA] clear complete"

msg_text_mode:
	.asciiz "[VGA] text mode, splash off"

msg_palette:
	.asciiz "[VGA] upload palette"

msg_font:
	.asciiz "[VGA] upload font"

msg_screen:
	.asciiz "[VGA] clear text screen"

msg_text:
	.asciiz "[VGA] write text"

msg_done:
	.asciiz "[VGA] demo done"

; 16 barev (RGB444), ulozeni po dvojicich [lowByte, highNibble]
palette0_data:
	.byte $00, $00  ; 0  black
	.byte $0A, $00  ; 1  blue
	.byte $A0, $00  ; 2  green
	.byte $AA, $00  ; 3  cyan
	.byte $00, $0A  ; 4  red
	.byte $0A, $0A  ; 5  magenta
	.byte $50, $0A  ; 6  brown
	.byte $AA, $0A  ; 7  light gray
	.byte $55, $05  ; 8  dark gray
	.byte $0F, $00  ; 9  bright blue
	.byte $F0, $00  ; 10 bright green
	.byte $FF, $00  ; 11 bright cyan
	.byte $00, $0F  ; 12 bright red
	.byte $0F, $0F  ; 13 bright magenta
	.byte $F0, $0F  ; 14 yellow
	.byte $FF, $0F  ; 15 white

	.include "font.asm"
