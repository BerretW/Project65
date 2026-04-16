; appartus_fileio.asm  —  AppartusOS VFS layer
;
; Devices and RAMDisk files accessible through a unified file-descriptor API.
;
; Pre-opened FDs (set up by _fio_init, called at boot):
;   FD 0  STDIN   CON  read
;   FD 1  STDOUT  CON  write
;   FD 2  STDERR  CON  write
;
; Device names recognised by _fopen:
;   CON   ACIA serial console  (read blocks until char; write sends char)
;   NULL  /dev/null            (writes discarded; reads return EOF)
;   VIA1  VIA1 port A  $CC01   (raw byte I/O on IC18 — ATtiny/keyboard VIA)
;   VIA2  VIA2 port A  $CC81   (raw byte I/O on IC16 — parallel port VIA)
;
; Calling convention:
;   _fio_init              — clear table, open FD 0/1/2 as CON
;   _fopen  A=name_lo,
;           X=name_hi      — null-terminated name (max 8 chars)
;                            Out: A=fd (3-5), C=0 OK; A=$FF C=1 error
;   _fclose X=fd           — FDs 0-2 (stdio) are protected and cannot be closed
;   _fgetc  X=fd           — Out: A=byte, C=0 OK; C=1 EOF/error
;   _fputc  A=byte, X=fd   — Out: C=0 OK; C=1 error (file fds are read-only)
;
; ZP variables (defined in appartus_zp.asm):
;   fd_tmp  $4F   scratch fd / chosen slot during _fopen
;   fio_ptr $50   2-byte pointer to current FD table entry or dev-name scan
;   io_buf  $52   2-byte computed read address (file fgetc path)

.setcpu     "65C02"
.smart      on
.autoimport on
.case       on

.include    "../io.inc65"

.importzp   os_ptr, rd_ptr, rd_idx, rd_tmp
.importzp   fd_tmp, fio_ptr, io_buf

.import     _rd_find
.import     _acia_getc, _acia_putc

.export     _fio_init
.export     _fopen
.export     _fclose
.export     _fgetc
.export     _fputc

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------

FD_MAX        = 6           ; total file descriptors (0-5)
FD_ENTRY_SZ   = 10          ; bytes per FD table entry
FD_TABLE_SZ   = FD_MAX * FD_ENTRY_SZ   ; 60 bytes

; FD entry field offsets
FD_TYPE       = 0           ; entry type (FDT_*)
FD_DEV        = 1           ; device id or rd_idx for files
FD_FLAGS      = 2           ; open flags (FD_R, FD_W, FD_EOF_F)
FD_POS_LO     = 3           ; current read position lo (file fds)
FD_POS_HI     = 4           ; current read position hi
FD_BASE_LO    = 5           ; storage base address lo  (file fds)
FD_BASE_HI    = 6           ; storage base address hi
FD_SIZE_LO    = 7           ; file size lo             (file fds)
FD_SIZE_HI    = 8           ; file size hi
                            ; byte 9 = padding

; FD type values
FDT_FREE      = 0
FDT_DEV       = 1
FDT_FILE      = 2

; FD flag bits
FD_R          = $01         ; open for reading
FD_W          = $02         ; open for writing

; Device IDs (index into dispatch tables)
DEV_CON       = 0
DEV_NULL      = 1
DEV_VIA1      = 2
DEV_VIA2      = 3
DEV_COUNT     = 4

; RAMDisk dir-entry field offsets (from appartus_ramdisk.asm)
RDE_SIZE_LO   = 10
RDE_SIZE_HI   = 11
RDE_STOR_LO   = 13
RDE_STOR_HI   = 14

; ---------------------------------------------------------------------------
; BSS — FD table (zeroed at startup by crt0, re-initialised by _fio_init)
; ---------------------------------------------------------------------------

.segment "BSS"

fd_table:     .res FD_TABLE_SZ   ; 60 bytes

; ---------------------------------------------------------------------------
; RODATA — device name table and dispatch vectors
; ---------------------------------------------------------------------------

.segment "RODATA"

; Device name table: null-terminated entries, ends with an extra null sentinel.
dev_names:
    .byte "CON",0
    .byte "NULL",0
    .byte "VIA1",0
    .byte "VIA2",0
    .byte 0             ; sentinel: empty string = end of table

; Dispatch tables: 2-byte (word) address per device, indexed by dev_id*2.
dev_getc_tbl:
    .word _dev_con_getc
    .word _dev_null_getc
    .word _dev_via1_getc
    .word _dev_via2_getc

dev_putc_tbl:
    .word _dev_con_putc
    .word _dev_null_putc
    .word _dev_via1_putc
    .word _dev_via2_putc

; ---------------------------------------------------------------------------
; CODE
; ---------------------------------------------------------------------------

.segment "CODE"

; ---------------------------------------------------------------------------
; _fio_init — Initialise FD table and pre-open FD 0/1/2 as CON
; Modifies: A, X
; ---------------------------------------------------------------------------
_fio_init:
    LDA #0
    LDX #FD_TABLE_SZ - 1
@clr:
    STA fd_table,X
    DEX
    BPL @clr
    ; FD 0 = STDIN : CON, read
    LDA #FDT_DEV
    STA fd_table + 0 * FD_ENTRY_SZ + FD_TYPE
    LDA #DEV_CON
    STA fd_table + 0 * FD_ENTRY_SZ + FD_DEV
    LDA #FD_R
    STA fd_table + 0 * FD_ENTRY_SZ + FD_FLAGS
    ; FD 1 = STDOUT : CON, write
    LDA #FDT_DEV
    STA fd_table + 1 * FD_ENTRY_SZ + FD_TYPE
    LDA #DEV_CON
    STA fd_table + 1 * FD_ENTRY_SZ + FD_DEV
    LDA #FD_W
    STA fd_table + 1 * FD_ENTRY_SZ + FD_FLAGS
    ; FD 2 = STDERR : CON, write
    LDA #FDT_DEV
    STA fd_table + 2 * FD_ENTRY_SZ + FD_TYPE
    LDA #DEV_CON
    STA fd_table + 2 * FD_ENTRY_SZ + FD_DEV
    LDA #FD_W
    STA fd_table + 2 * FD_ENTRY_SZ + FD_FLAGS
    RTS

; ---------------------------------------------------------------------------
; _fd_setptr — Point fio_ptr at fd_table[X]  (X = fd, 0..FD_MAX-1)
; Computes fio_ptr = &fd_table + X*10 (FD_ENTRY_SZ = 10).
; Preserves X.  Modifies A, fio_ptr.
; ---------------------------------------------------------------------------
_fd_setptr:
    PHX                 ; preserve fd value
    TXA
    ASL A               ; A = fd*2
    STA fio_ptr         ; temp: store fd*2 in fio_ptr lo (scratch)
    ASL A               ; A = fd*4
    ASL A               ; A = fd*8
    CLC
    ADC fio_ptr         ; A = fd*8 + fd*2 = fd*10
    CLC
    ADC #<fd_table
    STA fio_ptr
    LDA #>fd_table
    ADC #0
    STA fio_ptr+1
    PLX                 ; restore fd
    RTS

; ---------------------------------------------------------------------------
; _fopen — Open a device or RAMDisk file by name
; In:  A = name ptr lo, X = name ptr hi  (null-terminated, max 8 chars)
; Out: A = fd (3..5), C=0 OK;   A=$FF, C=1 error (not found or table full)
; Modifies: A, X, Y, os_ptr, fio_ptr, fd_tmp, rd_tmp, rd_idx, rd_ptr, io_buf
; ---------------------------------------------------------------------------
_fopen:
    STA os_ptr
    STX os_ptr+1

    ; Find a free user FD slot (scan 5 down to 3; leave 0-2 for stdio)
    LDX #FD_MAX - 1
@find_slot:
    CPX #2              ; X <= 2 means no user slots available
    BEQ @table_full
    JSR _fd_setptr      ; fio_ptr → fd_table[X]; preserves X
    LDA (fio_ptr)       ; FD_TYPE offset 0
    BEQ @slot_found     ; FDT_FREE = 0
    DEX
    BRA @find_slot
@table_full:
    LDA #$FF
    SEC
    RTS
@slot_found:
    STX fd_tmp          ; X still holds the chosen fd (fd_setptr preserves X)

    ; --- Scan device name table ---
    LDA #<dev_names
    STA fio_ptr
    LDA #>dev_names
    STA fio_ptr+1
    STZ rd_tmp          ; dev_id counter

@dev_loop:
    LDA (fio_ptr)       ; first byte of current device name
    BEQ @try_ramdisk    ; sentinel (extra null) = end of table
    JSR _str_match      ; compare os_ptr string vs fio_ptr string;
                        ; advances fio_ptr past current name; C=0 match
    BCS @dev_no_match
    ; Match — fill FD entry as device
    LDX fd_tmp
    JSR _fd_setptr
    LDA #FDT_DEV
    STA (fio_ptr)
    LDA rd_tmp          ; dev_id
    LDY #FD_DEV
    STA (fio_ptr),Y
    LDA #(FD_R | FD_W)
    LDY #FD_FLAGS
    STA (fio_ptr),Y
    LDA fd_tmp
    CLC
    RTS
@dev_no_match:
    INC rd_tmp
    LDA rd_tmp
    CMP #DEV_COUNT
    BNE @dev_loop

@try_ramdisk:
    ; os_ptr still holds the requested filename
    JSR _rd_find        ; C=0 found: rd_idx = slot, rd_ptr → dir entry
    BCS @not_found
    ; Fill FD entry as ramdisk file (read-only)
    LDX fd_tmp
    JSR _fd_setptr
    LDA #FDT_FILE
    STA (fio_ptr)
    LDA rd_idx
    LDY #FD_DEV
    STA (fio_ptr),Y
    LDA #FD_R
    LDY #FD_FLAGS
    STA (fio_ptr),Y
    ; Position = 0
    LDA #0
    LDY #FD_POS_LO
    STA (fio_ptr),Y
    LDY #FD_POS_HI
    STA (fio_ptr),Y
    ; Base address = stor_addr from dir entry (rd_ptr set by _rd_find)
    LDY #RDE_STOR_LO
    LDA (rd_ptr),Y
    LDY #FD_BASE_LO
    STA (fio_ptr),Y
    LDY #RDE_STOR_HI
    LDA (rd_ptr),Y
    LDY #FD_BASE_HI
    STA (fio_ptr),Y
    ; Size from dir entry
    LDY #RDE_SIZE_LO
    LDA (rd_ptr),Y
    LDY #FD_SIZE_LO
    STA (fio_ptr),Y
    LDY #RDE_SIZE_HI
    LDA (rd_ptr),Y
    LDY #FD_SIZE_HI
    STA (fio_ptr),Y
    LDA fd_tmp
    CLC
    RTS
@not_found:
    LDA #$FF
    SEC
    RTS

; ---------------------------------------------------------------------------
; _fclose — Close a file descriptor
; In:  X = fd.  FDs 0-2 (stdio) are protected and silently skipped.
; Modifies: A, X, fio_ptr
; ---------------------------------------------------------------------------
_fclose:
    CPX #3
    BCC @protected      ; FD 0-2: do not close
    CPX #FD_MAX
    BCS @protected
    JSR _fd_setptr
    LDA #FDT_FREE
    STA (fio_ptr)       ; clear type byte → marks slot as free
@protected:
    RTS

; ---------------------------------------------------------------------------
; _fgetc — Read one byte from fd
; In:  X = fd
; Out: A = byte, C=0 OK;   C=1 EOF or error
; Modifies: A, X, Y, fio_ptr, io_buf
; ---------------------------------------------------------------------------
_fgetc:
    CPX #FD_MAX
    BCS @err
    JSR _fd_setptr
    LDA (fio_ptr)       ; FD_TYPE
    CMP #FDT_DEV
    BEQ @device
    CMP #FDT_FILE
    BEQ @file
@err:
    SEC
    RTS

@device:
    LDY #FD_DEV
    LDA (fio_ptr),Y     ; dev_id (0-3)
    ASL A               ; * 2 → word index
    TAY
    LDA dev_getc_tbl,Y
    STA io_buf
    LDA dev_getc_tbl+1,Y
    STA io_buf+1
    JMP (io_buf)        ; tail-call device handler; handler RTS → _fgetc caller

@file:
    ; 16-bit EOF check: EOF when pos >= size
    LDY #FD_POS_HI
    LDA (fio_ptr),Y
    LDY #FD_SIZE_HI
    CMP (fio_ptr),Y     ; compare pos_hi with size_hi
    BCC @read_file      ; pos_hi < size_hi → not EOF
    BNE @eof            ; pos_hi > size_hi → EOF
    ; pos_hi == size_hi: compare lo bytes
    LDY #FD_POS_LO
    LDA (fio_ptr),Y
    LDY #FD_SIZE_LO
    CMP (fio_ptr),Y     ; compare pos_lo with size_lo
    BCC @read_file      ; pos_lo < size_lo → not EOF
@eof:
    SEC
    RTS

@read_file:
    ; Compute effective address = base_addr + pos (16-bit)
    LDY #FD_BASE_LO
    LDA (fio_ptr),Y
    STA io_buf
    LDY #FD_BASE_HI
    LDA (fio_ptr),Y
    STA io_buf+1
    LDY #FD_POS_LO
    LDA (fio_ptr),Y
    CLC
    ADC io_buf
    STA io_buf
    LDY #FD_POS_HI
    LDA (fio_ptr),Y
    ADC io_buf+1
    STA io_buf+1
    ; Read byte at computed address
    LDY #0
    LDA (io_buf),Y
    PHA
    ; Increment 16-bit position
    LDY #FD_POS_LO
    LDA (fio_ptr),Y
    INC A
    STA (fio_ptr),Y
    BNE @pos_ok
    LDY #FD_POS_HI
    LDA (fio_ptr),Y
    INC A
    STA (fio_ptr),Y
@pos_ok:
    PLA
    CLC
    RTS

; ---------------------------------------------------------------------------
; _fputc — Write one byte to fd
; In:  A = byte, X = fd
; Out: C=0 OK;   C=1 error (file fds are read-only; free/invalid fd = error)
; Modifies: A, X, Y, fio_ptr, io_buf
; ---------------------------------------------------------------------------
_fputc:
    PHA                 ; save byte across _fd_setptr
    CPX #FD_MAX
    BCS @err
    JSR _fd_setptr
    LDA (fio_ptr)       ; FD_TYPE
    CMP #FDT_DEV
    BEQ @device
    ; FDT_FILE or FDT_FREE → error (files are read-only after save)
@err:
    PLA
    SEC
    RTS

@device:
    LDY #FD_DEV
    LDA (fio_ptr),Y     ; dev_id
    ASL A
    TAY
    LDA dev_putc_tbl,Y
    STA io_buf
    LDA dev_putc_tbl+1,Y
    STA io_buf+1
    PLA                 ; restore byte into A
    JMP (io_buf)        ; tail-call device handler

; ---------------------------------------------------------------------------
; Device handlers — each returns with A set and C flag indicating status
; ---------------------------------------------------------------------------

_dev_con_getc:
    JMP _acia_getc      ; blocks until char received; A=char, never sets C

_dev_con_putc:
    JSR _acia_putc
    CLC
    RTS

_dev_null_getc:
    LDA #0
    SEC                 ; EOF
    RTS

_dev_null_putc:
    CLC                 ; discard — success
    RTS

_dev_via1_getc:
    LDA VIA1_ORA        ; read IC18 port A  ($CC01)
    CLC
    RTS

_dev_via1_putc:
    STA VIA1_ORA        ; write IC18 port A
    CLC
    RTS

_dev_via2_getc:
    LDA VIA2_ORA        ; read IC16 port A  ($CC81)
    CLC
    RTS

_dev_via2_putc:
    STA VIA2_ORA        ; write IC16 port A
    CLC
    RTS

; ---------------------------------------------------------------------------
; _str_match — Compare string at os_ptr with string at fio_ptr (device table)
;
; Advances fio_ptr past the current entry regardless of outcome, ready for
; the next call.  Uses 65C02 CMP (zp),Y for zero-scratch comparison.
;
; In:  os_ptr = input string, fio_ptr = device name entry
; Out: C=0 match, C=1 no match
; Modifies: A, Y, fio_ptr.  Preserves: X, os_ptr.
; ---------------------------------------------------------------------------
_str_match:
    LDY #0
@loop:
    LDA (os_ptr),Y          ; input char
    CMP (fio_ptr),Y         ; compare with device name char (65C02: CMP (zp),Y)
    BNE @no_match
    LDA (fio_ptr),Y         ; reload device char to test for null terminator
    BEQ @match              ; both chars were null → strings are equal
    INY
    BRA @loop

@match:
    ; Advance fio_ptr by Y+1 to skip past the null terminator
    TYA
    INC A
    CLC
    ADC fio_ptr
    STA fio_ptr
    BCC @done_match
    INC fio_ptr+1
@done_match:
    CLC
    RTS

@no_match:
    ; Skip fio_ptr to the byte after the null terminator of this entry
@skip:
    LDA (fio_ptr),Y
    BEQ @skip_done
    INY
    BRA @skip
@skip_done:
    INY                     ; step past null itself
    TYA
    CLC
    ADC fio_ptr
    STA fio_ptr
    BCC @done_nm
    INC fio_ptr+1
@done_nm:
    SEC
    RTS
