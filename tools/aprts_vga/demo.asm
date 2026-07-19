; demo.asm - test APRTS VGA FPGA pro AppartusOS
; FPGA registry jsou dekodovane od $CF00.
;
; Sestaveni:
;   build.bat
;
; Nacteni v AppartusOS:
;   LOAD              ; posli demo.hex pres serial
;   SAVE VGADEMO 3100 088B
;   RUN VGADEMO

ROM_PUTC    = $FF09
ROM_PUTS    = $FF0C
ROM_PUTNL   = $FF15
ROM_PRINTNL = $FF18
ROM_PRTBYTE = $FF1B

VGA_BASE    = $CF00
VGA_ADDR_L  = VGA_BASE + 0
VGA_ADDR_M  = VGA_BASE + 1
VGA_ADDR_H  = VGA_BASE + 2
VGA_DATA    = VGA_BASE + 3
VGA_CTRL    = VGA_BASE + 4
VGA_STATUS  = VGA_BASE + 5
VGA_FAIL_L  = VGA_BASE + 6
VGA_FAIL_M  = VGA_BASE + 7
VGA_FAIL_H  = VGA_BASE + 8
VGA_FAIL_EXP = VGA_BASE + 9
VGA_FAIL_ACT = VGA_BASE + 10
VGA_DIAG_STATE = VGA_BASE + 11
VGA_DBG_LAST_ADDR = VGA_BASE + 12
VGA_DBG_LAST_DATA = VGA_BASE + 13
VGA_DBG_WR_COUNT  = VGA_BASE + 14

VIA1_BASE   = $CC00
VIA1_T1C_H  = VIA1_BASE + 5
VIA1_IFR    = VIA1_BASE + 13
VIA1_IER    = VIA1_BASE + 14

STATUS_WRITE_PENDING = $80
STATUS_READ_PENDING  = $40
STATUS_CLEAR_ACTIVE  = $20
STATUS_DIAG_BUSY     = $10
STATUS_DIAG_DONE     = $08
STATUS_DIAG_ERROR    = $04

font_ptr = $20
text_ptr = $22

.org $3100

start:
	SEI
	JSR disable_nmi_timer
	LDA #<msg_start
	LDX #>msg_start
	JSR ROM_PRINTNL

	LDA #<msg_blind_mode
	LDX #>msg_blind_mode
	JSR ROM_PRINTNL
	LDA #<msg_wait_diag
	LDX #>msg_wait_diag
	JSR ROM_PRINTNL
	JSR delay_long
	LDA #<msg_diag_skip
	LDX #>msg_diag_skip
	JSR ROM_PRINTNL

	LDA #<msg_clear
	LDX #>msg_clear
	JSR ROM_PRINTNL
	LDA #$01                ; debug overlay on, do not start SRAM clear in blind mode
	STA VGA_STATUS
	JSR delay_long

	LDA #<msg_palette
	LDX #>msg_palette
	JSR ROM_PRINTNL
	JSR init_palette
	LDA #<msg_palette_done
	LDX #>msg_palette_done
	JSR ROM_PRINTNL

	LDA #<msg_first_bitmap
	LDX #>msg_first_bitmap
	JSR ROM_PRINTNL
	LDA #<msg_first_setaddr
	LDX #>msg_first_setaddr
	JSR ROM_PRINTNL
	JSR set_addr_00000
	LDA #<msg_first_addr_done
	LDX #>msg_first_addr_done
	JSR ROM_PRINTNL
	LDA #<msg_first_data_write
	LDX #>msg_first_data_write
	JSR ROM_PRINTNL
	LDA #$0F
	STA VGA_DATA
	LDA #<msg_first_data_done
	LDX #>msg_first_data_done
	JSR ROM_PRINTNL
	JSR delay_local
	LDA #<msg_first_write_ok
	LDX #>msg_first_write_ok
	JSR ROM_PRINTNL

	LDA #<msg_bitmap
	LDX #>msg_bitmap
	JSR ROM_PRINTNL
	LDA #$01
	JSR write_vga_sram_marked
	LDA #$02
	JSR write_vga_sram_marked
	LDA #$03
	JSR write_vga_sram_marked
	LDA #$04
	JSR write_vga_sram_marked
	LDA #$05
	JSR write_vga_sram_marked
	LDA #$06
	JSR write_vga_sram_marked
	LDA #$07
	JSR write_vga_sram_marked
	LDA #$08
	JSR write_vga_sram_marked
	LDA #<msg_bitmap_done
	LDX #>msg_bitmap_done
	JSR ROM_PRINTNL

	LDA #$01                ; bitmap mode, palette 0, splash off
	STA VGA_CTRL
	JSR delay_long
	JSR restore_nmi_timer
	CLI
	RTS

disable_nmi_timer:
	LDA #$40                ; IER bit7=0 clears Timer1 enable
	STA VIA1_IER
	STA VIA1_IFR            ; clear pending Timer1 flag
	RTS

restore_nmi_timer:
	LDA #$4D
	STA VIA1_T1C_H
	LDA #$C0                ; IER bit7=1 enables Timer1
	STA VIA1_IER
	RTS

set_addr_00000:
	LDA #$00
	STA VGA_ADDR_L
	STA VGA_ADDR_M
	LDA #$10                ; step 1, addr[18:16] = 0
	STA VGA_ADDR_H
	RTS

set_addr_font:
	LDA #$00
	STA VGA_ADDR_L
	LDA #$30
	STA VGA_ADDR_M
	LDA #$10                ; $03000, step 1
	STA VGA_ADDR_H
	RTS

set_addr_palette:
	LDA #$00
	STA VGA_ADDR_L
	LDA #$F0
	STA VGA_ADDR_M
	LDA #$11                ; $1F000, step 1
	STA VGA_ADDR_H
	RTS

set_addr_page:
	LDA #$00
	STA VGA_ADDR_L
	LDA page_index
	STA VGA_ADDR_M
	LDA page_index+1
	AND #$07
	ORA #$10                ; step 1, addr[18:16] from page_index high bits
	STA VGA_ADDR_H
	RTS

write_vga_palette:
	JSR delay_long
	STA VGA_DATA
	JSR delay_long
	RTS

write_vga_sram:
	STA VGA_DATA
	JSR delay_long
	RTS

write_vga_sram_marked:
	PHA
	LDA #'D'
	JSR ROM_PUTC
	PLA
	JSR write_vga_sram
	LDA #'d'
	JSR ROM_PUTC
	RTS

delay_local:
	LDX #$FF
delay_local_loop:
	DEX
	BNE delay_local_loop
	RTS

delay_long:
	LDY #$40
delay_long_outer:
	JSR delay_local
	DEY
	BNE delay_long_outer
	RTS

wait_status_clear:
	STA wait_mask
	LDA #$FF
	STA timeout_lo
	STA timeout_hi
wait_status_loop:
	LDA VGA_STATUS
	AND wait_mask
	BEQ wait_status_ok
	DEC timeout_lo
	BNE wait_status_loop
	DEC timeout_hi
	BNE wait_status_loop
	SEC
	RTS
wait_status_ok:
	CLC
	RTS

wait_status_set:
	STA wait_mask
	LDA #$FF
	STA timeout_lo
	STA timeout_hi
wait_status_set_loop:
	LDA VGA_STATUS
	AND wait_mask
	BNE wait_status_set_ok
	DEC timeout_lo
	BNE wait_status_set_loop
	DEC timeout_hi
	BNE wait_status_set_loop
	SEC
	RTS
wait_status_set_ok:
	CLC
	RTS

init_palette:
	LDA #<msg_palette_setaddr
	LDX #>msg_palette_setaddr
	JSR ROM_PRINTNL
	JSR set_addr_palette
	LDA #<msg_palette_addr_done
	LDX #>msg_palette_addr_done
	JSR ROM_PRINTNL
	LDA #<msg_palette_slow_write
	LDX #>msg_palette_slow_write
	JSR ROM_PRINTNL
	LDA #$00
	STA pal_index
palette_slow_loop:
	LDA #'>'
	JSR ROM_PUTC
	LDY pal_index
	LDA palette_rgb444,Y
	JSR write_vga_palette
	LDA #'<'
	JSR ROM_PUTC
	JSR delay_long
	INC pal_index
	LDA pal_index
	CMP #palette_rgb444_end - palette_rgb444
	BNE palette_slow_loop
	JSR ROM_PUTNL
	RTS

palette_zero_test:
	JSR set_addr_palette
	LDA #<msg_palette_zero
	LDX #>msg_palette_zero
	JSR ROM_PRINTNL
	LDA #$00
	STA VGA_DATA
	JSR delay_local
	LDA #<msg_palette_zero_ok
	LDX #>msg_palette_zero_ok
	JSR ROM_PRINTNL
	RTS

init_palette_trace:
	JSR set_addr_palette
	LDA #$00
	STA pal_index
palette_trace_loop:
	LDA #'P'
	JSR ROM_PUTC
	LDA pal_index
	JSR ROM_PRTBYTE
	LDA #'='
	JSR ROM_PUTC
	LDY pal_index
	LDA palette_rgb444,Y
	JSR ROM_PRTBYTE
	JSR ROM_PUTNL
	LDY pal_index
	LDA palette_rgb444,Y
	JSR write_vga_palette
	INC pal_index
	LDA pal_index
	CMP #palette_rgb444_end - palette_rgb444
	BNE palette_trace_loop
	RTS

first_bitmap_byte_test:
	LDA #<msg_first_setaddr
	LDX #>msg_first_setaddr
	JSR ROM_PRINTNL
	JSR set_addr_00000
	LDA #<msg_first_addr_done
	LDX #>msg_first_addr_done
	JSR ROM_PRINTNL
	LDA #$0F
	LDA #<msg_first_data_write
	LDX #>msg_first_data_write
	JSR ROM_PRINTNL
	LDA #$0F
	STA VGA_DATA
	LDA #<msg_first_data_done
	LDX #>msg_first_data_done
	JSR ROM_PRINTNL
	JSR delay_local
first_bitmap_done:
	CLC
	RTS

draw_bitmap:
	LDA #$01                ; diagnostic: 1 block * 8 B = 8 B
	STA pages_left
	LDA #$00
	STA page_index
	LDA #$01
	STA color_value
draw_bitmap_block_loop:
	LDA #'A'
	JSR ROM_PUTC
	LDA page_index
	STA VGA_ADDR_L
	LDA #$00
	STA VGA_ADDR_M
	LDA #$10                ; step 1, addr[18:16] = 0
	STA VGA_ADDR_H
	LDA #'a'
	JSR ROM_PUTC
	LDA #$08
	STA bytes_left
draw_bitmap_byte_loop:
	LDA #'D'
	JSR ROM_PUTC
	LDA color_value
	JSR write_vga_sram
	LDA #'d'
	JSR ROM_PUTC
	INC color_value
	LDA color_value
	AND #$0F
	BNE draw_bitmap_color_ok
	LDA #$01
	STA color_value
draw_bitmap_color_ok:
	DEC bytes_left
	BNE draw_bitmap_byte_loop
	JSR delay_long
	LDA page_index
	CLC
	ADC #$10
	STA page_index
	DEC pages_left
	BNE draw_bitmap_block_loop
	RTS

sram_rw_test:
	LDA #<msg_sram_probe
	LDX #>msg_sram_probe
	JSR ROM_PRINTNL
	JSR set_addr_00000
	LDA #$5A
	JSR write_vga_sram
	LDA #<msg_probe_status
	LDX #>msg_probe_status
	JSR ROM_PUTS
	LDA VGA_STATUS
	JSR ROM_PRTBYTE
	JSR ROM_PUTNL
	RTS

print_status_initial:
	LDA #<msg_status_initial
	LDX #>msg_status_initial
	JMP print_status
print_status_diag:
	LDA #<msg_status_diag
	LDX #>msg_status_diag
	JMP print_status
print_status_clear:
	LDA #<msg_status_clear
	LDX #>msg_status_clear
	JMP print_status
print_status_palette:
	LDA #<msg_status_palette
	LDX #>msg_status_palette
	JMP print_status
print_status_font:
	LDA #<msg_status_font
	LDX #>msg_status_font
	JMP print_status
print_status_bitmap:
	LDA #<msg_status_bitmap
	LDX #>msg_status_bitmap
	JMP print_status
print_status_bitmap_first:
	LDA #<msg_status_bitmap_first
	LDX #>msg_status_bitmap_first
	JMP print_status
print_status_final:
	LDA #<msg_status_final
	LDX #>msg_status_final
print_status:
	JSR ROM_PUTS
	LDA VGA_STATUS
	JSR ROM_PRTBYTE
	JSR ROM_PUTNL
	RTS

print_ctrl_after_mode:
	LDA #<msg_ctrl_after_mode
	LDX #>msg_ctrl_after_mode
	JSR ROM_PUTS
	LDA VGA_CTRL
	JSR ROM_PRTBYTE
	JSR ROM_PUTNL
	RTS

print_debug_write_regs:
	LDA #<msg_dbg_write
	LDX #>msg_dbg_write
	JSR ROM_PUTS
	LDA VGA_DBG_LAST_ADDR
	JSR ROM_PRTBYTE
	LDA #' '
	JSR ROM_PUTC
	LDA VGA_DBG_LAST_DATA
	JSR ROM_PRTBYTE
	LDA #' '
	JSR ROM_PUTC
	LDA VGA_DBG_WR_COUNT
	JSR ROM_PRTBYTE
	JSR ROM_PUTNL
	RTS

print_diag_fail:
	LDA #<msg_fail_addr
	LDX #>msg_fail_addr
	JSR ROM_PUTS
	LDA VGA_FAIL_H
	JSR ROM_PRTBYTE
	LDA VGA_FAIL_M
	JSR ROM_PRTBYTE
	LDA VGA_FAIL_L
	JSR ROM_PRTBYTE
	JSR ROM_PUTNL
	LDA #<msg_fail_exp
	LDX #>msg_fail_exp
	JSR ROM_PUTS
	LDA VGA_FAIL_EXP
	JSR ROM_PRTBYTE
	LDA #<msg_fail_act
	LDX #>msg_fail_act
	JSR ROM_PUTS
	LDA VGA_FAIL_ACT
	JSR ROM_PRTBYTE
	JSR ROM_PUTNL
	LDA #<msg_fail_state
	LDX #>msg_fail_state
	JSR ROM_PUTS
	LDA VGA_DIAG_STATE
	JSR ROM_PRTBYTE
	JSR ROM_PUTNL
	RTS

wait_mask:   .byte 0
timeout_lo:  .byte 0
timeout_hi:  .byte 0
bytes_left:  .word 0
pages_left:  .word 0
page_index:  .word 0
color_value: .byte 0
pal_index:   .byte 0

msg_start:          .byte "APRTS VGA test start, FPGA base $CF00", 0
msg_blind_mode:     .byte "Blind write-only run: no FPGA reads", 0
msg_wait_diag:      .byte "Waiting for FPGA SRAM diagnostic...", 0
msg_diag_skip:      .byte "Diagnostic wait elapsed", 0
msg_timeout_diag:   .byte "TIMEOUT: diagnostic busy bit stayed set", 0
msg_diag_error:     .byte "ERROR: FPGA SRAM diagnostic failed", 0
msg_diag_ok:        .byte "FPGA SRAM diagnostic OK", 0
msg_clear:          .byte "Requesting SRAM clear...", 0
msg_timeout_clear:  .byte "TIMEOUT: SRAM clear active bit stayed set", 0
msg_sram_probe:     .byte "Writing one SRAM probe byte at $00000", 0
msg_probe_status:   .byte "STATUS after SRAM probe=$", 0
msg_palette:        .byte "Uploading palette RAM", 0
msg_palette_done:   .byte "Palette probe done", 0
msg_palette_setaddr:.byte "Palette: set addr", 0
msg_palette_addr_done:.byte "Palette: addr done", 0
msg_palette_slow_write:.byte "Palette: slow write 16 colors", 0
msg_palette_low_write:.byte "Palette: write low", 0
msg_palette_low_done:.byte "Palette: low done", 0
msg_palette_high_write:.byte "Palette: write high", 0
msg_palette_high_done:.byte "Palette: high done", 0
msg_palette_zero:   .byte "Writing one palette zero byte", 0
msg_palette_zero_ok:.byte "One palette zero byte written", 0
msg_font:           .byte "Uploading 2 KB font to $03000", 0
msg_first_bitmap:   .byte "Writing first bitmap byte", 0
msg_first_setaddr:  .byte "First byte: set addr", 0
msg_first_addr_done:.byte "First byte: addr done", 0
msg_first_data_write:.byte "First byte: write DATA", 0
msg_first_data_done:.byte "First byte: DATA done", 0
msg_first_write_ok: .byte "First byte write-only path OK", 0
msg_timeout_write:  .byte "TIMEOUT: first SRAM write pending", 0
msg_bitmap_mode:    .byte "Switching to bitmap mode", 0
msg_ctrl_written:   .byte "CTRL write done", 0
msg_status_written: .byte "STATUS write done", 0
msg_bitmap:         .byte "Writing 8 B bitmap probe as slow bytes", 0
msg_bitmap_done:    .byte "Bitmap probe write done", 0
msg_done:           .byte "APRTS VGA test done, returning to shell", 0
msg_dbg_write:      .byte "DBG last/count=$", 0
msg_ctrl_after_mode:.byte "CTRL after bitmap mode=$", 0

msg_status_initial: .byte "STATUS initial=$", 0
msg_status_diag:    .byte "STATUS after diag=$", 0
msg_status_clear:   .byte "STATUS after clear=$", 0
msg_status_palette: .byte "STATUS after palette=$", 0
msg_status_font:    .byte "STATUS after font=$", 0
msg_status_bitmap_first: .byte "STATUS after first bitmap=$", 0
msg_status_bitmap:  .byte "STATUS after bitmap=$", 0
msg_status_final:   .byte "STATUS final=$", 0
msg_fail_addr:      .byte "FAIL addr=$", 0
msg_fail_exp:       .byte "FAIL expected=$", 0
msg_fail_act:       .byte " actual=$", 0
msg_fail_state:     .byte "FAIL state=$", 0

; 16 barev RGB444, kazda jako low byte a high nibble pro VGA palette RAM.
palette_rgb444:
	.byte $FF,$0F, $0A,$00, $A0,$00, $AA,$00
	.byte $00,$0A, $0A,$0A, $A0,$0A, $AA,$0A
	.byte $55,$05, $0F,$00, $F0,$00, $FF,$00
	.byte $00,$0F, $0F,$0F, $F0,$0F, $FF,$0F
palette_rgb444_end:

