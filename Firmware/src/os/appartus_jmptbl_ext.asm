; appartus_jmptbl_ext.asm - AppartusOS extended jump table
;
; This file appends OS kernel entries to the JMPTBL segment.
; The base ROM entries ($FF00-$FF32) come from jumptable.asm.
; OS entries begin at $FF33 and are appended sequentially.
;
; IMPORTANT: This file is linked AFTER jumptable.asm in the OS build
; so its JMPTBL entries land immediately after $FF32.
;
; See kernel_api.inc for the named constants for user programs.

.setcpu     "65C02"
.smart      on
.autoimport on
.case       on

.segment "JMPTBL"

; $FF33 - Enter OS shell (main loop, does not return)
_JOS_SHELL:     JMP _os_main

; $FF36 - Initialise / format RAMDisk
_JOS_RD_INIT:   JMP _rd_init

; $FF39 - Print RAMDisk directory to ACIA
_JOS_RD_LIST:   JMP _rd_list

; $FF3C - Find file: os_ptr→name  C=0 found (rd_idx), C=1 not found
_JOS_RD_FIND:   JMP _rd_find

; $FF3F - Save RAM region to RAMDisk (see _rd_save for calling convention)
_JOS_RD_SAVE:   JMP _rd_save

; $FF42 - Delete file by rd_idx
_JOS_RD_DEL:    JMP _rd_del

; $FF45 - Copy+run file by rd_idx
_JOS_RD_RUN:    JMP _rd_run

; $FF48 - Print RAMDisk free space to ACIA
_JOS_RD_FREE:   JMP _rd_free

; $FF4B - RAMDisk memcpy helper (rd_src→rd_dst, rd_size_hi:lo bytes)
_JOS_RD_CPY:    JMP _rd_memcpy

; $FF4E - Initialise FD table and pre-open stdin/stdout/stderr as CON
_JFIO_INIT:     JMP _fio_init

; $FF51 - Open file or device by name (A=name_lo, X=name_hi) → A=fd; C=1 error
_JFOPEN:        JMP _fopen

; $FF54 - Close file descriptor (X=fd); FD 0-2 are protected
_JFCLOSE:       JMP _fclose

; $FF57 - Read byte from fd (X=fd) → A=byte; C=1 EOF/error
_JFGETC:        JMP _fgetc

; $FF5A - Write byte to fd (A=byte, X=fd) → C=1 error
_JFPUTC:        JMP _fputc

.export _JOS_SHELL, _JOS_RD_INIT, _JOS_RD_LIST, _JOS_RD_FIND
.export _JOS_RD_SAVE, _JOS_RD_DEL, _JOS_RD_RUN, _JOS_RD_FREE
.export _JOS_RD_CPY
.export _JFIO_INIT, _JFOPEN, _JFCLOSE, _JFGETC, _JFPUTC
