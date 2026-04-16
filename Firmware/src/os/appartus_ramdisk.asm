; appartus_ramdisk.asm - AppartusOS RAMDisk filesystem
;
; Physical layout ($6000-$BFFF = 24 KB):
;   IC6 upper half ($6000-$7FFF) + full IC7 ($8000-$BFFF)
;
;   $6000-$600F   Header (16 bytes)
;     +0  "APOS"  signature (4 bytes)
;     +4  num_files (1 byte, 0-16)
;     +5  free_ptr lo (absolute addr of next free data byte)
;     +6  free_ptr hi
;     +7  reserved (9 bytes)
;
;   $6010-$610F   Directory (16 entries x 16 bytes = 256 bytes)
;     Each entry:
;     +0  name[8]     filename, null-padded (up to 8 chars)
;     +8  load_lo     program run/load address lo
;     +9  load_hi     program run/load address hi
;     +10 size_lo     data size lo
;     +11 size_hi     data size hi
;     +12 flags       bit0=VALID, bit1=RUNNABLE
;     +13 stor_lo     storage address inside RAMDisk lo
;     +14 stor_hi     storage address inside RAMDisk hi
;     +15 reserved
;
;   $6110-$BFFF   File data area (~24 KB, $5EF0 bytes)
;
; Exported routines:
;   _rd_init    - Format/initialise RAMDisk
;   _rd_check   - Check signature; C=0 valid, C=1 invalid
;   _rd_find    - Find file by name in os_ptr; C=0 found (rd_idx), C=1 not found
;   _rd_list    - Print directory listing to ACIA
;   _rd_save    - Save RAM region to RAMDisk
;   _rd_del     - Delete entry by rd_idx
;   _rd_run     - Copy+run file by rd_idx
;   _rd_free    - Print free/total space to ACIA

.setcpu     "65C02"
.smart      on
.autoimport on
.case       on

.include "../io.inc65"

.importzp   os_arg0, os_arg1, os_ptr
.importzp   rd_ptr, rd_idx, rd_tmp
.importzp   rd_src, rd_dst, rd_size_lo, rd_size_hi

.export _rd_init, _rd_check, _rd_find
.export _rd_list, _rd_save, _rd_del, _rd_run, _rd_free
.export _rd_memcpy

; ---------------------------------------------------------------------------
; RAMDisk constants
; ---------------------------------------------------------------------------

RD_MAX_FILES = 16                   ; 16 souborů — rozšíření díky IC7
RD_DIR_ENT   = 16                   ; bytes per dir entry
RD_NAME_LEN  = 8

; RAMDisk end: překrývá IC6 horní ($6000-$7FFF) + celý IC7 ($8000-$BFFF)
RD_END_ADDR  = $BFFF

; Header field absolute addresses
RD_HDR       = RAMDISK_START        ; $6000
RD_NUM       = RAMDISK_START + 4    ; num_files byte
RD_FREE_LO   = RAMDISK_START + 5    ; free_ptr lo
RD_FREE_HI   = RAMDISK_START + 6    ; free_ptr hi
RD_DIR       = RAMDISK_START + $10  ; $6010 – directory start (16 × 16 = 256 B)
RD_DATA      = RAMDISK_START + $110 ; $6110 – file data area start

; Dir entry field offsets (relative to entry base)
RDE_NAME     = 0
RDE_LOAD_LO  = 8
RDE_LOAD_HI  = 9
RDE_SIZE_LO  = 10
RDE_SIZE_HI  = 11
RDE_FLAGS    = 12
RDE_STOR_LO  = 13
RDE_STOR_HI  = 14

; Flag bits
RDF_VALID    = $01
RDF_RUN      = $02

.segment "CODE"

; ---------------------------------------------------------------------------
; _rd_ptr_from_idx - helper: set rd_ptr = &RD_DIR[rd_idx]
; Modifies A only.
; ---------------------------------------------------------------------------
_rd_ptr_from_idx:
    LDA rd_idx
    ASL
    ASL
    ASL
    ASL                 ; A = rd_idx * 16
    CLC
    ADC #<RD_DIR
    STA rd_ptr
    LDA #>RD_DIR
    ADC #0
    STA rd_ptr+1
    RTS

; ---------------------------------------------------------------------------
; _rd_init - Format the RAMDisk (write header, zero directory)
; Modifies: A, X
; ---------------------------------------------------------------------------
_rd_init:
    ; Write "APOS" signature
    LDA #'A'
    STA RD_HDR+0
    LDA #'P'
    STA RD_HDR+1
    LDA #'O'
    STA RD_HDR+2
    LDA #'S'
    STA RD_HDR+3
    ; num_files = 0
    STZ RD_NUM
    ; free_ptr = RD_DATA ($6110)
    LDA #<RD_DATA
    STA RD_FREE_LO
    LDA #>RD_DATA
    STA RD_FREE_HI
    ; Zero reserved header bytes
    LDA #0
    LDX #9
@clr_hdr:
    STA RD_HDR+7,X
    DEX
    BPL @clr_hdr
    ; Zero all directory entries (16 * 16 = 256 bytes, dva průchody po 128)
    LDX #127
@clr_dir_lo:
    STZ RD_DIR,X
    DEX
    BPL @clr_dir_lo
    LDX #127
@clr_dir_hi:
    STZ RD_DIR+128,X
    DEX
    BPL @clr_dir_hi
    RTS

; ---------------------------------------------------------------------------
; _rd_check - Verify RAMDisk signature
; Output: C=0 valid, C=1 invalid
; Modifies: A
; ---------------------------------------------------------------------------
_rd_check:
    LDA RD_HDR+0
    CMP #'A'
    BNE @bad
    LDA RD_HDR+1
    CMP #'P'
    BNE @bad
    LDA RD_HDR+2
    CMP #'O'
    BNE @bad
    LDA RD_HDR+3
    CMP #'S'
    BNE @bad
    CLC
    RTS
@bad:
    SEC
    RTS

; ---------------------------------------------------------------------------
; _rd_find - Find file by name
; Input:  os_ptr = pointer to null-terminated name (max 8 chars)
; Output: C=0 found (rd_idx = dir index), C=1 not found
; Modifies: A, X, Y, rd_ptr, rd_idx
; ---------------------------------------------------------------------------
_rd_find:
    LDA #0
    STA rd_idx
@scan:
    JSR _rd_ptr_from_idx
    ; Skip invalid entries
    LDY #RDE_FLAGS
    LDA (rd_ptr),Y
    AND #RDF_VALID
    BEQ @next
    ; Compare name bytes (Y = byte index 0..7)
    LDY #0
@cmp:
    LDA (os_ptr),Y          ; user name char
    BEQ @user_end           ; user name ended early
    CMP (rd_ptr),Y          ; compare with dir entry name
    BNE @next               ; mismatch
    INY
    CPY #RD_NAME_LEN
    BNE @cmp
    ; All 8 bytes matched
    CLC
    RTS
@user_end:
    ; user name shorter than 8: entry matches if entry[Y] is 0 too
    LDA (rd_ptr),Y
    BNE @next               ; entry has more chars = different name
    CLC
    RTS
@next:
    INC rd_idx
    LDA rd_idx
    CMP #RD_MAX_FILES
    BNE @scan
    SEC                     ; not found
    RTS

; ---------------------------------------------------------------------------
; _rd_list - Print directory listing to ACIA
; Modifies: A, X, Y, rd_ptr, rd_idx
; ---------------------------------------------------------------------------
_rd_list:
    LDA #<str_dir_hdr
    LDX #>str_dir_hdr
    JSR _acia_puts
    LDA #0
    STA rd_idx
    LDA #0
    STA rd_tmp              ; file count found
@loop:
    JSR _rd_ptr_from_idx
    LDY #RDE_FLAGS
    LDA (rd_ptr),Y
    AND #RDF_VALID
    BEQ @next
    INC rd_tmp
    ; Index digit
    LDA rd_idx
    CLC
    ADC #'0'
    JSR _acia_putc
    LDA #' '
    JSR _acia_putc
    ; Name (8 chars, space-padded)
    LDY #0
@pname:
    LDA (rd_ptr),Y
    BEQ @pad
    JSR _acia_putc
    INY
    CPY #RD_NAME_LEN
    BNE @pname
    BRA @after_name
@pad:
    LDA #' '
    JSR _acia_putc
    INY
    CPY #RD_NAME_LEN
    BNE @pad
@after_name:
    ; Space before size
    LDA #' '
    JSR _acia_putc
    ; Size in hex (4 digits big-endian)
    LDY #RDE_SIZE_HI
    LDA (rd_ptr),Y
    JSR _print_byte
    LDY #RDE_SIZE_LO
    LDA (rd_ptr),Y
    JSR _print_byte
    LDA #' '
    JSR _acia_putc
    ; Load address
    LDA #'@'
    JSR _acia_putc
    LDY #RDE_LOAD_HI
    LDA (rd_ptr),Y
    JSR _print_byte
    LDY #RDE_LOAD_LO
    LDA (rd_ptr),Y
    JSR _print_byte
    ; Runnable flag
    LDY #RDE_FLAGS
    LDA (rd_ptr),Y
    AND #RDF_RUN
    BEQ @not_run
    LDA #<str_run_flag
    LDX #>str_run_flag
    JSR _acia_puts
    BRA @endl
@not_run:
    LDA #<str_data_flag
    LDX #>str_data_flag
    JSR _acia_puts
@endl:
    JSR _acia_put_newline
@next:
    INC rd_idx
    LDA rd_idx
    CMP #RD_MAX_FILES
    BEQ @list_end
    JMP @loop
@list_end:
    ; Empty message
    LDA rd_tmp
    BNE @done
    LDA #<str_empty
    LDX #>str_empty
    JSR _acia_print_nl
@done:
    RTS

; ---------------------------------------------------------------------------
; _rd_save - Save RAM region to RAMDisk
; Input:  os_ptr    = pointer to filename (max 8 chars, null-terminated)
;         rd_src    = source address lo/hi (data to save)
;         rd_size_lo/hi = number of bytes to save
;         os_arg0   = load/run address lo (where program expects to run from)
;         os_arg1   = load/run address hi
;         rd_tmp    = flags (RDF_RUN if executable, 0 if data)
; Output: C=0 OK, C=1 error
; Modifies: A, X, Y, rd_ptr, rd_idx, rd_dst
; ---------------------------------------------------------------------------
_rd_save:
    ; RAMDisk must be valid
    JSR _rd_check
    BCC @chk_ok1
    JMP @err_fmt
@chk_ok1:
    ; Must not be full
    LDA RD_NUM
    CMP #RD_MAX_FILES
    BCC @chk_ok2
    JMP @err_full
@chk_ok2:
    ; Check size non-zero
    LDA rd_size_lo
    ORA rd_size_hi
    BNE @chk_ok3
    JMP @err_size
@chk_ok3:

    ; Find first free (invalid) slot
    LDA #0
    STA rd_idx
@find_free:
    JSR _rd_ptr_from_idx
    LDY #RDE_FLAGS
    LDA (rd_ptr),Y
    AND #RDF_VALID
    BEQ @got_slot
    INC rd_idx
    LDA rd_idx
    CMP #RD_MAX_FILES
    BNE @find_free
    BRA @err_full           ; no free slot (shouldn't happen if num_files < MAX)

@got_slot:
    ; rd_ptr → free dir entry
    ; Check that data fits in remaining RAMDisk space
    ; available = RD_END_ADDR+1 - free_ptr
    LDA RD_FREE_HI
    CMP #>RD_END_ADDR
    BCC @size_ok            ; free_ptr high < RD_END_ADDR high → definitely fits
    BNE @err_full           ; free_ptr high > RD_END_ADDR high → no space
    LDA RD_FREE_LO
    CMP #<(RD_END_ADDR+1)
    BCS @err_full           ; free_ptr lo >= RD_END_ADDR+1 lo → no space
@size_ok:

    ; Copy name into dir entry (8 bytes, null-pad remaining)
    LDY #0
@cpname:
    LDA (os_ptr),Y
    BEQ @pad_name
    STA (rd_ptr),Y
    INY
    CPY #RD_NAME_LEN
    BNE @cpname
    BRA @name_done
@pad_name:
    LDA #0
    STA (rd_ptr),Y
    INY
    CPY #RD_NAME_LEN
    BNE @pad_name
@name_done:

    ; Write load address
    LDY #RDE_LOAD_LO
    LDA os_arg0
    STA (rd_ptr),Y
    LDY #RDE_LOAD_HI
    LDA os_arg1
    STA (rd_ptr),Y

    ; Write size
    LDY #RDE_SIZE_LO
    LDA rd_size_lo
    STA (rd_ptr),Y
    LDY #RDE_SIZE_HI
    LDA rd_size_hi
    STA (rd_ptr),Y

    ; Write flags
    LDY #RDE_FLAGS
    LDA rd_tmp
    ORA #RDF_VALID
    STA (rd_ptr),Y

    ; Write storage address (current free_ptr)
    LDY #RDE_STOR_LO
    LDA RD_FREE_LO
    STA (rd_ptr),Y
    LDY #RDE_STOR_HI
    LDA RD_FREE_HI
    STA (rd_ptr),Y

    ; Copy data from rd_src to free area (rd_dst = free_ptr)
    LDA RD_FREE_LO
    STA rd_dst
    LDA RD_FREE_HI
    STA rd_dst+1
    JSR _rd_memcpy

    ; Advance free_ptr by size
    LDA RD_FREE_LO
    CLC
    ADC rd_size_lo
    STA RD_FREE_LO
    LDA RD_FREE_HI
    ADC rd_size_hi
    STA RD_FREE_HI

    ; Increment num_files
    INC RD_NUM

    CLC
    RTS

@err_fmt:
@err_size:
@err_full:
    SEC
    RTS

; ---------------------------------------------------------------------------
; _rd_del - Delete file by rd_idx (clear VALID flag)
; Input:  rd_idx = entry to delete
; Output: C=0 OK, C=1 invalid index or not valid
; Modifies: A, Y, rd_ptr
; ---------------------------------------------------------------------------
_rd_del:
    LDA rd_idx
    CMP #RD_MAX_FILES
    BCS @err
    JSR _rd_ptr_from_idx
    LDY #RDE_FLAGS
    LDA (rd_ptr),Y
    AND #RDF_VALID
    BEQ @err                ; already empty
    ; Clear all flags
    STZ rd_tmp
    LDA (rd_ptr),Y
    AND #<~RDF_VALID        ; clear VALID bit
    STA (rd_ptr),Y
    DEC RD_NUM
    CLC
    RTS
@err:
    SEC
    RTS

; ---------------------------------------------------------------------------
; _rd_run - Copy file to load address and execute it
; Input:  rd_idx = dir entry index
; The program is called with JSR-equivalent (can RTS back to OS).
; On return: C=0 program exited cleanly, C=1 entry invalid/not runnable
; Modifies: A, X, Y, rd_ptr, rd_src, rd_dst, rd_size_lo/hi, os_ptr
; ---------------------------------------------------------------------------
_rd_run:
    LDA rd_idx
    CMP #RD_MAX_FILES
    BCS @err
    JSR _rd_ptr_from_idx
    LDY #RDE_FLAGS
    LDA (rd_ptr),Y
    AND #RDF_VALID
    BEQ @err

    ; Get storage address → rd_src
    LDY #RDE_STOR_LO
    LDA (rd_ptr),Y
    STA rd_src
    LDY #RDE_STOR_HI
    LDA (rd_ptr),Y
    STA rd_src+1

    ; Get load/run address → rd_dst and os_ptr
    LDY #RDE_LOAD_LO
    LDA (rd_ptr),Y
    STA rd_dst
    STA os_ptr
    LDY #RDE_LOAD_HI
    LDA (rd_ptr),Y
    STA rd_dst+1
    STA os_ptr+1

    ; Get size
    LDY #RDE_SIZE_LO
    LDA (rd_ptr),Y
    STA rd_size_lo
    LDY #RDE_SIZE_HI
    LDA (rd_ptr),Y
    STA rd_size_hi

    ; Copy to load address if storage ≠ load address
    LDA rd_src
    CMP rd_dst
    BNE @do_copy
    LDA rd_src+1
    CMP rd_dst+1
    BEQ @no_copy
@do_copy:
    JSR _rd_memcpy
@no_copy:
    ; Call program: push return-1, JMP to load addr
    ; After program RTS, execution continues at @returned
    LDA #>(@returned - 1)
    PHA
    LDA #<(@returned - 1)
    PHA
    JMP (os_ptr)            ; jump into program
@returned:
    CLC
    RTS
@err:
    SEC
    RTS

; ---------------------------------------------------------------------------
; _rd_free - Print free and total space info to ACIA
; Modifies: A, X
; ---------------------------------------------------------------------------
_rd_free:
    JSR _rd_check
    BCS @invalid
    ; Free = RD_END_ADDR+1 - free_ptr
    LDA #<(RD_END_ADDR+1)
    SEC
    SBC RD_FREE_LO
    STA rd_size_lo
    LDA #>(RD_END_ADDR+1)
    SBC RD_FREE_HI
    STA rd_size_hi
    LDA #<str_free
    LDX #>str_free
    JSR _acia_puts
    LDA rd_size_hi
    JSR _print_byte
    LDA rd_size_lo
    JSR _print_byte
    LDA #<str_of8k
    LDX #>str_of8k
    JSR _acia_print_nl
    RTS
@invalid:
    LDA #<str_nofmt
    LDX #>str_nofmt
    JSR _acia_print_nl
    RTS

; ---------------------------------------------------------------------------
; _rd_memcpy - Copy rd_size_hi:rd_size_lo bytes from (rd_src) to (rd_dst)
; Advances rd_src and rd_dst.  Handles 0-byte size gracefully.
; Modifies: A, Y, rd_src, rd_dst, rd_size_lo, rd_size_hi
; ---------------------------------------------------------------------------
_rd_memcpy:
    LDY #0
    ; First copy full 256-byte pages (rd_size_hi pages)
    LDA rd_size_hi
    BEQ @tail
@page:
    LDA (rd_src),Y
    STA (rd_dst),Y
    INY
    BNE @page
    INC rd_src+1
    INC rd_dst+1
    DEC rd_size_hi
    BNE @page
@tail:
    ; Then copy remaining rd_size_lo bytes
    LDA rd_size_lo
    BEQ @done
@byte:
    LDA (rd_src),Y
    STA (rd_dst),Y
    INY
    DEC rd_size_lo
    BNE @byte
@done:
    RTS

; ---------------------------------------------------------------------------
; Strings
; ---------------------------------------------------------------------------

.segment "RODATA"

str_dir_hdr:  .byte "# NAME     SIZE LOAD  TYPE",13,10,0
str_run_flag: .byte " [RUN]",0
str_data_flag:.byte " [DAT]",0
str_empty:    .byte "(empty)",0
str_free:     .byte "Free: $",0
str_of8k:     .byte " / $5EF0 bytes (24 KB)",0
str_nofmt:    .byte "RAMDisk not formatted (use FORMAT)",0
