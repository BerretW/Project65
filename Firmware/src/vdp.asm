.include "io.inc65"
.include "macros_65c02.inc65"
.include "font.h"



.zeropage
_vdp_reg0:			.res 1
_vdp_reg1:			.res 1
_vdp_color:     .res 1

vdp_addr_nme: .res 2				;* Address of name table
vdp_addr_col: .res 2				;* Address of colour table
vdp_addr_pat: .res 2				;* Address of pattern table
vdp_addr_spa: .res 2				;* Address of sprite pattern table
vdp_addr_spp: .res 2				;* Address of sprite position table
vdp_bord_col: .res 2
.globalzp _vdp_reg0, _vdp_reg1

.smart		on
.autoimport	on
.case		on
.debuginfo	off
.importzp	sp, sreg, regsave, regbank, vdp_delay,tmpstack
.importzp	tmp1, tmp2, tmp3, tmp4, ptr1, ptr2, ptr3, ptr4
.macpack	longbranch


.export _vdp_init
.export _vdp_set_bgc, _vdp_set_fnc, _VDP_print_char, _vdp_fill
.export init_vdp_txt,vdp_addr_nme
.export _vdp_puts, _vdp_print_nl
.code
;_init:

_vdp_init:          CLD
                    ;JSR clear_vram
                    LDA #0
                    JSR gr_init_screen
                    JSR vdp_set_txt_mode

                    LDA #1
                    JSR _vdp_set_bgc
                    LDA #$D
                    JSR _vdp_set_fnc

                    LDX #$1F
                    LDA #$7
                    JSR _vdp_wr_reg
                    LDX #0
                    LDY #0
                    JSR gr_set_cur
                    RTS

_VDP_print_char:    JSR gr_put_byte
                    RTS

_vdp_puts:          phay
                    sta ptr1
                    stx ptr1 + 1
                    ldy #0
@next_char:         lda (ptr1),y
                    beq @eos
                    jsr gr_put_byte
                    iny
                    bne @next_char
@eos:               play
                    rts


_vdp_print_nl:      JSR _vdp_puts
_vdp_put_newline:   JSR gr_new_ln
                    RTS

_vdp_fill:          PHA
                    LDX #$0
                    LDA #$0
                    JSR _vdp_wr_addr
                    PLA
                    LDY #$40
                    JSR vdp_fill_vram
                    RTS

_vdp_set_bgc:       PHA
                    LDA _vdp_color
                    AND #%11110000
                    STA _vdp_color
                    PLA
                    ORA _vdp_color
                    STA _vdp_color

                    TAX
                    LDA #$7
                    JSR _vdp_wr_reg
                    RTS


_vdp_set_fnc:       PHA
                    LDA _vdp_color
                    AND #%00001111
                    STA _vdp_color
                    PLA
                    ROR
                    ROR
                    ROR
                    ROR
                    ORA _vdp_color
                    STA _vdp_color

                    TAX
                    LDA #$7
                    JSR _vdp_wr_reg
                    RTS


vdp_fill_vram:
                  	jsr _vdp_wr_vram
                  	dex
                  	bne vdp_fill_vram
                  	dey
                  	bne vdp_fill_vram
                  	rts

;****************************************
                    ;* clear_vram
                    ;* Set all 16k VDP vram to 0x00
                    ;* Input : None
                    ;* Output : None
                    ;* Regs affected : All
                    ;****************************************
clear_vram:
                                        ;	sei
                    ldx #$00			; Low byte of address
                    lda #$00			; High byte of address
                    jsr _vdp_wr_addr		; Write address to VDP

                    ldy #$40			; 0x40 pages = 16k (X already zero)
                    jsr vdp_fill_vram
                    ;	cli
                    rts

                    ;****************************************
                    ;* _vdp_init_mode
                    ;* Initialise VDP  to required mode and addresses
                    ;* Input : Y = Offset in to VDP init table
                    ;* Output : None
                    ;* Regs affected : All
                    ;****************************************

_vdp_init_mode:
                    	sei
                    	ldx vdp_base_table+0,y		; Get delay
                    	stx vdp_delay

                    	lda	#0						; Do R0
                    	ldx vdp_base_table+1,y		; Get R0 value
                    	jsr _vdp_wr_reg				; Write X to Reg A

                    	lda	#1						; Do R1
                    	ldx vdp_base_table+2,y		; Get R1 value
                    	jsr _vdp_wr_reg				; Write X to Reg A

                    	ldx vdp_base_table+3,y		; Get name table low address
                    	stx vdp_addr_nme	; Save in vdp_base
                    	ldx vdp_base_table+4,y		; Get name table high address
                    	stx vdp_addr_nme+1	; Save in vdp_base
                    	lda #2						; Do R2
                    	ldx vdp_base_table+5,y		; Get R2 value
                    	jsr _vdp_wr_reg				; Write X to Reg A

                    	ldx vdp_base_table+6,y		; Get col table low address
                    	stx vdp_addr_col	; Save in vdp_base
                    	ldx vdp_base_table+7,y		; Get col table high address
                    	stx vdp_addr_col+1	; Save in vdp_base
                    	lda #3						; Do R3
                    	ldx vdp_base_table+8,y		; Get R3 value
                    	jsr _vdp_wr_reg				; Write X to Reg A

                    	ldx vdp_base_table+9,y		; Get pat table low address
                    	stx vdp_addr_pat	; Save in vdp_base
                    	ldx vdp_base_table+10,y		; Get pat table high address
                    	stx vdp_addr_pat+1	; Save in vdp_base
                    	lda #4						; Do R4
                    	ldx vdp_base_table+11,y		; Get R4 value
                    	jsr _vdp_wr_reg				; Write X to Reg A

                    	ldx vdp_base_table+12,y		; Get spr att table low address
                    	stx vdp_addr_spa	; Save in vdp_base
                    	ldx vdp_base_table+13,y		; Get spr att table high address
                    	stx vdp_addr_spa+1	; Save in vdp_base
                    	lda #5						; Do R5
                    	ldx vdp_base_table+14,y		; Get R5 value
                    	jsr _vdp_wr_reg				; Write X to Reg A

                    	ldx vdp_base_table+15,y		; Get spr pat table low address
                    	stx vdp_addr_spp	; Save in vdp_base
                    	ldx vdp_base_table+16,y		; Get spr pat table high address
                    	stx vdp_addr_spp+1	; Save in vdp_base
                    	lda #6						; Do R6
                    	ldx vdp_base_table+17,y		; Get R6 value
                    	jsr _vdp_wr_reg				; Write X to Reg A

                    	lda #7						; Do R7
                    	ldx vdp_base_table+18,y		; Get R7 value
                    	stx vdp_bord_col	; Save border colour
                    	jsr _vdp_wr_reg				; Write X to Reg A

                    	cli

                    	rts

;****************************************
;* vdp_set_txt_mode
;* Set up text mode
;* Input : None
;* Output : None
;* Regs affected : All
;****************************************
vdp_set_txt_mode:
	ldy #vdp_base_table_txt-vdp_base_table
	jsr _vdp_init_mode
	jmp init_fonts




;****************************************
;* vdp_set_g1_mode
;* Set up G1 mode
;* Input : None
;* Output : None
;* Regs affected : All
;****************************************
vdp_set_g1_mode:
	ldy #vdp_base_table_g1-vdp_base_table
	jsr _vdp_init_mode
	jmp init_fonts

;****************************************
;* vdp_set_g2_mode
;* Set up G2 mode
;* Input : None
;* Output : None
;* Regs affected : All
;****************************************
vdp_set_g2_mode:
	ldy #vdp_base_table_g2-vdp_base_table
	jsr _vdp_init_mode
	jmp init_fonts

;****************************************
;* vdp_set_hires
;* Set up HI mode
;* Input : None
;* Output : None
;* Regs affected : All
;****************************************
vdp_set_hires:
	ldy #vdp_base_table_hi-vdp_base_table
	jsr _vdp_init_mode

	; No fonts to init but pre-fill name table
	; to use all 3 character sets
	sei

	; Point at name table
	ldx vdp_addr_nme
	lda vdp_addr_nme+1
	jsr _vdp_wr_addr

	; set name for 3 pages (768)
	ldx #0
	ldy #3
vdp_set_hires_fill_nme:
	txa						; Name table is 0..255 for 3 pages
	jsr _vdp_wr_vram
	inx
	bne vdp_set_hires_fill_nme
	dey
	bne vdp_set_hires_fill_nme

	cli

	rts



;****************************************
;* init_vdp_g1
;* Initialise video processor graphics 1
;* Input : None
;* Output : None
;* Regs affected : All
;***************************************
init_vdp_g1:
	jsr vdp_set_g1_mode
	jsr init_sprtpat_g1
	jsr init_colours_g1
	jsr init_sprites_g1
	rts

;****************************************
;* init_vdp_g1
;* Initialise video processor graphics 1
;* Input : None
;* Output : None
;* Regs affected : All
;***************************************
init_vdp_g2:
	jsr vdp_set_g2_mode
	jsr init_sprtpat_g1		; Same as G1
	jsr init_colours_g2
	jsr init_sprites_g1		; Same as G1
	rts

;****************************************
;* init_vdp_hires
;* Initialise video processor graphics 1
;* Input : None
;* Output : None
;* Regs affected : All
;***************************************
init_vdp_hires:
	jsr vdp_set_hires
	jsr init_sprtpat_g1
	jmp init_sprites_g1


;****************************************
;* init_vdp_txt
;* Initialise video processor text mode
;* Input : None
;* Output : None
;* Regs affected : All
;***************************************
init_vdp_txt:
	jmp vdp_set_txt_mode




;****************************************
;* init_colours_g1
;* Initialise colour table for graphics 1
;* Input : None
;* Output : None
;* Regs affected : All
;****************************************
init_colours_g1:
	sei
	ldx vdp_addr_col
	lda vdp_addr_col+1
	jsr _vdp_wr_addr				; Set VDP address

	ldx #$20					; 32 bytes to fill
	ldy #$01					; Only 1 pass through
	lda vdp_bord_col	; Border colour
	jsr vdp_fill_vram
	cli
	rts

;****************************************
;* init_colours_g2
;* Initialise colour table for graphics 2
;* Input : None
;* Output : None
;* Regs affected : All
;****************************************
init_colours_g2:
	sei
	ldx vdp_addr_col
	lda vdp_addr_col+1
	jsr _vdp_wr_addr				; Set VDP address

	ldx #$00					; 2048 bytes to fill
	ldy #$08					; 8 pass through
	lda vdp_bord_col	; Border colour
	jsr vdp_fill_vram
	cli
	rts

;****************************************
;* init_sprites_g1
;* Initialise sprite attribute table for graphics 1
;* Input : None
;* Output : None
;* Regs affected : All
;****************************************
init_sprites_g1:
	sei
	ldx vdp_addr_spa
	lda vdp_addr_spa+1
	jsr _vdp_wr_addr				; Set VDP address

	ldx #$80					; 128 bytes of attribute to fill
	ldy #$01					; Only 1 pass
	lda #$d0					; Sprite terminator
	jsr vdp_fill_vram
	cli
	rts

;****************************************
;* init_fonts
;* Initialise fonts
;* Input : None
;* Output : None
;* Regs affected : All
;****************************************
init_fonts:
	sei
	ldx vdp_addr_pat
	lda vdp_addr_pat+1
	jsr _vdp_wr_addr				; Write the address
	jsr init_fonts_sub
	cli
	rts

;****************************************
;* init_sprtpat_g1
;* Initialise fonts for sprites
;* Input : None
;* Output : None
;* Regs affected : All
;****************************************
init_sprtpat_g1:
	sei
	ldx vdp_addr_spp
	lda vdp_addr_spp+1
	jsr _vdp_wr_addr				; Write the address
	jsr init_fonts_sub
	cli
	rts

;****************************************
;* init_fonts_sub
;* Initialise fonts common subroutine
;* Input : None
;* Output : None
;* Regs affected : All
;* INTERRUPTS MUST HAVE BEEN DISABLED BY CALLER!!!
;****************************************
init_fonts_sub:
	stz tmp1;tmp_a				; XOR with zero = no change
	ldy #0					; byte within page
init_write_fonts:
	lda #<(vdp_font)		; Low byte of fonts source
	sta tmp2;tmp_alo
	lda #>(vdp_font)		; High byte of fonts source
	sta tmp3;tmp_ahi
	ldx #$04				; 4 pages = 1024 bytes
init_pattern:
	tya
	lda (tmp2),y			; Get byte from font table
	eor tmp1				; Invert if tmp_a is 0xff
	jsr _vdp_wr_vram			; Write the byte to VRAM
	iny
	bne init_pattern		; keep going for 1 page
	inc tmp3				; only need to increment high byte of font ptr
	dex						; page counter
	bne init_pattern		; keep going for 4 pages
	lda tmp1				; get the current eor mask
	eor	#$ff				; Invert the EOR mask
	sta tmp1				; And save for next go around
	bne init_write_fonts
	rts


vdp_base_table:
vdp_base_table_g1:
                    	.Byte	2	; Long delay
                    	.Byte	%00000000		; R0 - No-extvid
                    	.Byte	%11100000		; R1 - 16K,Disp-enable,Int-enable,8x8,No-mag
                    	.WORD	$1000			; Name table address
                    	.Byte	$1000>>10		; R2 Name table value
                    	.WORD	$1380			; Colour table
                    	.Byte	$1380>>6		; R3 Colour table value
                    	.WORD	$0000			; Pattern table
                    	.Byte	$0000>>11		; R4 Pattern table value
                    	.WORD	$1300			; Sprite attribute table
                    	.Byte	$1300>>7		; R5 Sprite attribute table value
                    	.WORD	$0800			; Sprite pattern table
                    	.Byte	$0800>>11		; R6 Sprite pattern table value
                    	.Byte	$f4			; R7 White f/gnd, blue background

vdp_base_table_g2:
                    	.Byte	2	; Long delay
                    	.Byte	%00000010		; R0 - GR2HiRes,No-extvid
                    	.Byte	%11100000		; R1 - 16K,Disp-enable,Int-enable,8x8,No-mag
                    	.WORD	$3800			; Name table address
                    	.Byte	$3800>>10		; R2 Name table value
                    	.WORD	$2000			; Colour table
                    	.Byte	$9f			; R3 Colour table magic value 0x9f
                    	.WORD	$0000			; Pattern table
                    	.Byte	$0000>>11		; R4 Pattern table value
                    	.WORD	$3b00			; Sprite attribute table
                    	.Byte	$3b00>>7		; R5 Sprite attribute table value
                    	.WORD	$1800			; Sprite pattern table
                    	.Byte	$1800>>11		; R6 Sprite pattern table value
                    	.Byte	$fc			; R7 White f/gnd, green background

vdp_base_table_hi:
                    	.Byte	2	; Long delay
                    	.Byte	%00000010		; R0 - GR2HiRes,No-extvid
                    	.Byte	%11100000		; R1 - 16K,Disp-enable,Int-enable,8x8,No-mag
                    	.WORD	$3800			; Name table
                    	.Byte	$3800>>10		; R2 Name table value
                    	.WORD	$2000			; Colour table
                    	.Byte	$ff			; R3 Colour table value - always 0xff
                    	.WORD	$0000			; Pattern table
                    	.Byte	$03			; R4 Pattern table value - always 0x03
                    	.WORD	$3b00			; Sprite attribute table
                    	.Byte	$3b00>>7		; R5 Sprite attribute table value
                    	.WORD	$1800			; Sprite pattern table
                    	.Byte	$1800>>11		; R6 Sprite pattern table value
                    	.Byte	$f4			; R7 White f/gnd, blue background

vdp_base_table_txt:
                    	.Byte	1	; Short delay
                    	.Byte	%00000000		; R0 - No-extvid $00
                    	.Byte	%11010000		; R1 - 16K,Disp-enable,Int-enable,TXT,8x8,No-mag !!!!!!!!!!!!!!!!!!!! Int-disable $D0
                    	.WORD	$0800			; screen image table table
                    	.byte	$0800>>10		; R2 screen image table table value
                    	.WORD	0				; Colour table NA
                    	.Byte	0				; R3 Colour table value
                    	.WORD	$0000			; Pattern table
                    	.BYTE	$0000>>11		; R4 Pattern table value
                    	.WORD	0				; Sprite attribute table NA
                    	.Byte	0				; R5 Sprite attribute table value
                    	.WORD	0				; Sprite pattern table NA
                    	.Byte	0				; R6 Sprite pattern table value
                    	.Byte	$fD			; R7 White f/gnd, magenta background
mod_sz_vdp_e:
