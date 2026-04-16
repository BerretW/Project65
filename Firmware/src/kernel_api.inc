; kernel_api.inc - AppartusOS public kernel API
;
; Include this file in your 65C02 assembly programs to access
; all OS services through the fixed ROM jump table.
;
; Usage example:
;   .include "kernel_api.inc"
;
;   ; Print a string (A=lo, X=hi, null-terminated)
;   LDA #<my_string
;   LDX #>my_string
;   JSR OS_PUTS
;
;   ; Save a file to RAMDisk
;   LDA #<filename       ; os_ptr = filename string
;   STA OS_ZP_OSPTR
;   LDA #>filename
;   STA OS_ZP_OSPTR+1
;   LDA #<6090           ; rd_src = source address
;   STA OS_ZP_RDSRC
;   LDA #>6090
;   STA OS_ZP_RDSRC+1
;   LDA #<$0100          ; rd_size_lo/hi = 256 bytes
;   STA OS_ZP_SIZELO
;   LDA #>$0100
;   STA OS_ZP_SIZEHI
;   LDA #<$6090          ; load address (where program runs)
;   STA OS_ZP_ARG0
;   LDA #>$6090
;   STA OS_ZP_ARG1
;   LDA #$03             ; RDF_VALID|RDF_RUN
;   STA OS_ZP_RDTMP
;   JSR OS_RD_SAVE
;   ; C=0 OK, C=1 error
;
; ============================================================
; Part 1 – Base ROM jump table (from jumptable.inc65)
; ============================================================

ROM_RST       = $FF00   ; Restart (jump to main/bootloader)
ROM_INTEN     = $FF03   ; Enable IRQ (CLI)
ROM_INTDI     = $FF06   ; Disable IRQ (SEI)
ROM_PUTC      = $FF09   ; Print char in A
ROM_PUTS      = $FF0C   ; Print null-terminated string (A=lo, X=hi)
ROM_GETC      = $FF0F   ; Blocking receive → A
ROM_SCAN      = $FF12   ; Non-blocking receive → A (0 = nothing)
ROM_PUTNL     = $FF15   ; Send CR+LF
ROM_PRINTNL   = $FF18   ; Print string + CR+LF (A=lo, X=hi)
ROM_PRTBYTE   = $FF1B   ; Print A as 2 hex digits
ROM_INSCAN    = $FF1E   ; Scan kbd or serial (non-blocking) → A
ROM_GETINP    = $FF21   ; Wait for kbd or serial input → A
ROM_DELAY     = $FF24   ; Software delay (A = count)
ROM_ACIA_INIT = $FF27   ; Init ACIA (19200 8N1)
ROM_IRQ_INIT  = $FF2A   ; Init IRQ timer
ROM_NMI_INIT  = $FF2D   ; Init NMI timer
ROM_INIT_VEC  = $FF30   ; Set IRQ/NMI vectors to default ISR

; ============================================================
; Part 2 – AppartusOS extended jump table ($FF33+)
; ============================================================

OS_SHELL      = $FF33   ; Enter OS shell (does not return)
OS_RD_INIT    = $FF36   ; Format/initialise RAMDisk
OS_RD_LIST    = $FF39   ; Print directory listing to ACIA
OS_RD_FIND    = $FF3C   ; Find file (os_ptr→name) → rd_idx; C=0 found
OS_RD_SAVE    = $FF3F   ; Save RAM region to RAMDisk (see ZP args below)
OS_RD_DEL     = $FF42   ; Delete file (rd_idx = entry index)
OS_RD_RUN     = $FF45   ; Copy+run file (rd_idx = entry index)
OS_RD_FREE    = $FF48   ; Print free space to ACIA
OS_RD_CPY     = $FF4B   ; memcpy rd_src→rd_dst, rd_size_hi:lo bytes

; ============================================================
; Part 2b – VFS / file-descriptor API ($FF4E+)
; ============================================================
; Devices: CON  NULL  VIA1  VIA2
; Pre-opened: FD 0 = stdin (CON), FD 1 = stdout (CON), FD 2 = stderr (CON)
; User FDs:   FD 3..5  (opened by OS_FOPEN, closed by OS_FCLOSE)
;
; Calling convention:
;   OS_FIO_INIT               — call once at boot (done by main_appartus.c)
;   OS_FOPEN  A=lo, X=hi      — open by name; Out: A=fd (3-5), C=1 error
;   OS_FCLOSE X=fd            — close; FDs 0-2 protected
;   OS_FGETC  X=fd            — Out: A=byte, C=0 ok; C=1 EOF/error
;   OS_FPUTC  A=byte, X=fd    — Out: C=0 ok; C=1 error (files are read-only)
;
; Example — dump file HELLO to console:
;   LDA #<str_hello           ; "HELLO",0
;   LDX #>str_hello
;   JSR OS_FOPEN              ; A=fd, C=0 if found
;   BCS not_found
;   TAX
; loop: JSR OS_FGETC          ; X=fd
;   BCS done                  ; EOF
;   JSR ROM_PUTC
;   BRA loop
; done: JSR OS_FCLOSE

OS_FIO_INIT   = $FF4E   ; Init FD table, open FD 0/1/2 as CON
OS_FOPEN      = $FF51   ; Open file/device (A=name_lo, X=name_hi) → A=fd
OS_FCLOSE     = $FF54   ; Close fd (X=fd)
OS_FGETC      = $FF57   ; Read byte (X=fd) → A; C=1 EOF
OS_FPUTC      = $FF5A   ; Write byte (A=byte, X=fd) → C=1 error

; ============================================================
; Part 3 – OS zero page variable addresses
; (read/write these to pass arguments to OS routines)
; ============================================================

OS_ZP_ARG0    = $40     ; Byte arg 0 (e.g. load_addr lo for SAVE)
OS_ZP_ARG1    = $41     ; Byte arg 1 (e.g. load_addr hi for SAVE)
OS_ZP_OSPTR   = $42     ; 2-byte pointer: filename for FIND/SAVE ($42 lo, $43 hi)
OS_ZP_RDPTR   = $44     ; 2-byte RAMDisk entry pointer ($44 lo, $45 hi)
OS_ZP_RDIDX   = $46     ; Dir entry index (0-7) for DEL/RUN
OS_ZP_RDTMP   = $47     ; Flags byte for SAVE (RDF_VALID|RDF_RUN etc.)
OS_ZP_RDSRC   = $49     ; 2-byte copy source ($49 lo, $4A hi)
OS_ZP_RDDST   = $4B     ; 2-byte copy dest ($4B lo, $4C hi)
OS_ZP_SIZELO  = $4D     ; Copy/file size lo
OS_ZP_SIZEHI  = $4E     ; Copy/file size hi
; VFS layer ZP (read-only for user programs — managed by OS_FOPEN/FGETC)
OS_ZP_FDTMP   = $4F     ; Scratch fd during OS_FOPEN
OS_ZP_FIOPTR  = $50     ; 2-byte FD table entry pointer ($50 lo, $51 hi)
OS_ZP_IOBUF   = $52     ; 2-byte computed read address  ($52 lo, $53 hi)

; ============================================================
; Part 4 – RAMDisk layout constants
; ============================================================

; RAMDisk spans IC6 upper ($6000-$7FFF) + full IC7 ($8000-$BFFF) = 24 KB
RD_START      = $6000   ; RAMDisk start
RD_HDR        = $6000   ; Header (16 bytes)
RD_DIR        = $6010   ; Directory (16 × 16 bytes = 256 bytes)
RD_DATA       = $6110   ; File data area start (~24 KB usable)
RD_END        = $BFFF   ; RAMDisk end

RD_MAX_FILES  = 16      ; Maximum number of files
RD_NAME_LEN   = 8       ; Maximum filename length

; Directory entry field offsets (relative to entry base address)
RDE_NAME      = 0       ; Filename (8 bytes, null-padded)
RDE_LOAD_LO   = 8       ; Load/run address lo
RDE_LOAD_HI   = 9       ; Load/run address hi
RDE_SIZE_LO   = 10      ; File size lo
RDE_SIZE_HI   = 11      ; File size hi
RDE_FLAGS     = 12      ; Flags (see below)
RDE_STOR_LO   = 13      ; Physical storage address lo
RDE_STOR_HI   = 14      ; Physical storage address hi

; Flag bits for RDE_FLAGS
RDF_VALID     = $01     ; Entry is in use
RDF_RUN       = $02     ; Entry is an executable program

; ============================================================
; Part 5 – Hardware I/O addresses (for direct access)
; ============================================================

ACIA_BASE     = $C800
ACIA_DATA     = $C800
ACIA_STATUS   = $C801
ACIA_COMMAND  = $C802
ACIA_CONTROL  = $C803

VIA1_BASE     = $CC00   ; IC18 – ATtiny26 / NMI source
VIA2_BASE     = $CC80   ; IC16 – JP8 parallel port / IRQ1

IRQ_LATCH_R   = $C480   ; Read IRQ status (74HC574 latch)
IRQ_LATCH_W   = $C400   ; Write/ACK IRQ

; ============================================================
; Part 6 – Convenience macros
; ============================================================

; OS_PRINT str_label - print a null-terminated string in RODATA
.macro OS_PRINT lbl
    LDA #<lbl
    LDX #>lbl
    JSR ROM_PUTS
.endmacro

; OS_PRINTLN str_label - print string + CRLF
.macro OS_PRINTLN lbl
    LDA #<lbl
    LDX #>lbl
    JSR ROM_PRINTNL
.endmacro

; OS_CALL addr - JSR to a fixed ROM address
.macro OS_CALL addr
    JSR addr
.endmacro
