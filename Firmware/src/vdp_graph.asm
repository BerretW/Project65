.include "io.inc65"
.include "macros_65c02.inc65"





.smart		on
.autoimport	on
.case		on
.debuginfo	off
.importzp	sp, sreg, regsave, regbank, vdp_addr_nme,tmpstack
.importzp	tmp1, tmp2, tmp3, tmp4, ptr1, ptr2, ptr3, ptr4
.macpack	longbranch
.export gr_init_screen_common, gr_init_screen_txt, gr_init_screen, gr_cls, gr_set_cur, gr_put, gr_plot, gr_get, gr_cur_right,gr_cur_up,gr_cur_down, gr_put_byte, gr_new_ln
tmp_a = tmp1
tmp_ahi = tmp2
tmp_alo = tmp3
tmp_bhi = tmp4
tmp_blo = ptr1
; VDP parameters
vdp_cnt:		.res	1		; VDP interrupt counter
vdp_cnt_hi:		.res		1		; VDP counter high
vdp_cnt_hi2:		.res	1		; VDP counter high 2
vdp_curoff:		.res		1		; Cursor off (0 = On)
vdp_curstat:		.res		1		; Cursor status
vdp_curval:		.res		1		; Cursor value on screen
vdp_blank:		.res		1		; Screen blank value normally 32
vdp_delay:		.res		1

.data
gr_screen_start: .res 2			; Start of screen memory in VDP
gr_screen_size: .res 2			; Number of bytes screen occupies
gr_screen_w: .res 1			; Number of columns
gr_screen_h: .res 1			; Number of rows
gr_cur_off: .res 1				; Y offset of cursor image from current position
gr_cur_x: .res 1					; Current X position of cursor
gr_cur_y: .res 1					; Current Y position of cursor
gr_cur_ptr: .res 2				; VDP address of cursor
gr_pixmode: .res 1				; Pixel plot mode (0=Erase, 1=Plot, 2=XOR)
gr_pixmask: .res 1				; Pixel plot mask
gr_pixcol: .res 1				; Pixel colour
gr_geom_tmp: .res 2			; One word of temp storage for local use
scratch:		.res 256
.code
mod_sz_graph_s:

;****************************************
;* gr_init_screen_common
;* Common screen initialisation code
;* A = Blank character
;****************************************
gr_init_screen_common:
	; Store blank char
	sta vdp_blank
	; Save value for cursor
	sta vdp_curval

	; VRAM address of screen data
	lda vdp_addr_nme
	sta gr_screen_start
	lda vdp_addr_nme+1
	sta gr_screen_start+1

	; Top left cursor position 0,0
	ldx #0
	stx gr_cur_x
	ldy #0
	sty gr_cur_y

	; Clear screen
	jsr gr_cls

	; Cursor pointer in to screen
	jsr gr_set_cur

	rts


;****************************************
;* gr_init_screen_txt
;* initialise the screen in text mode
;****************************************
gr_init_screen_txt:
	jsr init_vdp_txt

	; Size of screen in bytes
	lda #<(960)
	sta gr_screen_size
	lda #>(960)
	sta gr_screen_size+1

	; Width and height
	lda #40
	sta gr_screen_w
	lda #24
	sta gr_screen_h
	stz gr_cur_off		; No cursor offset

	lda #' '						; Blank is SPACE
	jsr gr_init_screen_common

	rts


;****************************************
;* gr_init_screen
;* A = Mode (0 = text, Not zero = graphic)
;* initialise the screen in text mode
;****************************************
gr_init_screen:
	cmp #0
	bne gr_init_skip_txt
	jmp gr_init_screen_txt
gr_init_skip_txt:
	jmp gr_init_screen_txt

;****************************************
;* gr_cls
;* Clear the screen
;****************************************
gr_cls:
	pha
	phx
	phy

	; Set VDP Address
	sei
	ldx gr_screen_start
	lda gr_screen_start+1
	jsr _vdp_wr_addr

	; X and Y count bytes to fill
	ldx #0
	ldy #0
	lda vdp_blank
gr_cls_loop:
	jsr _vdp_wr_vram
	inx
	bne gr_cls_skipy
	iny
gr_cls_skipy:
	cpx gr_screen_size
	bne gr_cls_loop
	cpy gr_screen_size+1
	bne gr_cls_loop

	cli

	ply
	plx
	pla

	rts

;****************************************
;* gr_getXY_ptr
;* Get VRAM address of screen from X,Y
;* Input : X, Y = coords
;* Output : X,Y = low and high VRAM address
;* Regs affected : A
;****************************************
gr_getXY_ptr:
	; 32 or 40 columns table selection
	lda gr_screen_w
	cmp #40
	bne gr_set_skip_40

	clc
	lda gr_offset_40lo, y
	adc gr_screen_start
	sta gr_geom_tmp
	lda gr_offset_40hi, y
	adc gr_screen_start+1
	sta gr_geom_tmp+1
	bra gr_add_x_offset

gr_set_skip_40:
	; 32 byte width window - but what if hi-res (because cursor offset not zero)
	lda gr_cur_off
	bne gr_calc_hires_ptr
	clc
	lda gr_offset_32lo, y
	adc gr_screen_start
	sta gr_geom_tmp
	lda gr_offset_32hi, y
	adc gr_screen_start+1
	sta gr_geom_tmp+1

gr_add_x_offset:
	clc
	txa
	adc gr_geom_tmp
	tax								; vram addr lo in X
	lda gr_geom_tmp+1
	adc #0
	tay								; vram addr hi in Y
	rts

gr_calc_hires_ptr:
	; Low byte = X&F8 | Y&07
	txa
	and #$f8
	sta gr_geom_tmp
	tya
	and #$07
	ora gr_geom_tmp
	tax			; Low address in X
	; High byte = Y>>3
	tya
	lsr a
	lsr a
	lsr a
	tay			; High address in Y
	rts

;****************************************
;* gr_plot
;* Write a byte in the screen pos
;* Input : X,Y = coord, A = Byte to put
;* Output : None
;* Regs affected : All
;****************************************
gr_plot:
	pha					; Save byte to put
	jsr gr_getXY_ptr	; vram addr in x,y
	pla					; Get byte to put
	jsr vdp_poke
	rts

;****************************************
;* gr_put
;* Write a byte in the current cursor position
;* Input : A = Byte to put
;* Output : None
;* Regs affected : All
;****************************************
gr_put:
	inc vdp_curoff		; Disable cusror
	sta vdp_curval		; Update cursor value
	; Load cursor address
	ldx gr_cur_ptr
	ldy gr_cur_ptr+1
	jsr vdp_poke
	dec vdp_curoff		; Allow cursor flashing
	rts


;****************************************
;* gr_get
;* Get the byte in the screen pos
;* Input : X,Y = coord
;* Output : X,Y = address, A = peeked byte
;* Regs affected : All
;****************************************
gr_get:
	jsr gr_getXY_ptr	; vram addr in x,y
	tya					; hi needs to be in A for peek
	jsr vdp_peek
	rts

;****************************************
;* gr_set_cur
;* Set the cursor position
;* Input : X, Y = position
;* Output : None
;* Regs affected : None
;****************************************
gr_set_cur:
	inc vdp_curoff				; Disable cursor

	; Save new cursor position
	stx gr_cur_x
	sty gr_cur_y

	; First restore what is under the cursor
	lda vdp_curval
	jsr gr_put

	; Now calculate the new cursor vram address
	ldx gr_cur_x
	ldy gr_cur_y
	jsr gr_get					; X,Y=address,A=vram contents
	stx gr_cur_ptr
	sty gr_cur_ptr+1
	sta vdp_curval

	dec vdp_curoff

	rts

	;****************************************
	;* gr_scroll_up
	;* Scroll screen one line up
	;****************************************
	gr_scroll_up:
		inc vdp_curoff

		; Get VDP Address of line + 1 line (source addr)
		clc
		lda gr_screen_start
		adc gr_screen_w
		sta tmp_alo
		lda gr_screen_start+1
		adc #0
		sta tmp_ahi

		; Get destinaton address = first line of screen
		lda gr_screen_start
		sta tmp_blo
		lda gr_screen_start+1
		sta tmp_bhi

		ldy gr_screen_h
		dey

		sei						; Stop IRQ as it messes with VDP
		; Only use vdp primitives inside sei,cli

		; Restore what was underneath cursor
		ldx gr_cur_ptr
		lda gr_cur_ptr+1
		jsr _vdp_wr_addr
		lda vdp_curval
		jsr _vdp_wr_vram

	gr_scroll_cpy_ln:
		; Set VDP with source address to read
		ldx tmp_alo
		lda tmp_ahi
		jsr _vdp_rd_addr

		; Read in a line worth of screen
		ldx gr_screen_w
	gr_scroll_read_ln:
		jsr _vdp_rd_vram
		sta scratch,x
		dex
		bne gr_scroll_read_ln

		; Set VDP with destinaton to write
		ldx tmp_blo
		lda tmp_bhi
		jsr _vdp_wr_addr

		; Write out a line worth of screen
		ldx gr_screen_w
	gr_scroll_write_ln:
		lda scratch,x
		jsr _vdp_wr_vram
		dex
		bne gr_scroll_write_ln

		; Update source address
		clc
		lda tmp_alo
		adc gr_screen_w
		sta tmp_alo
		lda tmp_ahi
		adc #0
		sta tmp_ahi
		; Update destinaton address
		clc
		lda tmp_blo
		adc gr_screen_w
		sta tmp_blo
		lda tmp_bhi
		adc #0
		sta tmp_bhi

		; One line complete
		dey
		bne gr_scroll_cpy_ln

		; VDP is pointing at last line
		; Needs to be filled with blank
		lda vdp_blank
		sta vdp_curval			; Also this is the cursor value
		ldx gr_screen_w
	gr_scroll_erase_ln:
		jsr _vdp_wr_vram
		dex
		bne gr_scroll_erase_ln

		cli			; Enable IRQ

		dec vdp_curoff

		rts


		;****************************************
		;* gr_cur_right
		;* Advance cursor position
		;* Input : None
		;* Output : None
		;* Regs affected : None
		;****************************************
		gr_cur_right:
			phaxy
			; Load cursor x,y position
			ldx gr_cur_x
			ldy gr_cur_y

			; Move cursor right
			inx
			; Check if reached past edge of line
			cpx gr_screen_w
			bne gr_adv_skip_nl
			; If got here then wrap to next line
			ldx #0
			iny
			cpy gr_screen_h
			bne gr_adv_skip_nl
			; If got here then screen needs to scroll
			dey					; First put y back in bound
			phx
			phy
			jsr gr_scroll_up
			ply
			plx
		gr_adv_skip_nl:
			jsr gr_set_cur
			plaxy
			rts

		;****************************************
		;* gr_cur_left
		;* Advance cursor left
		;* Input : None
		;* Output : None
		;* Regs affected : None
		;****************************************
		gr_cur_left:
			phaxy
			; Load cursor x,y position, load X last to check for 0
			ldy gr_cur_y
			ldx gr_cur_x

			; Decrement screen pointer
			; Move cursor left
			bne gr_cur_skip_at_left		; If already at the left
			cpy #0						; If already at the top left
			beq gr_cur_skip_at_tl
			dey
			ldx gr_screen_w
		gr_cur_skip_at_left:
			dex
			jsr gr_set_cur

		gr_cur_skip_at_tl:
			plaxy
			rts

		;****************************************
		;* gr_cur_up
		;* Advance cursor up
		;* Input : None
		;* Output : None
		;* Regs affected : None
		;****************************************
		gr_cur_up:
			phaxy
			; Load cursor x,y position, load Y last to check for zero
			ldx gr_cur_x
			ldy gr_cur_y

			beq gr_cur_skip_at_top	; If already at the top, don't do anything
			dey
			jsr gr_set_cur

		gr_cur_skip_at_top:
			plaxy
			rts

		;****************************************
		;* gr_cur_down
		;* Advance cursor down
		;* Input : None
		;* Output : None
		;* Regs affected : None
		;****************************************
		gr_cur_down:
			phaxy
			; Load cursor x,y position
			ldx gr_cur_x
			ldy gr_cur_y
			iny
			cpy gr_screen_h			; If already at  bottom
			beq gr_cur_skip_at_bot				; then don't do anything

			jsr gr_set_cur

		gr_cur_skip_at_bot:
		 	plaxy
			rts


	;****************************************
	;* gr_new_ln
	;* Carry out a new line
	;* Input : None
	;* Output : None
	;* Regs affected : None
	;****************************************
	gr_new_ln:
		phaxy
		; X pos is zero, Y needs to increment
		ldx #0
		ldy gr_cur_y
		iny
		cpy gr_screen_h
		bne gr_nl_skip_nl
		; If got here then screen needs to scroll
		dey
		phx
		phy
		jsr gr_scroll_up
		ply
		plx
	gr_nl_skip_nl:
		jsr gr_set_cur
		plaxy
		rts

		;****************************************
		;* gr_del
		;* Action del
		;* Input : None
		;* Output : None
		;* Regs affected : None
		;****************************************
		gr_del:
			phaxy
			jsr gr_cur_left
			lda #' '							; Put a space
			jsr gr_put
			plaxy
			rts

		;****************************************
		;* gr_put_byte
		;* Put a byte out
		;* Input : A = Byte to put
		;* Output : None
		;* Regs affected : None
		;****************************************
		gr_put_byte:
			cmp #UTF_DEL			; Del key
			beq gr_process_special
			cmp #32					; Special char?
			bcs gr_pb_notspecial	; >=32 == carry clear

		gr_process_special:
			cmp #UTF_CR				; New line?
			bne gr_skip_new_ln
			jmp gr_new_ln
		gr_skip_new_ln:
			cmp #UTF_DEL			; Delete?
			bne gr_skip_del
			jmp gr_del
		gr_skip_del:
			cmp #CRSR_LEFT
			bne gr_skip_left
			jmp gr_cur_left
		gr_skip_left:
			cmp #CRSR_RIGHT
			bne gr_skip_right
			jmp gr_cur_right
		gr_skip_right:
			cmp #CRSR_UP
			bne gr_skip_up
			jmp gr_cur_up
		gr_skip_up:
			cmp #CRSR_DOWN
			bne gr_skip_down
			jmp gr_cur_down
		gr_skip_down:
			cmp #UTF_FF
			bne gr_skip_cls
			jmp gr_cls
		gr_skip_cls:
			rts

		;	Normal caracter processing here.
		gr_pb_notspecial:
			phaxy

			; Place in current position and move right
			jsr gr_put
			jsr gr_cur_right

			plaxy

			rts


	gr_offset_40lo:
	.byte<(0*40), <(1*40), <(2*40), <(3*40)
	.byte<(4*40), <(5*40), <(6*40), <(7*40)
	.byte<(8*40), <(9*40), <(10*40), <(11*40)
	.byte<(12*40), <(13*40), <(14*40), <(15*40)
	.byte<(16*40), <(17*40), <(18*40), <(19*40)
	.byte<(20*40), <(21*40), <(22*40), <(23*40)
	gr_offset_40hi:
	.byte>(0*40), >(1*40), >(2*40), >(3*40)
	.byte>(4*40), >(5*40), >(6*40), >(7*40)
	.byte>(8*40), >(9*40), >(10*40), >(11*40)
	.byte>(12*40), >(13*40), >(14*40), >(15*40)
	.byte>(16*40), >(17*40), >(18*40), >(19*40)
	.byte>(20*40), >(21*40), >(22*40), >(23*40)
	gr_offset_32lo:
	.byte<(0*32), <(1*32), <(2*32), <(3*32)
	.byte<(4*32), <(5*32), <(6*32), <(7*32)
	.byte<(8*32), <(9*32), <(10*32), <(11*32)
	.byte<(12*32), <(13*32), <(14*32), <(15*32)
	.byte<(16*32), <(17*32), <(18*32), <(19*32)
	.byte<(20*32), <(21*32), <(22*32), <(23*32)
	gr_offset_32hi:
	.byte>(0*32), >(1*32), >(2*32), >(3*32)
	.byte>(4*32), >(5*32), >(6*32), >(7*32)
	.byte>(8*32), >(9*32), >(10*32), >(11*32)
	.byte>(12*32), >(13*32), >(14*32), >(15*32)
	.byte>(16*32), >(17*32), >(18*32), >(19*32)
	.byte>(20*32), >(21*32), >(22*32), >(23*32)
