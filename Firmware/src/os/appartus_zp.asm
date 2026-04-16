; appartus_zp.asm - AppartusOS zero page allocations
;
; Range $40-$50: clear of cc65 ($00-$1F), EWOZ ($24-$30), ihex ($38-$3E), utils ($xx)
; These are used exclusively by OS kernel routines.
;
; Naming convention: exported as .exportzp so other modules can .importzp them.

.zeropage

os_arg0:    .res 1      ; $40 - scratch byte / general arg 0
os_arg1:    .res 1      ; $41 - scratch byte / general arg 1
os_ptr:     .res 2      ; $42-$43 - OS name/generic pointer (lo/hi)
rd_ptr:     .res 2      ; $44-$45 - RAMDisk dir-entry pointer (lo/hi)
rd_idx:     .res 1      ; $46 - current dir entry index (0..RD_MAX_FILES-1)
rd_tmp:     .res 1      ; $47 - RAMDisk scratch byte
parse_idx:  .res 1      ; $48 - shell command buffer parse position
rd_src:     .res 2      ; $49-$4A - memcpy source pointer (lo/hi)
rd_dst:     .res 2      ; $4B-$4C - memcpy dest pointer (lo/hi)
rd_size_lo: .res 1      ; $4D - file/copy size low byte
rd_size_hi: .res 1      ; $4E - file/copy size high byte

.exportzp os_arg0, os_arg1, os_ptr, rd_ptr, rd_idx, rd_tmp
.exportzp parse_idx, rd_src, rd_dst, rd_size_lo, rd_size_hi
