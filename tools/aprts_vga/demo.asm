; demo.asm - test APRTS VGA FPGA pro AppartusOS
; FPGA registry jsou dekodovane od $CF00.
;
; Sestaveni:
;   build.bat
;
; Nacteni v AppartusOS:
;   LOAD              ; posli demo.hex pres serial
;   SAVE VGADEMO 3100 0496
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
	LDA #<msg_start
	LDX #>msg_start
	JSR ROM_PRINTNL

	JSR print_status_initial

	LDA #<msg_wait_diag
	LDX #>msg_wait_diag
	JSR ROM_PRINTNL
	LDA #STATUS_DIAG_BUSY
	JSR wait_status_clear
	BCC diag_ready
	LDA #<msg_timeout_diag
	LDX #>msg_timeout_diag
	JSR ROM_PRINTNL
	JSR print_status_final
	RTS

diag_ready:
	JSR print_status_diag
	LDA VGA_STATUS
	AND #STATUS_DIAG_ERROR
	BEQ diag_ok
	LDA #<msg_diag_error
	LDX #>msg_diag_error
	JSR ROM_PRINTNL
	JSR print_diag_fail
	RTS

diag_ok:
	LDA #<msg_diag_ok
	LDX #>msg_diag_ok
	JSR ROM_PRINTNL

	LDA #<msg_clear
	LDX #>msg_clear
	JSR ROM_PRINTNL
	LDA #$03                ; debug overlay on + SRAM clear request toggle
	STA VGA_STATUS
	LDA #$01                ; debug overlay on, clear request bit zpet na 0
	STA VGA_STATUS
	LDA #STATUS_CLEAR_ACTIVE
	JSR wait_status_set
	LDA #STATUS_CLEAR_ACTIVE
	JSR wait_status_clear
	BCC clear_done
	LDA #<msg_timeout_clear
	LDX #>msg_timeout_clear
	JSR ROM_PRINTNL
	JSR print_status_final
	RTS

clear_done:
	JSR print_status_clear

	LDA #<msg_palette
	LDX #>msg_palette
	JSR ROM_PRINTNL
	JSR init_palette
	JSR print_status_palette

	LDA #<msg_bitmap
	LDX #>msg_bitmap
	JSR ROM_PRINTNL
	JSR draw_bitmap
	JSR print_status_bitmap

	LDA #$01                ; bitmap mode, palette 0, splash off
	STA VGA_CTRL
	LDA #$01                ; automatic debug overlay on
	STA VGA_STATUS

	JSR print_status_final
	LDA #<msg_done
	LDX #>msg_done
	JSR ROM_PRINTNL
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

write_vga_palette:
	STA VGA_DATA
	JSR delay_local
	RTS

write_vga_sram:
	STA VGA_DATA
	JSR delay_local
	RTS

delay_local:
	LDX #$40
delay_local_loop:
	DEX
	BNE delay_local_loop
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
	JSR set_addr_palette
	LDY #$00
palette_loop:
	LDA palette_rgb444,Y
	JSR write_vga_palette
	INY
	CPY #palette_rgb444_end - palette_rgb444
	BNE palette_loop
	RTS

draw_bitmap:
	JSR set_addr_00000
	LDA #$00
	STA bytes_left
	LDA #$10                ; 4096 B bitmap block
	STA bytes_left+1
	LDA #$01
	STA color_value
draw_bitmap_loop:
	LDA color_value
	JSR write_vga_sram
	INC color_value
	LDA color_value
	AND #$0F
	BNE draw_bitmap_color_ok
	LDA #$01
	STA color_value
draw_bitmap_color_ok:
	DEC bytes_left
	BNE draw_bitmap_loop
	DEC bytes_left+1
	BNE draw_bitmap_loop
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
print_status_final:
	LDA #<msg_status_final
	LDX #>msg_status_final
print_status:
	JSR ROM_PUTS
	LDA VGA_STATUS
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
color_value: .byte 0

msg_start:          .byte "APRTS VGA test start, FPGA base $CF00", 0
msg_wait_diag:      .byte "Waiting for FPGA SRAM diagnostic...", 0
msg_timeout_diag:   .byte "TIMEOUT: diagnostic busy bit stayed set", 0
msg_diag_error:     .byte "ERROR: FPGA SRAM diagnostic failed", 0
msg_diag_ok:        .byte "FPGA SRAM diagnostic OK", 0
msg_clear:          .byte "Requesting SRAM clear...", 0
msg_timeout_clear:  .byte "TIMEOUT: SRAM clear active bit stayed set", 0
msg_sram_probe:     .byte "Writing one SRAM probe byte at $00000", 0
msg_probe_status:   .byte "STATUS after SRAM probe=$", 0
msg_palette:        .byte "Uploading palette RAM", 0
msg_font:           .byte "Uploading 2 KB font to $03000", 0
msg_bitmap:         .byte "Writing 4 KB bitmap block to VRAM", 0
msg_done:           .byte "APRTS VGA test done, returning to shell", 0

msg_status_initial: .byte "STATUS initial=$", 0
msg_status_diag:    .byte "STATUS after diag=$", 0
msg_status_clear:   .byte "STATUS after clear=$", 0
msg_status_palette: .byte "STATUS after palette=$", 0
msg_status_font:    .byte "STATUS after font=$", 0
msg_status_bitmap:  .byte "STATUS after bitmap=$", 0
msg_status_final:   .byte "STATUS final=$", 0
msg_fail_addr:      .byte "FAIL addr=$", 0
msg_fail_exp:       .byte "FAIL expected=$", 0
msg_fail_act:       .byte " actual=$", 0
msg_fail_state:     .byte "FAIL state=$", 0

; 16 barev RGB444, kazda jako low byte a high nibble pro VGA palette RAM.
palette_rgb444:
	.byte $00,$00, $0A,$00, $A0,$00, $AA,$00
	.byte $00,$0A, $0A,$0A, $A0,$0A, $AA,$0A
	.byte $55,$05, $0F,$00, $F0,$00, $FF,$00
	.byte $00,$0F, $0F,$0F, $F0,$0F, $FF,$0F
palette_rgb444_end:

