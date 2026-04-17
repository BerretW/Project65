; appartus_basic.asm - P65 BASIC v1.0
;
; Minimal integer BASIC for Project65 SBC.
; Entry:  _basic_main  (called from OS shell via BASIC command)
; Return: caller (user typed BYE/EXIT)
;
; Program RAM:    $2000-$4FFF  (sorted lines, 12 KB)
; Program format: [lnum_lo][lnum_hi][text_NUL]...[0x00][0x00]  (sentinel)
;
; Direct commands: NEW LIST RUN SAVE LOAD BYE
; Statements:      PRINT INPUT LET IF FOR NEXT WHILE WEND
;                  GOTO GOSUB RETURN END POKE REM
; Expressions:     + - * /  = <> < > <= >=  PEEK() vars(A-Z) literals
;
; Operator precedence (low→high): compare → +/- → */  → unary/primary
; Comparisons return 0 (false) or 1 (true), all 16-bit signed arithmetic.

.setcpu     "65C02"
.smart      on
.autoimport on
.case       on
.macpack    longbranch

.include "../io.inc65"

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
BAS_START   = $2000     ; program RAM base
BAS_MAXEND  = $4F00     ; program RAM limit (~12 KB)
BAS_MAX_FOR = 8
BAS_MAX_WHL = 8
BAS_MAX_GSB = 8

RDF_VALID   = $01
RD_DIR      = $6010

; ---------------------------------------------------------------------------
; Zero page  ($54-$66) — free of cc65($00-$1F), ihex($38-$3E), OS($40-$53)
; ---------------------------------------------------------------------------
.zeropage

bas_ip:   .res 2   ; $54-$55  execution pointer (into current line text)
bas_lp:   .res 2   ; $56-$57  line pointer (to lnum_lo of current line)
bas_ep:   .res 2   ; $58-$59  end-of-program (just past last NUL, before sentinel)
bas_acc:  .res 2   ; $5A-$5B  expression accumulator
bas_rhs:  .res 2   ; $5C-$5D  expression RHS / keyword scan ptr / memmove dst
bas_tmp:  .res 2   ; $5E-$5F  16-bit scratch
bas_tmp2: .res 2   ; $60-$61  16-bit scratch #2 / memmove src
bas_fsp:  .res 1   ; $62      FOR  stack depth (0-8)
bas_gsp:  .res 1   ; $63      GOSUB stack depth (0-8)
bas_wsp:  .res 1   ; $64      WHILE stack depth (0-8)

.exportzp bas_ip, bas_lp, bas_ep, bas_acc, bas_rhs, bas_tmp, bas_tmp2
.exportzp bas_fsp, bas_gsp, bas_wsp

; ---------------------------------------------------------------------------
; BSS — zeroed by crt0 at startup
; ---------------------------------------------------------------------------
.segment "BSS"

bas_vars:      .res 52   ; variables A-Z (A=+0, B=+2, …, Z=+50), 16-bit each
bas_for_stk:   .res 56   ; 8 × 7: var_id(1)+to_lo+hi(2)+step_lo+hi(2)+body_lo+hi(2)
bas_whl_stk:   .res 32   ; 8 × 4: cond_lo+hi(2)+body_lo+hi(2)
bas_gsb_stk:   .res 16   ; 8 × 2: ret_lo+hi
bas_ibuf:      .res 82   ; BASIC line input buffer (80 chars + NUL + 1)
bas_lnum:      .res 2    ; line number parsed from current input

; ---------------------------------------------------------------------------
; CODE
; ---------------------------------------------------------------------------
.segment "CODE"
.export _basic_main

; ============================================================
; _basic_main — entry from OS shell
; ============================================================
_basic_main:
    JSR _bas_new
    LDA #<str_bas_banner
    LDX #>str_bas_banner
    JSR _acia_print_nl
    LDA #<str_bas_hint
    LDX #>str_bas_hint
    JSR _acia_print_nl

; ============================================================
; REPL — Read-Eval-Print Loop (never returns except via BYE)
; ============================================================
_bas_repl:
    LDA #<str_bas_prompt
    LDX #>str_bas_prompt
    JSR _acia_puts
    JSR _bas_getline          ; → bas_ibuf (uppercase)
    LDA bas_ibuf
    BEQ _bas_repl

    ; Digit first → store/delete program line
    CMP #'0'
    BCC @direct
    CMP #'9'+1
    BCS @direct
    JSR _bas_store_line
    JMP _bas_repl
@direct:
    LDA #<bas_ibuf
    STA bas_ip
    LDA #>bas_ibuf
    STA bas_ip+1
    JSR _bas_exec_direct
    jcs _bas_run_loop
    JMP _bas_repl

; ============================================================
; _bas_getline — read line from ACIA into bas_ibuf, uppercase
; ============================================================
_bas_getline:
    LDY #0
@gl:
    JSR _acia_getc
    CMP #$1B
    BEQ @esc   ; ESC → clear
    CMP #$0D
    BEQ @done   ; CR  → done
    CMP #$0A
    BEQ @gl   ; LF  → ignore
    CMP #$7F
    BEQ @bs   ; DEL → backspace
    CMP #$08
    BEQ @bs   ; BS
    CPY #80
    BEQ @gl   ; buffer full
    CMP #'a'
    BCC @st
    CMP #'z'+1
    BCS @st
    AND #$DF                  ; to uppercase
@st:
    STA bas_ibuf,Y
    JSR _acia_putc
    INY
    BRA @gl
@bs:
    CPY #0
    BEQ @gl
    DEY
    LDA #$08
    JSR _acia_putc
    LDA #' '
    JSR _acia_putc
    LDA #$08
    JSR _acia_putc
    BRA @gl
@esc:
    LDA #0
    STA bas_ibuf
    JSR _acia_put_newline
    RTS
@done:
    LDA #0
    STA bas_ibuf,Y
    JSR _acia_put_newline
    RTS

; ============================================================
; _bas_new — clear program and reset everything
; ============================================================
_bas_new:
    LDA #<BAS_START
    STA bas_ep
    LDA #>BAS_START
    STA bas_ep+1
    LDA #0
    LDY #1
    STA (bas_ep)        ; sentinel lo
    STA (bas_ep),Y      ; sentinel hi
    STZ bas_fsp
    STZ bas_gsp
    STZ bas_wsp
    LDX #51
@cv: LDA #0
STA bas_vars,X
DEX
BPL @cv
    RTS

; ============================================================
; _bas_list — list program to ACIA
; ============================================================
_bas_list:
    LDA #<BAS_START
    STA bas_lp
    LDA #>BAS_START
    STA bas_lp+1
@ll:
    ; Check sentinel
    LDA (bas_lp)
    BNE @ldo
    LDY #1
    LDA (bas_lp),Y
    BEQ @ldone
@ldo:
    ; Print line number
    LDA (bas_lp)
    STA bas_acc
    LDY #1
    LDA (bas_lp),Y
    STA bas_acc+1
    JSR _bas_print_uint
    LDA #' '
    JSR _acia_putc
    ; Print text (bas_lp+2)
    LDA bas_lp
    CLC
    ADC #2
    STA bas_ip
    LDA bas_lp+1
    ADC #0
    STA bas_ip+1
@lchar:
    LDA (bas_ip)
    BEQ @lnl
    JSR _acia_putc
    INC bas_ip
    BNE @lchar
    INC bas_ip+1
    BRA @lchar
@lnl:
    JSR _acia_put_newline
    JSR _bas_next_line
    BRA @ll
@ldone: RTS

; ============================================================
; _bas_run — run from first line
; ============================================================
_bas_run:
    STZ bas_fsp
    STZ bas_gsp
    STZ bas_wsp
    LDA #<BAS_START
    STA bas_lp
    LDA #>BAS_START
    STA bas_lp+1
_bas_run_loop:
    LDA (bas_lp)
    BNE @exec
    LDY #1
    LDA (bas_lp),Y
    BEQ @prog_end
@exec:
    LDA bas_lp
    CLC
    ADC #2
    STA bas_ip
    LDA bas_lp+1
    ADC #0
    STA bas_ip+1
    JSR _bas_exec_stmt        ; C=0 advance; C=1 bas_lp already set
    BCS _bas_run_loop
    JSR _bas_next_line
    JMP _bas_run_loop
@prog_end:
    LDA #<str_ready
    LDX #>str_ready
    JMP _acia_print_nl

; ============================================================
; _bas_next_line — advance bas_lp past current line text+NUL
; ============================================================
_bas_next_line:
    LDA bas_lp
    CLC
    ADC #2
    STA bas_ip
    LDA bas_lp+1
    ADC #0
    STA bas_ip+1
@scan:
    LDA (bas_ip)
    BEQ @nl_end
    INC bas_ip
    BNE @scan
    INC bas_ip+1
    BRA @scan
@nl_end:
    INC bas_ip
    BNE @ok
    INC bas_ip+1
@ok:
    LDA bas_ip
    STA bas_lp
    LDA bas_ip+1
    STA bas_lp+1
    RTS

; ============================================================
; Helpers: skip_spaces, skip_ip
; ============================================================
_bas_skip_spaces:
    LDA (bas_ip)
    CMP #' '
    BNE @done
    INC bas_ip
    BNE _bas_skip_spaces
    INC bas_ip+1
    BRA _bas_skip_spaces
@done: RTS

_bas_skip_ip:
    INC bas_ip
    BNE @ok
    INC bas_ip+1
@ok: RTS

; ============================================================
; _bas_check_kw — keyword match at (bas_ip) vs (bas_rhs)
; C=0 match: bas_ip advanced past keyword + trailing spaces
; C=1 no match: bas_ip unchanged
; Clobbers A, Y. Preserves X.
; ============================================================
_bas_check_kw:
    LDA bas_ip
    PHA
    LDA bas_ip+1
    PHA   ; save
    LDY #0
@cmp:
    LDA (bas_rhs),Y
    BEQ @kw_end
    CMP (bas_ip),Y
    BNE @no
    INY
    BRA @cmp
@kw_end:
    ; Word-boundary check: next char must not be A-Z, 0-9
    LDA (bas_ip),Y
    JSR _bas_is_alnum
    BCS @no
    PLA
    PLA   ; discard saved ip
    TYA
    CLC
    ADC bas_ip
    STA bas_ip
    BCC @sp
    INC bas_ip+1
@sp:
    JSR _bas_skip_spaces
    CLC
    RTS
@no:
    PLA
    STA bas_ip+1
    PLA
    STA bas_ip
    SEC
    RTS

_bas_is_alnum:              ; C=1 if A is alphanumeric
    CMP #'0'
    BCC @n
    CMP #'9'+1
    BCC @y
    CMP #'A'
    BCC @n
    CMP #'Z'+1
    BCC @y
@n: CLC
RTS
@y: SEC
RTS

; ============================================================
; _bas_exec_direct — direct command or statement
; ============================================================
_bas_exec_direct:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    BEQ @done

    LDA #<kw_new
    STA bas_rhs
    LDA #>kw_new
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @d1
    JSR _bas_new
    LDA #<str_ok
    LDX #>str_ok
    JMP _acia_print_nl
@d1:
    LDA #<kw_list
    STA bas_rhs
    LDA #>kw_list
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @d2
    JMP _bas_list
@d2:
    LDA #<kw_run
    STA bas_rhs
    LDA #>kw_run
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @d3
    JMP _bas_run
@d3:
    LDA #<kw_save
    STA bas_rhs
    LDA #>kw_save
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @d4
    JMP _bas_cmd_save
@d4:
    LDA #<kw_load
    STA bas_rhs
    LDA #>kw_load
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @d5
    JMP _bas_cmd_load
@d5:
    LDA #<kw_bye
    STA bas_rhs
    LDA #>kw_bye
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @d6
    RTS                     ; return to _basic_main → back to shell
@d6:
    JSR _bas_exec_stmt      ; fall through to statement exec
@done: RTS

; ============================================================
; _bas_exec_stmt — execute one statement at bas_ip
; C=0 normal advance; C=1 control flow changed (bas_lp set)
; ============================================================
_bas_exec_stmt:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    jeq @eol

    LDA #<kw_rem
    STA bas_rhs
    LDA #>kw_rem
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s1
    CLC
    RTS
@s1:
    LDA #<kw_print
    STA bas_rhs
    LDA #>kw_print
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s2
    JSR _bas_stmt_print
    CLC
    RTS
@s2:
    LDA #<kw_input
    STA bas_rhs
    LDA #>kw_input
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s3
    JSR _bas_stmt_input
    CLC
    RTS
@s3:
    LDA #<kw_let
    STA bas_rhs
    LDA #>kw_let
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s4
    JSR _bas_skip_spaces
    JSR _bas_stmt_assign
    CLC
    RTS
@s4:
    LDA #<kw_if
    STA bas_rhs
    LDA #>kw_if
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s5
    JMP _bas_stmt_if
@s5:
    LDA #<kw_for
    STA bas_rhs
    LDA #>kw_for
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s6
    JMP _bas_stmt_for
@s6:
    LDA #<kw_next
    STA bas_rhs
    LDA #>kw_next
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s7
    JMP _bas_stmt_next
@s7:
    LDA #<kw_while
    STA bas_rhs
    LDA #>kw_while
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s8
    JMP _bas_stmt_while_fix
@s8:
    LDA #<kw_wend
    STA bas_rhs
    LDA #>kw_wend
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s9
    JMP _bas_stmt_wend
@s9:
    LDA #<kw_goto
    STA bas_rhs
    LDA #>kw_goto
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s10
    JMP _bas_stmt_goto
@s10:
    LDA #<kw_gosub
    STA bas_rhs
    LDA #>kw_gosub
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s11
    JMP _bas_stmt_gosub
@s11:
    LDA #<kw_return
    STA bas_rhs
    LDA #>kw_return
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s12
    JMP _bas_stmt_return
@s12:
    LDA #<kw_end
    STA bas_rhs
    LDA #>kw_end
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s13
    JMP _bas_stmt_end
@s13:
    LDA #<kw_poke
    STA bas_rhs
    LDA #>kw_poke
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @s14
    JSR _bas_stmt_poke
    CLC
    RTS
@s14:
    ; Implicit assignment: var = expr
    LDA (bas_ip)
    CMP #'A'
    BCC @err
    CMP #'Z'+1
    BCS @err
    JSR _bas_stmt_assign
    CLC
    RTS
@err:
    LDA #<str_syntax
    LDX #>str_syntax
    JSR _acia_print_nl
    JSR _bas_go_end
    SEC
    RTS
@eol:
    CLC
    RTS

; ===========================================================
; Statement handlers
; ===========================================================

; --- PRINT ---
; PRINT["str"|expr] [;|,] ...
_bas_stmt_print:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    BEQ @pr_nl
@pr_item:
    LDA (bas_ip)
    BEQ @pr_nl
    CMP #'"'
    BNE @pr_expr
    INC bas_ip
    BNE @pr_sc
    INC bas_ip+1
@pr_sc:
@pr_str:
    LDA (bas_ip)
    BEQ @pr_after
    CMP #'"'
    BEQ @pr_qend
    JSR _acia_putc
    INC bas_ip
    BNE @pr_str
    INC bas_ip+1
    BRA @pr_str
@pr_qend:
    INC bas_ip
    BNE @pr_after
    INC bas_ip+1
    BRA @pr_after
@pr_expr:
    JSR _bas_expr
    JSR _bas_print_int
@pr_after:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    BEQ @pr_nl
    CMP #';'
    BEQ @pr_semi
    CMP #','
    BNE @pr_nl
    INC bas_ip
    BNE @pr_cm
    INC bas_ip+1
@pr_cm:
    LDA #' '
    JSR _acia_putc
    JSR _acia_putc
    JSR _bas_skip_spaces
    BRA @pr_item
@pr_semi:
    INC bas_ip
    BNE @pr_se
    INC bas_ip+1
@pr_se:
    JSR _bas_skip_spaces
    BRA @pr_item
@pr_nl:
    JMP _acia_put_newline

; --- INPUT ---
; INPUT ["prompt",] var
_bas_stmt_input:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #'"'
    BNE @inp_var
    INC bas_ip
    BNE @inp_pl
    INC bas_ip+1
@inp_pl:
@inp_ploop:
    LDA (bas_ip)
    BEQ @inp_pe
    CMP #'"'
    BEQ @inp_pe
    JSR _acia_putc
    INC bas_ip
    BNE @inp_ploop
    INC bas_ip+1
    BRA @inp_ploop
@inp_pe:
    LDA (bas_ip)
    CMP #'"'
    BNE @inp_var
    INC bas_ip
    BNE @inp_sk
    INC bas_ip+1
@inp_sk:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #','
    BNE @inp_var
    INC bas_ip
    BNE @inp_v2
    INC bas_ip+1
@inp_v2:
    JSR _bas_skip_spaces
@inp_var:
    LDA (bas_ip)
    CMP #'A'
    BCC @inp_err
    CMP #'Z'+1
    BCS @inp_err
    SEC
    SBC #'A'
    PHA   ; var_id
    INC bas_ip
    BNE @inp_rd
    INC bas_ip+1
@inp_rd:
    LDA #'?'
    JSR _acia_putc
    LDA #' '
    JSR _acia_putc
    JSR _bas_getline
    LDA #<bas_ibuf
    STA bas_ip
    LDA #>bas_ibuf
    STA bas_ip+1
    JSR _bas_parse_num      ; → bas_acc
    PLA
    JSR _bas_set_var
    RTS
@inp_err:
    LDA #<str_syntax
    LDX #>str_syntax
    JMP _acia_print_nl

; --- LET/implicit assignment: var = expr ---
_bas_stmt_assign:
    LDA (bas_ip)
    CMP #'A'
    BCC @aerr
    CMP #'Z'+1
    BCS @aerr
    SEC
    SBC #'A'
    PHA   ; var_id on stack
    INC bas_ip
    BNE @ask
    INC bas_ip+1
@ask:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #'='
    BNE @aerr2
    INC bas_ip
    BNE @aex
    INC bas_ip+1
@aex:
    JSR _bas_skip_spaces
    JSR _bas_expr
    PLA
    JMP _bas_set_var
@aerr2: PLA
@aerr:
    LDA #<str_syntax
    LDX #>str_syntax
    JMP _acia_print_nl

; --- IF: IF expr THEN lineno ---
_bas_stmt_if:
    JSR _bas_expr           ; condition → bas_acc
    ; Save condition
    LDA bas_acc
    PHA
    LDA bas_acc+1
    PHA
    JSR _bas_skip_spaces
    ; Skip optional THEN
    LDA #<kw_then
    STA bas_rhs
    LDA #>kw_then
    STA bas_rhs+1
    JSR _bas_check_kw
    JSR _bas_skip_spaces
    JSR _bas_parse_num      ; target line → bas_acc
    LDA bas_acc
    STA bas_tmp
    LDA bas_acc+1
    STA bas_tmp+1
    ; Restore condition
    PLA
    STA bas_acc+1
    PLA
    STA bas_acc
    ; If false → advance normally
    LDA bas_acc
    ORA bas_acc+1
    BEQ @if_false
    ; If true → find line
    JSR _bas_find_line
    BCC @if_jmp
    LDA #<str_undef
    LDX #>str_undef
    JSR _acia_print_nl
    JSR _bas_go_end
@if_jmp:
    SEC
    RTS
@if_false:
    CLC
    RTS

; --- FOR: FOR var = from TO to [STEP step] ---
_bas_stmt_for:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #'A'
    jcc @for_err
    CMP #'Z'+1
    jcs @for_err
    SEC
    SBC #'A'
    STA bas_tmp             ; var_id (lo); bas_tmp+1 unused
    INC bas_ip
    BNE @for_eq
    INC bas_ip+1
@for_eq:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #'='
    jne @for_err
    INC bas_ip
    BNE @for_fr
    INC bas_ip+1
@for_fr:
    JSR _bas_skip_spaces
    JSR _bas_expr   ; from → bas_acc
    LDA bas_tmp
    JSR _bas_set_var   ; var = from
    JSR _bas_skip_spaces
    ; TO
    LDA #<kw_to
    STA bas_rhs
    LDA #>kw_to
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @for_err
    JSR _bas_skip_spaces
    JSR _bas_expr   ; to → bas_acc
    LDA bas_acc
    STA bas_tmp2   ; save to in bas_tmp2
    LDA bas_acc+1
    STA bas_tmp2+1
    ; STEP (default 1)
    LDA #<kw_step
    STA bas_rhs
    LDA #>kw_step
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @for_defstep
    JSR _bas_skip_spaces
    JSR _bas_expr   ; step → bas_acc
    BRA @for_got_step
@for_defstep:
    LDA #1
    STA bas_acc
    STZ bas_acc+1
@for_got_step:
    ; Check stack overflow
    LDA bas_fsp
    CMP #BAS_MAX_FOR
    BCS @for_ov
    ; Compute offset = fsp * 7 (using *8 - *1)
    LDA bas_fsp
    ASL
    ASL
    ASL   ; *8
    SEC
    SBC bas_fsp   ; *7
    TAX
    ; Get body address = next line after FOR
    ; Save bas_lp, advance to next, save body, restore
    LDA bas_lp
    PHA
    LDA bas_lp+1
    PHA
    JSR _bas_next_line
    LDA bas_lp
    STA bas_rhs   ; body_lo (use bas_rhs as temp — safe: not in expr)
    LDA bas_lp+1
    STA bas_rhs+1   ; body_hi
    PLA
    STA bas_lp+1
    PLA
    STA bas_lp
    ; Push entry to bas_for_stk[X]
    LDA bas_tmp
    STA bas_for_stk,X   ; var_id
    LDA bas_tmp2
    STA bas_for_stk+1,X   ; to_lo
    LDA bas_tmp2+1
    STA bas_for_stk+2,X   ; to_hi
    LDA bas_acc
    STA bas_for_stk+3,X   ; step_lo
    LDA bas_acc+1
    STA bas_for_stk+4,X   ; step_hi
    LDA bas_rhs
    STA bas_for_stk+5,X   ; body_lo
    LDA bas_rhs+1
    STA bas_for_stk+6,X   ; body_hi
    INC bas_fsp
    CLC
    RTS   ; advance normally into body
@for_err:
    LDA #<str_syntax
    LDX #>str_syntax
    JSR _acia_print_nl
    CLC
    RTS
@for_ov:
    LDA #<str_for_ov
    LDX #>str_for_ov
    JSR _acia_print_nl
    CLC
    RTS

; --- NEXT ---
_bas_stmt_next:
    ; Skip optional var name (we always use top of stack)
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #'A'
    BCC @nx_check
    CMP #'Z'+1
    BCS @nx_check
    INC bas_ip
    BNE @nx_check
    INC bas_ip+1
@nx_check:
    LDA bas_fsp
    BEQ @nx_err
    ; Top-of-stack offset = (fsp-1)*7
    LDA bas_fsp
    DEA                 ; OPRAVA 4: DEC -> DEA (pro 65C02)
    STA bas_tmp         ; temp = fsp-1
    ASL
    ASL
    ASL                 ; temp*8
    SEC
    SBC bas_tmp         ; temp*8 - temp = temp*7
    TAX
    ; Load var_id, get current var value
    LDA bas_for_stk,X
    STA bas_tmp   ; var_id
    LDA bas_tmp
    ASL
    TAY
    LDA bas_vars,Y
    STA bas_acc
    LDA bas_vars+1,Y
    STA bas_acc+1
    ; Add step
    LDA bas_acc
    CLC
    ADC bas_for_stk+3,X
    STA bas_acc
    LDA bas_acc+1
    ADC bas_for_stk+4,X
    STA bas_acc+1
    ; Store new value
    LDA bas_tmp
    JSR _bas_set_var

    ; OPRAVA 3: Znaménkové porovnání mezí
    LDA bas_for_stk+4,X
    BMI @nx_neg_step

@nx_pos_step:
    ; Positive step: done if bas_acc > to (které znamená 'to < bas_acc')
    LDA bas_for_stk+1,X
    CMP bas_acc
    LDA bas_for_stk+2,X
    SBC bas_acc+1
    BVC @nx_ps_nv
    EOR #$80
@nx_ps_nv:
    BMI @nx_done
    BRA @nx_cont

@nx_neg_step:
    ; Negative step: done if bas_acc < to
    LDA bas_acc
    CMP bas_for_stk+1,X
    LDA bas_acc+1
    SBC bas_for_stk+2,X
    BVC @nx_ns_nv
    EOR #$80
@nx_ns_nv:
    BMI @nx_done

@nx_cont:
    ; Continue: jump to body
    LDA bas_for_stk+5,X
    STA bas_lp
    LDA bas_for_stk+6,X
    STA bas_lp+1
    SEC
    RTS
@nx_done:
    DEC bas_fsp
    CLC
    RTS
@nx_err:
    LDA #<str_next_wo
    LDX #>str_next_wo
    JSR _acia_print_nl
    CLC
    RTS

; --- WHILE: WHILE expr ---
_bas_stmt_while_fix:
    LDA bas_ip
    STA bas_tmp2
    LDA bas_ip+1
    STA bas_tmp2+1
    JSR _bas_expr
    LDA bas_acc
    ORA bas_acc+1
    BEQ @whlf_skip
    ; True: compute body lp
    LDA bas_wsp
    CMP #BAS_MAX_WHL
    BCS @whlf_ov
    LDA bas_lp
    PHA
    LDA bas_lp+1
    PHA
    JSR _bas_next_line       ; bas_lp → next line (body)
    LDA bas_lp
    STA bas_rhs
    LDA bas_lp+1
    STA bas_rhs+1   ; save body lp
    PLA
    STA bas_lp+1
    PLA
    STA bas_lp   ; restore WHILE lp
    ; Push entry
    LDA bas_wsp
    ASL
    ASL
    TAX
    LDA bas_tmp2
    STA bas_whl_stk,X
    LDA bas_tmp2+1
    STA bas_whl_stk+1,X
    LDA bas_rhs
    STA bas_whl_stk+2,X
    LDA bas_rhs+1
    STA bas_whl_stk+3,X
    INC bas_wsp
    CLC
    RTS   ; advance into body
@whlf_skip:
    JMP _bas_skip_to_wend
@whlf_ov:
    LDA #<str_whl_ov
    LDX #>str_whl_ov
    JSR _acia_print_nl
    CLC
    RTS

; --- WEND ---
_bas_stmt_wend:
    LDA bas_wsp
    BEQ @wend_err
    LDA bas_wsp
    DEA                 ; OPRAVA 4: DEC -> DEA (pro 65C02)
    ASL
    ASL
    TAX   ; offset = (wsp-1)*4
    ; Save current bas_ip, set to condition ptr
    LDA bas_ip
    PHA
    LDA bas_ip+1
    PHA
    LDA bas_whl_stk,X
    STA bas_ip
    LDA bas_whl_stk+1,X
    STA bas_ip+1
    JSR _bas_expr           ; re-evaluate condition → bas_acc
    PLA
    STA bas_ip+1
    PLA
    STA bas_ip
    LDA bas_acc
    ORA bas_acc+1
    BEQ @wend_false
    ; True: jump to body
    LDA bas_whl_stk+2,X
    STA bas_lp
    LDA bas_whl_stk+3,X
    STA bas_lp+1
    SEC
    RTS
@wend_false:
    DEC bas_wsp
    CLC
    RTS
@wend_err:
    LDA #<str_wend_wo
    LDX #>str_wend_wo
    JSR _acia_print_nl
    CLC
    RTS

; --- _bas_skip_to_wend: scan forward to matching WEND, set bas_lp after it ---
_bas_skip_to_wend:
    LDA #1
    STA bas_tmp   ; nesting depth
@stw_next:
    JSR _bas_next_line
    LDA (bas_lp)
    BNE @stw_chk
    LDY #1
    LDA (bas_lp),Y
    BEQ @stw_eof
@stw_chk:
    LDA bas_lp
    CLC
    ADC #2
    STA bas_ip
    LDA bas_lp+1
    ADC #0
    STA bas_ip+1
    JSR _bas_skip_spaces
    ; Check WHILE → depth++
    LDA #<kw_while
    STA bas_rhs
    LDA #>kw_while
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @stw_chk_wend
    INC bas_tmp
    BRA @stw_next
@stw_chk_wend:
    ; Re-setup bas_ip for WEND check (check_kw didn't match, bas_ip unchanged)
    LDA #<kw_wend
    STA bas_rhs
    LDA #>kw_wend
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @stw_next   ; not WEND
    DEC bas_tmp
    BNE @stw_next   ; depth>0, keep going
    ; Found matching WEND — advance past it
    JSR _bas_next_line
    SEC
    RTS
@stw_eof:
    LDA #<str_wend_wo
    LDX #>str_wend_wo
    JSR _acia_print_nl
    JSR _bas_go_end
    SEC
    RTS

; --- GOTO ---
_bas_stmt_goto:
    JSR _bas_skip_spaces
    JSR _bas_parse_num
    LDA bas_acc
    STA bas_tmp
    LDA bas_acc+1
    STA bas_tmp+1
    JSR _bas_find_line
    BCC @gt_ok
    LDA #<str_undef
    LDX #>str_undef
    JSR _acia_print_nl
    JSR _bas_go_end
@gt_ok:
    SEC
    RTS

; --- GOSUB ---
_bas_stmt_gosub:
    LDA bas_gsp
    CMP #BAS_MAX_GSB
    BCS @gsb_ov
    ; OPRAVA 1: Zpracujeme cílové číslo řádku jako první
    JSR _bas_skip_spaces
    JSR _bas_parse_num
    LDA bas_acc
    STA bas_tmp
    LDA bas_acc+1
    STA bas_tmp+1
    ; Compute and save return address
    LDA bas_lp
    PHA
    LDA bas_lp+1
    PHA
    JSR _bas_next_line                  ; bas_lp → return line
    LDA bas_gsp
    ASL
    TAX
    LDA bas_lp
    STA bas_gsb_stk,X
    LDA bas_lp+1
    STA bas_gsb_stk+1,X
    PLA
    STA bas_lp+1
    PLA
    STA bas_lp   ; restore for parse_num (doesn't need bas_lp)
    INC bas_gsp
    ; Provedeme skok
    JSR _bas_find_line
    BCC @gsb_ok
    LDA #<str_undef
    LDX #>str_undef
    JSR _acia_print_nl
    JSR _bas_go_end
@gsb_ok:
    SEC
    RTS
@gsb_ov:
    LDA #<str_gsb_ov
    LDX #>str_gsb_ov
    JSR _acia_print_nl
    CLC
    RTS

; --- RETURN ---
_bas_stmt_return:
    LDA bas_gsp
    BEQ @ret_err
    DEC bas_gsp
    LDA bas_gsp
    ASL
    TAX
    LDA bas_gsb_stk,X
    STA bas_lp
    LDA bas_gsb_stk+1,X
    STA bas_lp+1
    SEC
    RTS
@ret_err:
    LDA #<str_ret_wo
    LDX #>str_ret_wo
    JSR _acia_print_nl
    CLC
    RTS

; --- END ---
_bas_stmt_end:
    JSR _bas_go_end
    SEC
    RTS

; --- POKE addr, val ---
_bas_stmt_poke:
    JSR _bas_expr           ; address → bas_acc
    LDA bas_acc
    STA bas_tmp
    LDA bas_acc+1
    STA bas_tmp+1
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #','
    BNE @pk_err
    INC bas_ip
    BNE @pk_v
    INC bas_ip+1
@pk_v:
    JSR _bas_skip_spaces
    JSR _bas_expr   ; value → bas_acc
    LDA bas_acc
    STA (bas_tmp)
    RTS
@pk_err:
    LDA #<str_syntax
    LDX #>str_syntax
    JMP _acia_print_nl

; ============================================================
; Expression evaluator
; ============================================================

; Level 0: comparisons =, <>, <, >, <=, >=
_bas_expr:
    JSR _bas_addsub
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #'='
    BNE @chk_lt
       ; == : save left, eval right, compare
    LDA bas_acc
    PHA
    LDA bas_acc+1
    PHA
    INC bas_ip
    BNE @ceq_r
    INC bas_ip+1
@ceq_r:
    JSR _bas_skip_spaces
    JSR _bas_addsub
    PLA
    STA bas_rhs+1
    PLA
    STA bas_rhs
    LDA bas_rhs
    CMP bas_acc
    jne _bas_cmp_false
    LDA bas_rhs+1
    CMP bas_acc+1
    jne _bas_cmp_false
    JMP _bas_cmp_true
@chk_lt:
    CMP #'<'
    jne @chk_gt
    INC bas_ip
    BNE @clt_ok
    INC bas_ip+1
@clt_ok:
    LDA (bas_ip)
    CMP #'>'
    BEQ @cne
    CMP #'='
    BEQ @clte
    ; pure <
    JSR _bas_skip_spaces
    LDA bas_acc
    PHA
    LDA bas_acc+1
    PHA
    JSR _bas_addsub
    PLA
    STA bas_rhs+1
    PLA
    STA bas_rhs   ; rhs=left, acc=right
    ; left < right?  i.e. rhs < acc
    LDA bas_rhs
    CMP bas_acc
    LDA bas_rhs+1
    SBC bas_acc+1
    BVC @clt_nv
    EOR #$80
@clt_nv:
    jmi _bas_cmp_true
    JMP _bas_cmp_false
@cne:
    INC bas_ip
    BNE @cne_r
    INC bas_ip+1
@cne_r:
    JSR _bas_skip_spaces
    LDA bas_acc
    PHA
    LDA bas_acc+1
    PHA
    JSR _bas_addsub
    PLA
    STA bas_rhs+1
    PLA
    STA bas_rhs
    LDA bas_rhs
    CMP bas_acc
    jne _bas_cmp_true
    LDA bas_rhs+1
    CMP bas_acc+1
    jne _bas_cmp_true
    JMP _bas_cmp_false
@clte:
    INC bas_ip
    BNE @clte_r
    INC bas_ip+1
@clte_r:
    JSR _bas_skip_spaces
    LDA bas_acc
    PHA
    LDA bas_acc+1
    PHA
    JSR _bas_addsub
    PLA
    STA bas_rhs+1
    PLA
    STA bas_rhs
    ; left <= right? i.e. NOT (left > right)
    LDA bas_acc
    CMP bas_rhs
    LDA bas_acc+1
    SBC bas_rhs+1
    BVC @clte_nv
    EOR #$80
@clte_nv:
    jmi _bas_cmp_false
    JMP _bas_cmp_true   ; right < left → false; right >= left → true
@chk_gt:
    CMP #'>'
    BNE @no_cmp
    INC bas_ip
    BNE @cgt_ok
    INC bas_ip+1
@cgt_ok:
    LDA (bas_ip)
    CMP #'='
    BEQ @cgte
    ; pure >
    JSR _bas_skip_spaces
    LDA bas_acc
    PHA
    LDA bas_acc+1
    PHA
    JSR _bas_addsub
    PLA
    STA bas_rhs+1
    PLA
    STA bas_rhs
    ; left > right? i.e. rhs > acc  where rhs=left, acc=right
    LDA bas_acc
    CMP bas_rhs
    LDA bas_acc+1
    SBC bas_rhs+1
    BVC @cgt_nv
    EOR #$80
@cgt_nv:
    jmi _bas_cmp_true
    JMP _bas_cmp_false
@cgte:
    INC bas_ip
    BNE @cgte_r
    INC bas_ip+1
@cgte_r:
    JSR _bas_skip_spaces
    LDA bas_acc
    PHA
    LDA bas_acc+1
    PHA
    JSR _bas_addsub
    PLA
    STA bas_rhs+1
    PLA
    STA bas_rhs
    ; left >= right? i.e. NOT (left < right)
    LDA bas_rhs
    CMP bas_acc
    LDA bas_rhs+1
    SBC bas_acc+1
    BVC @cgte_nv
    EOR #$80
@cgte_nv:
    jmi _bas_cmp_false
    JMP _bas_cmp_true
@no_cmp:
    RTS
_bas_cmp_true:
    LDA #1
    STA bas_acc
    STZ bas_acc+1
    RTS
_bas_cmp_false:
    LDA #0
    STA bas_acc
    STA bas_acc+1
    RTS

; Level 1: add/subtract
_bas_addsub:
    JSR _bas_muldiv
@as_loop:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #'+'
    BEQ @as_add
    CMP #'-'
    BEQ @as_sub
    RTS
@as_add:
    INC bas_ip
    BNE @as_ar
    INC bas_ip+1
@as_ar:
    JSR _bas_skip_spaces
    LDA bas_acc
    PHA
    LDA bas_acc+1
    PHA
    JSR _bas_muldiv
    PLA
    STA bas_rhs+1
    PLA
    STA bas_rhs
    LDA bas_rhs
    CLC
    ADC bas_acc
    STA bas_acc
    LDA bas_rhs+1
    ADC bas_acc+1
    STA bas_acc+1
    BRA @as_loop
@as_sub:
    INC bas_ip
    BNE @as_sr
    INC bas_ip+1
@as_sr:
    JSR _bas_skip_spaces
    LDA bas_acc
    PHA
    LDA bas_acc+1
    PHA
    JSR _bas_muldiv
    PLA
    STA bas_rhs+1
    PLA
    STA bas_rhs
    LDA bas_rhs
    SEC
    SBC bas_acc
    STA bas_acc
    LDA bas_rhs+1
    SBC bas_acc+1
    STA bas_acc+1
    BRA @as_loop

; Level 2: multiply/divide
_bas_muldiv:
    JSR _bas_primary
@md_loop:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #'*'
    BEQ @md_mul
    CMP #'/'
    BEQ @md_div
    RTS
@md_mul:
    INC bas_ip
    BNE @md_mr
    INC bas_ip+1
@md_mr:
    JSR _bas_skip_spaces
    LDA bas_acc
    PHA
    LDA bas_acc+1
    PHA
    JSR _bas_primary
    LDA bas_acc
    STA bas_tmp
    LDA bas_acc+1
    STA bas_tmp+1
    PLA
    STA bas_acc+1
    PLA
    STA bas_acc
    JSR _bas_mul16
    BRA @md_loop
@md_div:
    INC bas_ip
    BNE @md_dr
    INC bas_ip+1
@md_dr:
    JSR _bas_skip_spaces
    LDA bas_acc
    PHA
    LDA bas_acc+1
    PHA
    JSR _bas_primary
    LDA bas_acc
    STA bas_tmp
    LDA bas_acc+1
    STA bas_tmp+1
    PLA
    STA bas_acc+1
    PLA
    STA bas_acc
    JSR _bas_div16
    BRA @md_loop

; Level 3: primary
_bas_primary:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    ; Unary minus
    CMP #'-'
    BNE @pr_not_neg
    INC bas_ip
    BNE @pr_neg
    INC bas_ip+1
@pr_neg:
    JSR _bas_primary
    LDA #0
    SEC
    SBC bas_acc
    STA bas_acc
    LDA #0
    SBC bas_acc+1
    STA bas_acc+1
    RTS
@pr_not_neg:
    ; Parenthesis
    CMP #'('
    BNE @pr_not_paren
    INC bas_ip
    BNE @pr_pe
    INC bas_ip+1
@pr_pe:
    JSR _bas_expr
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #')'
    BNE @pr_pok
    INC bas_ip
    BNE @pr_pok
    INC bas_ip+1
@pr_pok:
    RTS
@pr_not_paren:
    ; PEEK
    LDA #<kw_peek
    STA bas_rhs
    LDA #>kw_peek
    STA bas_rhs+1
    JSR _bas_check_kw
    BCS @pr_not_peek
    LDA (bas_ip)
    CMP #'('
    BNE @pr_peek_e
    INC bas_ip
    BNE @pr_pk
    INC bas_ip+1
@pr_pk:
    JSR _bas_expr
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #')'
    BNE @pr_peek_e
    INC bas_ip
    BNE @pr_pk2
    INC bas_ip+1
@pr_pk2:
    LDA bas_acc
    STA bas_tmp
    LDA bas_acc+1
    STA bas_tmp+1
    LDA (bas_tmp)
    STA bas_acc
    STZ bas_acc+1
    RTS
@pr_peek_e:
    LDA #<str_syntax
    LDX #>str_syntax
    JSR _acia_print_nl
    STZ bas_acc
    STZ bas_acc+1
    RTS
@pr_not_peek:
    ; Variable A-Z
    LDA (bas_ip)        ; reload: _bas_check_kw clobbers A
    CMP #'A'
    BCC @pr_num
    CMP #'Z'+1
    BCS @pr_num
    SEC
    SBC #'A'
    INC bas_ip
    BNE @pr_var
    INC bas_ip+1
@pr_var:
    JMP _bas_get_var_by_id  ; tail call
@pr_num:
    JMP _bas_parse_num

; ============================================================
; _bas_parse_num — parse decimal (or $hex) integer at bas_ip → bas_acc
; ============================================================
_bas_parse_num:
    STZ bas_acc
    STZ bas_acc+1
    LDA (bas_ip)
    CMP #'$'
    BEQ _bas_parse_hex
@pn:
    LDA (bas_ip)
    CMP #'0'
    BCC @pn_done
    CMP #'9'+1
    BCS @pn_done
    SEC
    SBC #'0'
    PHA
    ; acc * 10 = acc*8 + acc*2
    ASL bas_acc
    ROL bas_acc+1   ; *2
    LDA bas_acc
    STA bas_tmp
    LDA bas_acc+1
    STA bas_tmp+1
    ASL bas_acc
    ROL bas_acc+1   ; *4
    ASL bas_acc
    ROL bas_acc+1   ; *8
    LDA bas_acc
    CLC
    ADC bas_tmp
    STA bas_acc
    LDA bas_acc+1
    ADC bas_tmp+1
    STA bas_acc+1   ; *10
    PLA
    CLC
    ADC bas_acc
    STA bas_acc
    BCC @pn_ni
    INC bas_acc+1
@pn_ni:
    INC bas_ip
    BNE @pn
    INC bas_ip+1
    BRA @pn
@pn_done: RTS

; ============================================================
; _bas_parse_hex — parse $XXXX hex literal at bas_ip → bas_acc
; Called from _bas_parse_num when '$' detected; bas_acc already zero
; ============================================================
_bas_parse_hex:
    INC bas_ip          ; skip '$'
    BNE @ph_loop
    INC bas_ip+1
@ph_loop:
    LDA (bas_ip)
    CMP #'0'
    BCC @ph_done
    CMP #'9'+1
    BCC @ph_digit
    CMP #'A'
    BCC @ph_done
    CMP #'F'+1
    BCS @ph_done
    SEC
    SBC #'A'-10         ; A-F → 10-15
    BRA @ph_got
@ph_digit:
    SEC
    SBC #'0'            ; 0-9 → 0-9
@ph_got:
    PHA
    ASL bas_acc         ; acc <<= 4
    ROL bas_acc+1
    ASL bas_acc
    ROL bas_acc+1
    ASL bas_acc
    ROL bas_acc+1
    ASL bas_acc
    ROL bas_acc+1
    PLA
    CLC
    ADC bas_acc
    STA bas_acc
    BCC @ph_ni
    INC bas_acc+1
@ph_ni:
    INC bas_ip
    BNE @ph_loop
    INC bas_ip+1
    BRA @ph_loop
@ph_done: RTS

; ============================================================
; Variable helpers
; ============================================================
_bas_get_var_by_id:     ; A = var index 0-25 → bas_acc
    ASL
    TAX
    LDA bas_vars,X
    STA bas_acc
    LDA bas_vars+1,X
    STA bas_acc+1
    RTS

_bas_set_var:           ; A = var index 0-25, store bas_acc
    ASL
    TAX
    LDA bas_acc
    STA bas_vars,X
    LDA bas_acc+1
    STA bas_vars+1,X
    RTS

; ============================================================
; _bas_print_int — signed decimal from bas_acc
; ============================================================
_bas_print_int:
    LDA bas_acc+1
    BPL _bas_print_uint
    LDA #'-'
    JSR _acia_putc
    LDA #0
    SEC
    SBC bas_acc
    STA bas_acc
    LDA #0
    SBC bas_acc+1
    STA bas_acc+1
    ; fall through

; ============================================================
; _bas_print_uint — unsigned decimal from bas_acc
; ============================================================
_bas_print_uint:
    ; Copy to bas_tmp for digit extraction (preserves bas_acc)
    LDA bas_acc
    STA bas_tmp
    LDA bas_acc+1
    STA bas_tmp+1
    LDX #0
@pu_loop:
    JSR _bas_div10_tmp      ; bas_tmp /= 10, remainder → A
    PHA
    INX
    LDA bas_tmp
    ORA bas_tmp+1
    BNE @pu_loop
@pu_print:
    PLA
    ORA #'0'
    JSR _acia_putc
    DEX
    BNE @pu_print
    RTS

; _bas_div10_tmp — bas_tmp / 10 → quotient in bas_tmp, remainder in A
; Uses bas_rhs as work area. Does NOT touch bas_acc.
_bas_div10_tmp:
    PHX
    STZ bas_rhs
    STZ bas_rhs+1
    LDX #16
@dt:
    ASL bas_tmp
    ROL bas_tmp+1
    ROL bas_rhs
    ROL bas_rhs+1
    LDA bas_rhs
    CMP #10
    LDA bas_rhs+1
    SBC #0
    BCC @dt_no
    LDA bas_rhs
    SEC
    SBC #10
    STA bas_rhs
    BCS @dt_hi
    DEC bas_rhs+1
@dt_hi:
    INC bas_tmp
    BNE @dt_no
    INC bas_tmp+1
@dt_no: DEX
BNE @dt
    LDA bas_rhs
    PLX
    RTS   ; remainder

; ============================================================
; _bas_mul16 — bas_acc × bas_tmp → bas_acc (low 16 bits)
; ============================================================
_bas_mul16:
    LDA #0
    STA bas_rhs
    STA bas_rhs+1
    LDX #16
@ml:
    LSR bas_tmp+1
    ROR bas_tmp
    BCC @ml_no
    LDA bas_rhs
    CLC
    ADC bas_acc
    STA bas_rhs
    LDA bas_rhs+1
    ADC bas_acc+1
    STA bas_rhs+1
@ml_no:
    ASL bas_acc
    ROL bas_acc+1
    DEX
    BNE @ml
    LDA bas_rhs
    STA bas_acc
    LDA bas_rhs+1
    STA bas_acc+1
    RTS

; ============================================================
; _bas_div16 — bas_acc / bas_tmp → quotient in bas_acc
; OPRAVA 2: Dělení nyní podporuje znaménka (Signed Division)
; ============================================================
_bas_div16:
    LDA bas_tmp
    ORA bas_tmp+1
    BNE @dv_chk_sign
    LDA #<str_divz
    LDX #>str_divz
    JSR _acia_print_nl
    STZ bas_acc
    STZ bas_acc+1
    RTS
@dv_chk_sign:
    ; Výsledné znaménko schováme na zásobník (XOR obou hodnot)
    LDA bas_acc+1
    EOR bas_tmp+1
    PHA

    ; Absolutní hodnota (bas_acc)
    LDA bas_acc+1
    BPL @dv_acc_pos
    LDA #0
    SEC
    SBC bas_acc
    STA bas_acc
    LDA #0
    SBC bas_acc+1
    STA bas_acc+1
@dv_acc_pos:

    ; Absolutní hodnota (bas_tmp)
    LDA bas_tmp+1
    BPL @dv_tmp_pos
    LDA #0
    SEC
    SBC bas_tmp
    STA bas_tmp
    LDA #0
    SBC bas_tmp+1
    STA bas_tmp+1
@dv_tmp_pos:

    ; Vlastní Unsigned dělení
    LDA #0
    STA bas_rhs
    STA bas_rhs+1
    LDX #16
@dv:
    ASL bas_acc
    ROL bas_acc+1
    ROL bas_rhs
    ROL bas_rhs+1
    LDA bas_rhs
    CMP bas_tmp
    LDA bas_rhs+1
    SBC bas_tmp+1
    BCC @dv_no
    LDA bas_rhs
    SEC
    SBC bas_tmp
    STA bas_rhs
    LDA bas_rhs+1
    SBC bas_tmp+1
    STA bas_rhs+1
    INC bas_acc
    BNE @dv_no
    INC bas_acc+1
@dv_no:
    DEX
    BNE @dv

    ; Obnova znaménka výsledku ze zásobníku
    PLA
    BPL @dv_done
    LDA #0
    SEC
    SBC bas_acc
    STA bas_acc
    LDA #0
    SBC bas_acc+1
    STA bas_acc+1
@dv_done:
    RTS

; ============================================================
; Program management helpers
; ============================================================
_bas_go_end:
    LDA bas_ep
    STA bas_lp
    LDA bas_ep+1
    STA bas_lp+1
    RTS

_bas_find_line:             ; find bas_tmp line → bas_lp, C=0 found
    LDA #<BAS_START
    STA bas_lp
    LDA #>BAS_START
    STA bas_lp+1
@fl:
    LDA (bas_lp)
    BNE @fl_chk
    LDY #1
    LDA (bas_lp),Y
    BEQ @fl_no   ; sentinel
@fl_chk:
    LDA (bas_lp)
    CMP bas_tmp
    BNE @fl_nx
    LDY #1
    LDA (bas_lp),Y
    CMP bas_tmp+1
    BEQ @fl_yes
@fl_nx:
    JSR _bas_next_line
    BRA @fl
@fl_yes: CLC
RTS
@fl_no:  SEC
RTS

; ============================================================
; _bas_store_line — store/replace line from bas_ibuf
; bas_ibuf: decimal line number then text
; ============================================================
_bas_store_line:
    LDA #<bas_ibuf
    STA bas_ip
    LDA #>bas_ibuf
    STA bas_ip+1
    JSR _bas_parse_num                  ; line number → bas_acc
    LDA bas_acc
    STA bas_lnum
    LDA bas_acc+1
    STA bas_lnum+1
    JSR _bas_skip_spaces                ; skip spaces after number → bas_ip = text start

    ; _bas_find_line clobbers bas_ip (via _bas_next_line) — save it first
    LDA bas_ip
    PHA
    LDA bas_ip+1
    PHA
    ; Delete existing line with same number
    LDA bas_lnum
    STA bas_tmp
    LDA bas_lnum+1
    STA bas_tmp+1
    JSR _bas_find_line
    BCS @sl_no_del
    JSR _bas_del_at_lp                  ; removes line at bas_lp, updates bas_ep
@sl_no_del:
    PLA
    STA bas_ip+1
    PLA
    STA bas_ip                          ; restore text pointer in bas_ibuf
    ; If no text remains, just delete (bare line number = delete)
    LDA bas_ip
    STA bas_rhs
    LDA bas_ip+1
    STA bas_rhs+1
    LDA (bas_ip)
    jeq @sl_done

    ; Compute new_line_size = 2 + strlen(text) + 1
    LDY #0
@sl_len:
    LDA (bas_ip),Y
    BEQ @sl_len_done
    INY
    BRA @sl_len
@sl_len_done:
    INY
    INY
    INY   ; +2 lnum, +1 NUL
    TYA
    STA bas_tmp   ; size in bas_tmp (1 byte, max ~82)
    STZ bas_tmp+1

    ; Check space
    LDA bas_ep
    CLC
    ADC bas_tmp
    STA bas_acc
    LDA bas_ep+1
    ADC bas_tmp+1
    STA bas_acc+1
    LDA bas_acc+1
    CMP #>BAS_MAXEND
    jcs @sl_full
    LDA bas_acc+1
    CMP #>BAS_MAXEND
    jne @sl_fit
    LDA bas_acc
    CMP #<BAS_MAXEND
    jcs @sl_full
@sl_fit:
    ; Find insertion point (sorted): first line with lnum >= bas_lnum
    LDA #<BAS_START
    STA bas_lp
    LDA #>BAS_START
    STA bas_lp+1
@sl_find:
    LDA (bas_lp)
    BNE @sl_fi_chk
    LDY #1
    LDA (bas_lp),Y
    BEQ @sl_ins   ; sentinel
@sl_fi_chk:
    ; Compare bas_lp line number vs bas_lnum
    LDA (bas_lp)
    CMP bas_lnum
    BCC @sl_fi_next   ; this line < target: skip
    BNE @sl_ins                                       ; this line > target: insert here
    LDY #1
    LDA (bas_lp),Y
    CMP bas_lnum+1
    BCS @sl_ins
@sl_fi_next:
    JSR _bas_next_line
    BRA @sl_find
@sl_ins:
    ; bas_lp = insertion point
    ; Shift bytes from [bas_lp .. bas_ep+1] forward by bas_tmp bytes (reverse copy)
    ; Count to move = bas_ep - bas_lp + 2 (sentinel is 2 bytes past bas_ep-1)
    ; Actually bas_ep points to first byte of sentinel (=0x00), so move [bas_lp..bas_ep+1]
    ; count = bas_ep - bas_lp + 2
    LDA bas_ep
    SEC
    SBC bas_lp
    STA bas_rhs
    LDA bas_ep+1
    SBC bas_lp+1
    STA bas_rhs+1
    LDA bas_rhs
    CLC
    ADC #2
    STA bas_rhs
    BCC @sl_mv
    INC bas_rhs+1
@sl_mv:
    ; src = bas_lp + count - 1  (high end of block)
    ; dst = src + bas_tmp
    LDA bas_lp
    CLC
    ADC bas_rhs
    STA bas_tmp2
    LDA bas_lp+1
    ADC bas_rhs+1
    STA bas_tmp2+1
    LDA bas_tmp2        ; proper 16-bit decrement (DEC doesn't affect carry)
    BNE @sl_dec_lo
    DEC bas_tmp2+1
@sl_dec_lo:
    DEC bas_tmp2        ; src = bas_lp+count-1
    ; dst = bas_tmp2 + bas_tmp (note bas_tmp2 used as src ptr, bas_acc as dst ptr)
    LDA bas_tmp2
    CLC
    ADC bas_tmp
    STA bas_acc
    LDA bas_tmp2+1
    ADC bas_tmp+1
    STA bas_acc+1
    ; Reverse copy: count bytes from src downward to dst
    ; Simple loop: copy bas_rhs (16-bit) bytes from bas_tmp2 to bas_acc, decrement both, decrement count
@sl_copy:
    LDA bas_rhs
    ORA bas_rhs+1
    BEQ @sl_copy_done
    ; Count-1 is already in bas_rhs after the loop
    LDA (bas_tmp2)
    STA (bas_acc)
    LDA bas_tmp2
    BNE @sl_ds
    DEC bas_tmp2+1
@sl_ds: DEC bas_tmp2
    LDA bas_acc
    BNE @sl_dd
    DEC bas_acc+1
@sl_dd: DEC bas_acc
    LDA bas_rhs
    BNE @sl_dc
    DEC bas_rhs+1
@sl_dc: DEC bas_rhs
    BRA @sl_copy
@sl_copy_done:
    ; Save line size — _bas_parse_num below clobbers bas_tmp
    LDA bas_tmp
    PHA
    ; Re-point bas_ip to bas_ibuf text (after line number + spaces)
    LDA #<bas_ibuf
    STA bas_ip
    LDA #>bas_ibuf
    STA bas_ip+1
    JSR _bas_parse_num
    JSR _bas_skip_spaces
    ; Write at bas_lp
    LDY #0
    LDA bas_lnum
    STA (bas_lp),Y
    INY
    LDA bas_lnum+1
    STA (bas_lp),Y
    INY
@sl_wtext:
    LDA (bas_ip)
    STA (bas_lp),Y
    BEQ @sl_wdone
    INC bas_ip
    BNE @sl_wnxt
    INC bas_ip+1
@sl_wnxt: INY
BRA @sl_wtext
@sl_wdone:
    ; Update bas_ep — restore line size saved before re-parse
    PLA
    STA bas_tmp
    LDA bas_ep
    CLC
    ADC bas_tmp
    STA bas_ep
    BCC @sl_done
    INC bas_ep+1
@sl_done: RTS
@sl_full:
    LDA #<str_pfull
    LDX #>str_pfull
    JMP _acia_print_nl

; ============================================================
; _bas_del_at_lp — delete line at bas_lp, update bas_ep
; Uses bas_tmp2 as src ptr, bas_rhs as count (forward copy)
; ============================================================
_bas_del_at_lp:
    ; Compute line size (2 + strlen + 1)
    LDA bas_lp
    CLC
    ADC #2
    STA bas_tmp2
    LDA bas_lp+1
    ADC #0
    STA bas_tmp2+1
@dl_scan:
    LDA (bas_tmp2)
    BEQ @dl_scan_done
    INC bas_tmp2
    BNE @dl_scan
    INC bas_tmp2+1
    BRA @dl_scan
@dl_scan_done:
    INC bas_tmp2
    BNE @dl_s2
    INC bas_tmp2+1   ; past NUL → src = next line
@dl_s2:
    ; line_size = bas_tmp2 - bas_lp
    LDA bas_tmp2
    SEC
    SBC bas_lp
    STA bas_rhs
    LDA bas_tmp2+1
    SBC bas_lp+1
    STA bas_rhs+1
    ; Count to copy = bas_ep - bas_tmp2 + 2 (sentinel)
    LDA bas_ep
    SEC
    SBC bas_tmp2
    STA bas_acc
    LDA bas_ep+1
    SBC bas_tmp2+1
    STA bas_acc+1
    LDA bas_acc
    CLC
    ADC #2
    STA bas_acc
    BCC @dl_copy
    INC bas_acc+1
@dl_copy:
    ; Forward copy: bas_tmp2 → bas_lp, bas_acc bytes
    LDA bas_acc
    ORA bas_acc+1
    BEQ @dl_done
    LDA (bas_tmp2)
    STA (bas_lp)
    INC bas_tmp2
    BNE @dl_nt
    INC bas_tmp2+1
@dl_nt:
    INC bas_lp
    BNE @dl_nl
    INC bas_lp+1
@dl_nl:
    LDA bas_acc
    BNE @dl_dc
    DEC bas_acc+1
@dl_dc: DEC bas_acc
BRA @dl_copy
@dl_done:
    ; Subtract line_size from bas_ep
    LDA bas_ep
    SEC
    SBC bas_rhs
    STA bas_ep
    LDA bas_ep+1
    SBC bas_rhs+1
    STA bas_ep+1
    ; Restore bas_lp (was advanced during copy — restore to original = bas_ep)
    ; Actually bas_lp was advanced to the position of old next line,
    ; which is now at the deletion point. Caller doesn't rely on bas_lp value.
    RTS

; ============================================================
; SAVE — SAVE "filename"
; ============================================================
_bas_cmd_save:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #'"'
    BNE @sv_err
    INC bas_ip
    BNE @sv_fn
    INC bas_ip+1
@sv_fn:
    LDY #0
@sv_nm:
    LDA (bas_ip)
    BEQ @sv_ne
    CMP #'"'
    BEQ @sv_ne
    CPY #8
    BCS @sv_skip_nm
    STA bas_ibuf,Y
    INY
    INC bas_ip
    BNE @sv_nm
    INC bas_ip+1
    BRA @sv_nm
@sv_skip_nm:
    INC bas_ip
    BNE @sv_nm
    INC bas_ip+1
    BRA @sv_nm
@sv_ne:
    LDA #0
    STA bas_ibuf,Y
    ; size = (bas_ep - BAS_START) + 2  [includes sentinel]
    LDA bas_ep
    SEC
    SBC #<BAS_START
    STA rd_size_lo
    LDA bas_ep+1
    SBC #>BAS_START
    STA rd_size_hi
    LDA rd_size_lo
    CLC
    ADC #2
    STA rd_size_lo
    BCC @sv_sz
    INC rd_size_hi
@sv_sz:
    LDA #<bas_ibuf
    STA os_ptr
    LDA #>bas_ibuf
    STA os_ptr+1
    LDA #<BAS_START
    STA rd_src
    LDA #>BAS_START
    STA rd_src+1
    LDA #<BAS_START
    STA os_arg0
    LDA #>BAS_START
    STA os_arg1
    LDA #RDF_VALID
    STA rd_tmp
    JSR _rd_save
    BCS @sv_err
    LDA #<str_saved
    LDX #>str_saved
    JMP _acia_print_nl
@sv_err:
    LDA #<str_sv_err
    LDX #>str_sv_err
    JMP _acia_print_nl

; ============================================================
; LOAD — LOAD "filename"
; ============================================================
_bas_cmd_load:
    JSR _bas_skip_spaces
    LDA (bas_ip)
    CMP #'"'
    jne @ld_err
    INC bas_ip
    BNE @ld_fn
    INC bas_ip+1
@ld_fn:
    LDY #0
@ld_nm:
    LDA (bas_ip)
    BEQ @ld_ne
    CMP #'"'
    BEQ @ld_ne
    CPY #8
    BCS @ld_skip
    STA bas_ibuf,Y
    INY
    INC bas_ip
    BNE @ld_nm
    INC bas_ip+1
    BRA @ld_nm
@ld_skip:
    INC bas_ip
    BNE @ld_nm
    INC bas_ip+1
    BRA @ld_nm
@ld_ne:
    LDA #0
    STA bas_ibuf,Y
    LDA #<bas_ibuf
    STA os_ptr
    LDA #>bas_ibuf
    STA os_ptr+1
    JSR _rd_find
    BCS @ld_nf
    ; Entry address = RD_DIR + rd_idx * 16
    LDA rd_idx
    ASL
    ASL
    ASL
    ASL
    CLC
    ADC #<RD_DIR
    STA rd_ptr
    LDA #>RD_DIR
    ADC #0
    STA rd_ptr+1
    LDY #10
    LDA (rd_ptr),Y
    STA rd_size_lo
    LDY #11
    LDA (rd_ptr),Y
    STA rd_size_hi
    LDY #13
    LDA (rd_ptr),Y
    STA rd_src
    LDY #14
    LDA (rd_ptr),Y
    STA rd_src+1
    LDA #<BAS_START
    STA rd_dst
    LDA #>BAS_START
    STA rd_dst+1
    JSR _rd_memcpy
    ; Update bas_ep = BAS_START + size - 2
    LDA #<BAS_START
    CLC
    ADC rd_size_lo
    STA bas_ep
    LDA #>BAS_START
    ADC rd_size_hi
    STA bas_ep+1
    LDA bas_ep
    SEC
    SBC #2
    STA bas_ep
    BCS @ld_ep
    DEC bas_ep+1
@ld_ep:
    STZ bas_fsp
    STZ bas_gsp
    STZ bas_wsp
    LDA #<str_loaded
    LDX #>str_loaded
    JMP _acia_print_nl
@ld_nf:
    LDA #<str_notfnd
    LDX #>str_notfnd
    JMP _acia_print_nl
@ld_err:
    LDA #<str_syntax
    LDX #>str_syntax
    JMP _acia_print_nl

; ============================================================
; OS ZP imports
; ============================================================
.importzp os_arg0, os_arg1, os_ptr
.importzp rd_ptr, rd_idx, rd_tmp
.importzp rd_src, rd_dst, rd_size_lo, rd_size_hi

; ============================================================
; RODATA — strings and keywords
; ============================================================
.segment "RODATA"

str_bas_banner: .byte "P65 BASIC v1.0",0
str_bas_hint:   .byte "NEW LIST RUN SAVE LOAD BYE",0
str_bas_prompt: .byte "BASIC> ",0
str_ok:         .byte "OK",0
str_ready:      .byte "Ready.",0
str_syntax:     .byte "?SYNTAX ERROR",0
str_undef:      .byte "?UNDEFINED LINE",0
str_for_ov:     .byte "?FOR OVF",0
str_next_wo:    .byte "?NEXT WO FOR",0
str_whl_ov:     .byte "?WHILE OVF",0
str_wend_wo:    .byte "?WEND WO WHILE",0
str_gsb_ov:     .byte "?GOSUB OVF",0
str_ret_wo:     .byte "?RET WO GOSUB",0
str_divz:       .byte "?DIV/0",0
str_pfull:      .byte "?PROG FULL",0
str_saved:      .byte "Saved.",0
str_sv_err:     .byte "?Save err.",0
str_loaded:     .byte "OK",0
str_notfnd:     .byte "?Not found.",0

kw_new:    .byte "NEW",0
kw_list:   .byte "LIST",0
kw_run:    .byte "RUN",0
kw_save:   .byte "SAVE",0
kw_load:   .byte "LOAD",0
kw_bye:    .byte "BYE",0
kw_rem:    .byte "REM",0
kw_print:  .byte "PRINT",0
kw_input:  .byte "INPUT",0
kw_let:    .byte "LET",0
kw_if:     .byte "IF",0
kw_then:   .byte "THEN",0
kw_for:    .byte "FOR",0
kw_to:     .byte "TO",0
kw_step:   .byte "STEP",0
kw_next:   .byte "NEXT",0
kw_while:  .byte "WHILE",0
kw_wend:   .byte "WEND",0
kw_goto:   .byte "GOTO",0
kw_gosub:  .byte "GOSUB",0
kw_return: .byte "RETURN",0
kw_end:    .byte "END",0
kw_poke:   .byte "POKE",0
kw_peek:   .byte "PEEK",0