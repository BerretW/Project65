; appartus_shell.asm - AppartusOS interactive shell + kernel main
;
; Entry point: _os_main (called from main_appartus.c after HW init)
;
; Supported commands (case-insensitive input):
;   HELP / ?         - show command list
;   VER              - OS version
;   DIR              - list RAMDisk files
;   FREE             - show RAMDisk free space
;   FORMAT           - re-initialise RAMDisk (clears all files)
;   LOAD             - receive Intel HEX via ACIA to RAM
;   SAVE <n> <a> <s> - save $s bytes from address $a to RAMDisk as <n>
;   DEL  <name>      - delete file from RAMDisk
;   RUN  <name>      - run file from RAMDisk (program may RTS back)
;   MON              - enter EWOZ/WozMon monitor
;   RESET            - soft reset (jump to $FF00)
;
; Command-line syntax notes:
;   <name>  up to 8 alphanumeric chars, no spaces
;   <a>     4-digit hex address, e.g. 6090
;   <s>     4-digit hex size, e.g. 0100
;
; Example session:
;   > LOAD
;   (send intel hex file over serial)
;   > SAVE HELLO 6090 0100
;   > DIR
;   > RUN HELLO

.setcpu     "65C02"
.smart      on
.autoimport on
.case       on

.include "../io.inc65"

; Rozsah adres nahraných _ihex_load (sledování pro LSAVE)
ihex_minL  = $54
ihex_minH  = $55
ihex_maxL  = $56
ihex_maxH  = $57

.importzp   os_arg0, os_arg1, os_ptr
.importzp   rd_ptr, rd_idx, rd_tmp
.importzp   parse_idx, rd_src, rd_dst, rd_size_lo, rd_size_hi
.importzp   fd_tmp

; cc65 ZP imports (used by acia/utils)
.importzp   tmp1, ptr1

.export _os_main
.export _IRQ_Event, _NMI_Event
.import _basic_main

; ---------------------------------------------------------------------------
; BSS – OS buffers (in RAM, zeroed at startup by crt0)
; ---------------------------------------------------------------------------

.segment "BSS"

cmd_buf:    .res 64         ; raw input line
cmd_token:  .res 9          ; current parsed token (8 chars + NUL)
os_name:    .res 9          ; filename parsed from command line

.export cmd_token           ; needed by appartus_fileio TYPE/HEXD (autoimport)

; ---------------------------------------------------------------------------
; CODE
; ---------------------------------------------------------------------------

.segment "CODE"

; ---------------------------------------------------------------------------
; Interrupt event stubs (OS version – extend as needed)
; ---------------------------------------------------------------------------

_IRQ_Event:
_NMI_Event:
    RTS

; ---------------------------------------------------------------------------
; _os_main - OS entry point (never returns)
; ---------------------------------------------------------------------------

_os_main:
    ; Check RAMDisk – format if no valid signature found
    JSR _rd_check
    BCC @rd_ok
    LDA #<str_rd_fmt
    LDX #>str_rd_fmt
    JSR _acia_print_nl
    JSR _rd_init
@rd_ok:
    ; Banner
    LDA #<str_banner
    LDX #>str_banner
    JSR _acia_print_nl
    LDA #<str_sub
    LDX #>str_sub
    JSR _acia_print_nl
    JSR _acia_put_newline

; ---------------------------------------------------------------------------
; Main shell loop
; ---------------------------------------------------------------------------

_shell_loop:
    ; Print prompt
    LDA #<str_prompt
    LDX #>str_prompt
    JSR _acia_puts

    ; Read input line into cmd_buf
    JSR _getline

    ; Skip empty lines
    LDA cmd_buf
    BEQ _shell_loop

    ; Initialise parse index
    STZ parse_idx

    ; Get first token (command name) into cmd_token
    JSR _tok_next
    LDA cmd_token
    BEQ _shell_loop         ; blank line after trim

    ; --- Dispatch table (compare and branch) ---

    LDA #<cmd_token
    LDX #>cmd_token
    STA os_ptr
    STX os_ptr+1

    ; HELP / ?
    JSR _str_cmp_P
    .byte "HELP",0
    BNE @no_help
    JMP _cmd_help
@no_help:
    JSR _str_cmp_P
    .byte "?",0
    BNE @no_help2
    JMP _cmd_help
@no_help2:

    ; VER
    JSR _str_cmp_P
    .byte "VER",0
    BNE @no_ver
    JMP _cmd_ver
@no_ver:

    ; DIR
    JSR _str_cmp_P
    .byte "DIR",0
    BNE @no_dir
    JMP _cmd_dir
@no_dir:

    ; FREE
    JSR _str_cmp_P
    .byte "FREE",0
    BNE @no_free
    JMP _cmd_free
@no_free:

    ; FORMAT
    JSR _str_cmp_P
    .byte "FORMAT",0
    BNE @no_fmt
    JMP _cmd_format
@no_fmt:

    ; LOAD
    JSR _str_cmp_P
    .byte "LOAD",0
    BNE @no_load
    JMP _cmd_load
@no_load:

    ; SAVE
    JSR _str_cmp_P
    .byte "SAVE",0
    BNE @no_save
    JMP _cmd_save
@no_save:

    ; DEL
    JSR _str_cmp_P
    .byte "DEL",0
    BNE @no_del
    JMP _cmd_del
@no_del:

    ; RUN
    JSR _str_cmp_P
    .byte "RUN",0
    BNE @no_run
    JMP _cmd_run
@no_run:

    ; BASIC
    JSR _str_cmp_P
    .byte "BASIC",0
    BNE @no_basic
    JMP _cmd_basic
@no_basic:

    ; RESET
    JSR _str_cmp_P
    .byte "RESET",0
    BNE @no_reset
    JMP _cmd_reset
@no_reset:

    ; TYPE
    JSR _str_cmp_P
    .byte "TYPE",0
    BNE @no_type
    JMP _cmd_type
@no_type:

    ; LSAVE
    JSR _str_cmp_P
    .byte "LSAVE",0
    BNE @no_lsave
    JMP _cmd_lsave
@no_lsave:

    ; Unknown command
    LDA #<str_unknown
    LDX #>str_unknown
    JSR _acia_puts
    LDA #<cmd_token
    LDX #>cmd_token
    JSR _acia_print_nl
    JMP _shell_loop

; ---------------------------------------------------------------------------
; Command handlers
; ---------------------------------------------------------------------------

_cmd_help:
    LDA #<str_help
    LDX #>str_help
    JSR _acia_puts
    JMP _shell_loop

_cmd_ver:
    LDA #<str_version
    LDX #>str_version
    JSR _acia_print_nl
    JMP _shell_loop

_cmd_dir:
    JSR _rd_list
    JMP _shell_loop

_cmd_free:
    JSR _rd_free
    JMP _shell_loop

_cmd_format:
    LDA #<str_fmt_confirm
    LDX #>str_fmt_confirm
    JSR _acia_puts
    JSR _acia_getc
    JSR _acia_put_newline
    CMP #'Y'
    BEQ @do_fmt
    CMP #'y'
    BNE @cancel
@do_fmt:
    JSR _rd_init
    LDA #<str_fmt_done
    LDX #>str_fmt_done
    JSR _acia_print_nl
    JMP _shell_loop
@cancel:
    LDA #<str_cancelled
    LDX #>str_cancelled
    JSR _acia_print_nl
    JMP _shell_loop

_cmd_load:
    LDA #<str_load_wait
    LDX #>str_load_wait
    JSR _acia_print_nl
    JSR _ihex_load
    CMP #0
    BEQ @ok
    CMP #$FF
    BEQ @esc
    LDA #<str_load_warn
    LDX #>str_load_warn
    JSR _acia_print_nl
    JMP _shell_loop
@esc:
    LDA #<str_cancelled
    LDX #>str_cancelled
    JSR _acia_print_nl
    JMP _shell_loop
@ok:
    LDA #<str_load_ok
    LDX #>str_load_ok
    JSR _acia_print_nl
    JMP _shell_loop

_cmd_save:
    ; SAVE <name> <addr> <size>
    ; Token: name (up to 8 chars)
    JSR _tok_next
    LDA cmd_token
    BEQ @bad_args
    ; Copy name to os_name
    LDA #<cmd_token
    LDX #>cmd_token
    JSR _strcpy_to_osname
    ; Token: address (4 hex digits)
    JSR _tok_next
    LDA cmd_token
    BEQ @bad_args
    JSR _parse_hex4
    BCS @bad_args
    STA os_arg0             ; load addr lo
    STX os_arg1             ; load addr hi
    STA rd_src              ; also source addr (program sits at its load addr)
    STX rd_src+1
    ; Token: size (4 hex digits)
    JSR _tok_next
    LDA cmd_token
    BEQ @bad_args
    JSR _parse_hex4
    BCS @bad_args
    STA rd_size_lo
    STX rd_size_hi
    ; Set up os_ptr → os_name
    LDA #<os_name
    LDX #>os_name
    STA os_ptr
    STX os_ptr+1
    ; flags: check if name begins with a letter for RUN flag heuristic
    ; (user can always run any file; mark all saved as RUN for simplicity)
    LDA #RDF_RUN
    STA rd_tmp
    ; Call _rd_save
    JSR _rd_save
    BCS @save_err
    LDA #<str_save_ok
    LDX #>str_save_ok
    JSR _acia_print_nl
    JMP _shell_loop
@bad_args:
    LDA #<str_bad_args
    LDX #>str_bad_args
    JSR _acia_print_nl
    JMP _shell_loop
@save_err:
    LDA #<str_save_err
    LDX #>str_save_err
    JSR _acia_print_nl
    JMP _shell_loop

_cmd_del:
    ; DEL <name>
    JSR _tok_next
    LDA cmd_token
    BEQ @bad
    ; Find file
    LDA #<cmd_token
    LDX #>cmd_token
    STA os_ptr
    STX os_ptr+1
    JSR _rd_find
    BCS @notfound
    JSR _rd_del
    BCS @bad
    LDA #<str_del_ok
    LDX #>str_del_ok
    JSR _acia_print_nl
    JMP _shell_loop
@notfound:
    LDA #<str_notfound
    LDX #>str_notfound
    JSR _acia_print_nl
    JMP _shell_loop
@bad:
    LDA #<str_bad_args
    LDX #>str_bad_args
    JSR _acia_print_nl
    JMP _shell_loop

_cmd_run:
    ; RUN <name>
    JSR _tok_next
    LDA cmd_token
    BEQ @bad
    LDA #<cmd_token
    LDX #>cmd_token
    STA os_ptr
    STX os_ptr+1
    JSR _rd_find
    BCS @notfound
    ; rd_idx now has entry index
    JSR _rd_run
    BCS @run_err
    LDA #<str_prog_ret
    LDX #>str_prog_ret
    JSR _acia_print_nl
    JMP _shell_loop
@notfound:
    LDA #<str_notfound
    LDX #>str_notfound
    JSR _acia_print_nl
    JMP _shell_loop
@run_err:
    LDA #<str_run_err
    LDX #>str_run_err
    JSR _acia_print_nl
    JMP _shell_loop
@bad:
    LDA #<str_bad_args
    LDX #>str_bad_args
    JSR _acia_print_nl
    JMP _shell_loop

_cmd_basic:
    JSR _basic_main
    JMP _shell_loop

_cmd_reset:
    JMP _RST

; ---------------------------------------------------------------------------
; _cmd_type — TYPE <name>
;
; Opens a file or device by name and prints its content to the ACIA.
; For file FDs: stops at EOF.
; For device FDs: stops when ESC ($1B) is received (useful with CON).
; ---------------------------------------------------------------------------

_cmd_type:
    JSR _tok_next               ; parse filename into cmd_token
    LDA cmd_token
    BEQ @bad_args_t
    LDA #<cmd_token
    LDX #>cmd_token
    JSR _fopen                  ; A=fd or $FF, C=1 error
    BCS @notfound_t
    TAX                         ; fd into X
    STX fd_tmp                  ; save fd for the loop
@type_loop:
    LDX fd_tmp
    JSR _fgetc                  ; A=byte, C=1 EOF/error
    BCS @type_eof
    CMP #$1B                    ; ESC aborts (useful for device FDs)
    BEQ @type_eof
    JSR _acia_putc
    BRA @type_loop
@type_eof:
    LDX fd_tmp
    JSR _fclose
    JSR _acia_put_newline
    JMP _shell_loop
@notfound_t:
    LDA #<str_notfound
    LDX #>str_notfound
    JSR _acia_print_nl
    JMP _shell_loop
@bad_args_t:
    LDA #<str_bad_args
    LDX #>str_bad_args
    JSR _acia_print_nl
    JMP _shell_loop

; ---------------------------------------------------------------------------
; _cmd_lsave — LSAVE <name>
;
; Přijme Intel HEX přes ACIA a uloží přijatá data rovnou do RAMDisku.
; Rozsah adres (zdroj + load adresa + velikost) se odvodí automaticky
; z min/max adres zapsaných loaderem (ihex_minH:L .. ihex_maxH:L).
;
; Syntax:  LSAVE <name>   (jméno max 8 znaků)
; ---------------------------------------------------------------------------

_cmd_lsave:
    ; Parsuj jméno souboru
    JSR _tok_next
    LDA cmd_token
    BEQ @ls_done            ; žádné jméno → ignoruj
    JSR _strcpy_to_osname
    ; Načti HEX
    JSR _ihex_load
    CMP #$FF
    BEQ @ls_done            ; ESC → tiše návrat
    ; Zkontroluj, zda min < max (máme data)
    LDA ihex_maxH
    CMP ihex_minH
    BCC @ls_done
    BNE @ls_save
    LDA ihex_maxL
    CMP ihex_minL
    BCC @ls_done
    BEQ @ls_done
@ls_save:
    LDA ihex_minL
    STA rd_src
    STA os_arg0
    LDA ihex_minH
    STA rd_src+1
    STA os_arg1
    LDA ihex_maxL
    SEC
    SBC ihex_minL
    STA rd_size_lo
    LDA ihex_maxH
    SBC ihex_minH
    STA rd_size_hi
    LDA #<os_name
    LDX #>os_name
    STA os_ptr
    STX os_ptr+1
    LDA #RDF_RUN
    STA rd_tmp
    JSR _rd_save
    BCS @ls_done
    LDA #<str_save_ok
    LDX #>str_save_ok
    JSR _acia_print_nl
@ls_done:
    JMP _shell_loop

; ---------------------------------------------------------------------------
; _getline - Read one line from ACIA into cmd_buf (max 63 chars)
; Echo characters, handle backspace/DEL.
; Converts lowercase to uppercase.
; Null-terminates result.  Modifies A, X, Y.
; ---------------------------------------------------------------------------

_getline:
    LDY #0
@loop:
    JSR _acia_getc
    CMP #$0D                ; CR = end of line
    BEQ @done
    CMP #$0A                ; LF = ignore
    BEQ @loop
    CMP #$7F                ; DEL = backspace
    BEQ @backspace
    CMP #$08                ; BS
    BEQ @backspace
    CPY #63                 ; buffer full?
    BEQ @loop
    ; Convert to uppercase
    CMP #'a'
    BCC @store
    CMP #'z'+1
    BCS @store
    AND #$DF
@store:
    STA cmd_buf,Y
    JSR _acia_putc
    INY
    BRA @loop
@backspace:
    CPY #0
    BEQ @loop
    DEY
    LDA #$08
    JSR _acia_putc
    LDA #' '
    JSR _acia_putc
    LDA #$08
    JSR _acia_putc
    BRA @loop
@done:
    LDA #0
    STA cmd_buf,Y           ; null terminate
    JSR _acia_put_newline
    RTS

; ---------------------------------------------------------------------------
; _tok_next - Extract next whitespace-delimited token from cmd_buf
; Uses/advances parse_idx.
; Result placed in cmd_token (up to 8 chars + NUL).
; If no more tokens, cmd_token[0] = 0.
; Modifies A, X, Y.
; ---------------------------------------------------------------------------

_tok_next:
    LDX parse_idx
    ; Skip leading spaces
@skip_sp:
    LDA cmd_buf,X
    BEQ @empty
    CMP #' '
    BNE @copy
    INX
    BRA @skip_sp
@empty:
    STX parse_idx
    STZ cmd_token
    RTS
@copy:
    LDY #0
@copy_loop:
    LDA cmd_buf,X
    BEQ @end_tok
    CMP #' '
    BEQ @end_tok
    CPY #8                  ; token too long → truncate (entry will not match)
    BEQ @skip_rest
    STA cmd_token,Y
    INY
    INX
    BRA @copy_loop
@skip_rest:
    INX
    LDA cmd_buf,X
    BEQ @end_tok
    CMP #' '
    BNE @skip_rest
@end_tok:
    LDA #0
    STA cmd_token,Y         ; null terminate
    STX parse_idx
    RTS

; ---------------------------------------------------------------------------
; _parse_hex4 - Parse 4-character hex string in cmd_token → 16-bit value
; Output: A = lo byte, X = hi byte
; C=0 OK, C=1 parse error (non-hex character found)
; Modifies A, X, Y, tmp1.
; ---------------------------------------------------------------------------

_parse_hex4:
    LDY #0
    LDA #0
    STA tmp1                ; accumulator lo
    STA tmp1+1              ; not used, use os_arg0/1 temporarly
    LDY #0
    LDA #0
    STA os_arg0             ; result lo
    STA os_arg1             ; result hi (temporary)
@loop:
    CPY #4
    BEQ @done
    LDA cmd_token,Y
    BEQ @done               ; early null = ok if we got some digits
    JSR _hex_nib
    BCS @err
    ; shift result left 4 bits and OR in nibble
    ; result = result << 4 | nibble
    ; current result in os_arg1:os_arg0 (big endian for shift)
    ASL os_arg0
    ROL os_arg1
    ASL os_arg0
    ROL os_arg1
    ASL os_arg0
    ROL os_arg1
    ASL os_arg0
    ROL os_arg1
    ORA os_arg0
    STA os_arg0
    INY
    BRA @loop
@done:
    LDA os_arg0
    LDX os_arg1
    CLC
    RTS
@err:
    SEC
    RTS

; ---------------------------------------------------------------------------
; _hex_nib - Convert ASCII hex char in A to value 0-15
; C=0 OK (value in A), C=1 not a hex char
; ---------------------------------------------------------------------------

_hex_nib:
    CMP #'0'
    BCC @bad
    CMP #'9'+1
    BCC @digit
    CMP #'A'
    BCC @bad
    CMP #'F'+1
    BCC @upper
    CMP #'a'
    BCC @bad
    CMP #'f'+1
    BCS @bad
    SEC
    SBC #'a' - 10
    CLC
    RTS
@upper:
    SEC
    SBC #'A' - 10
    CLC
    RTS
@digit:
    SEC
    SBC #'0'
    CLC
    RTS
@bad:
    SEC
    RTS

; ---------------------------------------------------------------------------
; _str_cmp_P - Compare (os_ptr) string with inline literal after JSR
; Call:  JSR _str_cmp_P
;        .byte "STRING",0
; Sets Z=1 if strings equal, Z=0 if not.
; Returns to byte after null terminator of inline string.
; Modifies A, Y; preserves X.
; ---------------------------------------------------------------------------

_str_cmp_P:
    ; Return address on stack points to the inline literal
    PLA
    STA rd_dst              ; lo of return addr (pointing to byte before literal)
    PLA
    STA rd_dst+1            ; hi
    ; rd_dst+1 now points to JSR target-1; actual literal is at rd_dst+1
    INC rd_dst
    BNE @go
    INC rd_dst+1
@go:
    LDY #0
@loop:
    LDA (os_ptr),Y          ; char from token
    STA rd_tmp              ; save
    LDA (rd_dst),Y          ; char from inline literal
    BEQ @lit_end
    CMP rd_tmp
    BNE @no_match
    INY
    BRA @loop
@lit_end:
    ; literal ended; match only if token also ended
    LDA (os_ptr),Y
    BNE @no_match
    ; Advance rd_dst past null (Y bytes + null)
    TYA
    CLC
    ADC rd_dst
    STA rd_dst
    BCC @push
    INC rd_dst+1
@push:
    INC rd_dst              ; skip null byte itself
    BNE @push2
    INC rd_dst+1
@push2:
    ; Push updated return address - 1 (as JSR convention)
    LDA rd_dst+1
    PHA
    LDA rd_dst
    SEC
    SBC #1
    PHA
    LDA #0                  ; Z=1 → equal
    RTS                     ; return past the literal

@no_match:
    ; Skip to end of literal
@skip:
    LDA (rd_dst),Y
    BEQ @skip_done
    INY
    BRA @skip
@skip_done:
    ; Advance rd_dst past literal + null
    TYA
    CLC
    ADC rd_dst
    STA rd_dst
    BCC @skip2
    INC rd_dst+1
@skip2:
    INC rd_dst
    BNE @skip3
    INC rd_dst+1
@skip3:
    ; Push updated return address - 1
    LDA rd_dst+1
    PHA
    LDA rd_dst
    SEC
    SBC #1
    PHA
    LDA #1                  ; Z=0 → not equal
    RTS

; ---------------------------------------------------------------------------
; _strcpy_to_osname - Copy cmd_token to os_name (up to 8 chars + NUL)
; Modifies A, Y.
; ---------------------------------------------------------------------------

_strcpy_to_osname:
    LDY #0
@loop:
    LDA cmd_token,Y
    STA os_name,Y
    BEQ @done
    INY
    CPY #8
    BNE @loop
    LDA #0
    STA os_name,Y
@done:
    RTS

; ---------------------------------------------------------------------------
; Strings (RODATA)
; ---------------------------------------------------------------------------

.segment "RODATA"

; Define RDF_RUN here for the SAVE command handler
RDF_RUN = $02

str_banner:
    .byte "AppartusOS v1.2",0
str_sub:
    .byte "HELP for help.",0
str_prompt:
    .byte "> ",0
str_version:
    .byte "AppartusOS v1.2 2026",0
str_rd_fmt:
    .byte "RAMDisk init...",0
str_help:
    .byte "HELP VER DIR FREE FORMAT LOAD LSAVE",13,10
    .byte "SAVE DEL RUN TYPE BASIC RESET",13,10
    .byte "SAVE <n> <a> <sz>  LSAVE <n>",13,10,0
str_fmt_confirm:
    .byte "Format? ALL LOST. (Y/N): ",0
str_fmt_done:
    .byte "Fmated.",0
str_cancelled:
    .byte "Cancel.",0
str_load_wait:
    .byte "Send Intel HEX (ESC=abort)...",0
str_load_ok:
    .byte "HEX OK.",0
str_load_warn:
    .byte "?HEX chksum.",0
str_save_ok:
    .byte "Saved.",0
str_save_err:
    .byte "?RAMDisk full or bad args.",0
str_del_ok:
    .byte "Deleted.",0
str_notfound:
    .byte "Not found.",0
str_run_err:
    .byte "?Run error.",0
str_prog_ret:
    .byte "Done.",0
str_bad_args:
    .byte "?Args.",0
str_unknown:
    .byte "?Cmd: ",0
