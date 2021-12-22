.include "io.inc65"
.include "macros_65c02.inc65"

.zeropage

vdp_delay:			.res 1


.export _vdp_wr_reg
.export _vdp_wr_vram
.export _vdp_rd_vram
.export _vdp_rd_stat_reg
.export _vdp_wr_addr
.export _vdp_rd_addr
.export vdp_delay
.export vdp_peek
.export vdp_poke

.zeropage
.smart		on
.autoimport	on
.case		on
.debuginfo	off
.importzp	sp, sreg, regsave, regbank
.importzp	tmp1, tmp2, tmp3, tmp4, ptr1, ptr2, ptr3, ptr4
.macpack	longbranch





.code



;****************************************
;* vdp_wr_reg
;* Write to Register A the value X
;* Input : A - Register Number, X - Data
;* Output : None
;* Regs affected : P
;****************************************
_vdp_wr_reg:
		stx VDP_MODE1
		nop; Extra nop for fast CPU
		nop
		nop
		ora #$80
		sta VDP_MODE1
		eor #$80
		rts

;****************************************
;* _vdp_rd_stat_reg
;* Read VDP status register byte result  A
;* Input : none
;* Output : A - status register
;* Regs affected : P
;****************************************
_vdp_rd_stat_reg:
		LDA VDP_MODE1
		RTS


;****************************************
;* vdp_mem_wait
;* Delay some time before a memory access,
;* taking in to account mode 9918 needs up
;* to 3.1uS for text mode, 8uS for graphics
;* I and II
;* @ 5.35Mhz	= 16 cycles for 3.1uS
;*				= 43 cycles for 8uS
;* Input : None
;* Output : None
;* Regs affected : none
;****************************************
vdp_mem_wait:
								phx								; 3
								ldx vdp_delay				; 3
								beq vdp_mem_wait_end			; 3
vdp_mem_wait_loop:
								dex								; 2
								bne	vdp_mem_wait_loop			; 3
vdp_mem_wait_end:
								plx								; 3
								rts

;****************************************
;* vdp_wr_addr
;* Write to address in X (low) and A (high) - for writing
;* Input : A - Address high byte, X - Address low byte
;* Output : None
;* Regs affected : P
;****************************************
_vdp_wr_addr:
							stx VDP_MODE1
								; Extra nop for fast CPU
							nop
							nop
							nop
							nop
							ora #$40		; Required by VDP
							sta VDP_MODE1
							eor #$40		; Undo that bit
							rts

							;****************************************
							;* vdp_rd_addr
							;* Set read address
							;* Input : A - high, X - low
							;* Output : None
							;* Regs affected : None
							;****************************************
_vdp_rd_addr:
								stx VDP_MODE1
							; These nops are needed for fast CPU
								nop
								nop
								sta VDP_MODE1
								bra vdp_mem_wait
;****************************************
;* vdp_wr_vram
;* Write VRAM byte in A
;* Input : A - Byte to write
;* Output : None
;* Regs affected : None
;****************************************
_vdp_wr_vram:		nop
								nop
								nop
								sta VDP_MODE0
								bra vdp_mem_wait
;****************************************
;* vdp_rd_vram
;* Read VRAM byte, result in A
;* Input : None
;* Output : A - Byte from VRAM
;* Regs affected : P
;****************************************
_vdp_rd_vram:		nop
								nop
								nop
								lda VDP_MODE0
								bra vdp_mem_wait
								;****************************************
								;* vdp_poke
								;* Write VRAM byte in A, (YX)
								;* Input : A - Byte to write
								;*		   X = Low Address
								;*		   Y = High Address
								;* Output : None
								;* Regs affected : None
								;****************************************
vdp_poke:
									pha
									tya
									sei
									jsr _vdp_wr_addr
									pla
									jsr _vdp_wr_vram
									cli
									rts

								;****************************************
								;* vdp_peek
								;* Get VRAM byte in (AX)
								;*		   X = Low Address
								;*		   A = High Address
								;* Output : A = byte read
								;* Regs affected : None
								;****************************************
vdp_peek:
									sei
									jsr _vdp_rd_addr
									jsr _vdp_rd_vram
									cli
									rts
