; aprts_vga demo pro SBC65C02
; Obvod je mapovany na $CFxx (A0-A3 -> registry)
;   $CF00 = ADDR_L
;   $CF01 = ADDR_M
;   $CF02 = ADDR_H (A18..A16 v bitech 2..0, krok v bitech 7..4)
;   $CF03 = DATA
;   $CF04 = CTRL (bit7 splash, bit0 mode: 0=text, 1=bitmap)
;   $CF05 = DEBUG (bit0 debug overlay enable)

	.setcpu "65C02"

VGA_ADDR_L       = $CF00
VGA_ADDR_M       = $CF01
VGA_ADDR_H       = $CF02
VGA_DATA         = $CF03
VGA_CTRL         = $CF04
VGA_DEBUG        = $CF05

ZP_PTR_LO        = $20
ZP_PTR_HI        = $21
ZP_COUNT_LO      = $22
ZP_COUNT_HI      = $23
ZP_ATTR          = $24

	.segment "CODE"

start:
	lda #$01
	sta VGA_DEBUG

	; Textovy rezim, paleta 0, splash off
	lda #$00
	sta VGA_CTRL

	jsr init_palette0
	jsr upload_font
	jsr clear_text_screen

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

	rts

; A=atribut, ZP_PTR_* ukazuje na 0-terminated text
write_string:
	sta ZP_ATTR
	ldy #$00
@loop:
	lda (ZP_PTR_LO),y
	beq @done
	sta VGA_DATA
	lda ZP_ATTR
	sta VGA_DATA
	iny
	bne @loop
@done:
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
	sta VGA_DATA
	inx
	lda palette0_data,x
	sta VGA_DATA
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
	sta VGA_DATA
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
	sta VGA_DATA
	lda #$F1              ; bila na modrem pozadi
	sta VGA_DATA

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
