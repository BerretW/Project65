SAA_DATA    = $C400
SAA_REG     = $C401

;;Register map of SAA1099
AM0         = $0
AM1         = $1
AM2         = $2
AM3         = $3
AM4         = $4
AM5         = $5

FQ0         = $8
FQ1         = $9
FQ2         = $A
FQ3         = $B
FQ4         = $C
FQ5         = $D

OC10        = $10
OC32        = $11
OC54        = $12

FQE         = $14
NOE         = $15
NOG10       = $16

ENVG0       = $18
ENVG1       = $19

SOE         = $1C

.setcpu		"65C02"
.smart		on
.autoimport	on
.case		on
.debuginfo	off
.importzp	sp, sreg, regsave, regbank, _in_char , BANK_BASE, TQ, B
.importzp	tmp1, tmp2, tmp3, tmp4, ptr1, ptr2, ptr3, ptr4
.macpack	longbranch

.segment "DATA"

_octave:			 .res 1
_note:         .res 1
_chan:         .res 1
_volume:       .res 1
;_note = $5000
;_chan = $5001
;_volume = $5002
;_octave = $5003

.export _octave, _note, _chan, _volume
.segment "DATA"
octaveAdr: .byte OC10 , OC32, OC54
noteAdr: .byte 5, 32, 60, 85, 110, 132, 153, 173, 192, 210, 227, 243
channelAdr: .byte $08, $09, $0A, $0B, $0C, $0D



.export _saa_init
.export _saa_write_register
.export _saa_write_data
.export _saa_note_play
.export _saa_note_stop
.export _saa_play_note

.segment "CODE"





_saa_play_note: LDX _chan
                LDA _volume
                JSR _saa_write_data_to_register
                LDY _chan
                LDX channelAdr, Y
                LDY _note
                LDA noteAdr, Y
                JSR _saa_write_data_to_register
                RTS

_saa_note_play:     ;A = Number of note in octave to play, X channel to play, Y Volume of cannels in format RL € 00-F0
                PHA
                TYA
                JSR _saa_write_data_to_register
                PLY
                LDA channelAdr, X
                TAX
                LDA noteAdr, Y
                JSR _saa_write_data_to_register
                RTS

_saa_note_stop:     ;A number of channel to stop playing
                PHA
                TAX
                LDA #$0
                JSR _saa_write_data_to_register
                PLA
                RTS




_saa_write_data_to_register:  STX SAA_REG
                              NOP
                              NOP
                              NOP
                              STA SAA_DATA
                              NOP
                              NOP
                              NOP
                              NOP
                              NOP
                              NOP
                              NOP
                              NOP
                              NOP
                              LDA SAA_DATA
                              NOP
                              NOP
                              NOP
                              NOP
                              NOP
                              NOP
                              RTS

_saa_write_register:  STA SAA_REG
                      RTS
_saa_write_data:      STA SAA_DATA
                      RTS

_saa_mute:  LDX #0
@start:     LDA #$00
            STX $C401
            STA $C400
            INX
            TXA
            CMP #$6
            BNE @start
            RTS

_saa_zero:  LDA #$0
            LDX #$19
@start:     STX SAA_REG
            JSR _saa_write_data_to_register
            DEX
            BNE @start
            RTS


_saa_init:  JSR _saa_zero
            LDX #SOE
            LDA #$2
            JSR _saa_write_data_to_register

            LDA #$0
            JSR _saa_write_data
            LDX #SOE
            LDA #$1
            JSR _saa_write_data_to_register

            RTS
            LDX #AM0
            LDA #$FF
            JSR _saa_write_data_to_register

            LDX #AM1
            LDA #$0
            JSR _saa_write_data_to_register

            LDX #AM2
            LDA #$0
            JSR _saa_write_data_to_register

            LDX #AM3
            LDA #$0
            JSR _saa_write_data_to_register

            LDX #AM4
            LDA #$0
            JSR _saa_write_data_to_register

            LDX #AM5
            LDA #$0
            JSR _saa_write_data_to_register

            LDX #OC10
            LDA #$11
            JSR _saa_write_data_to_register

            LDX #OC32
            LDA #$55
            JSR _saa_write_data_to_register

            LDX #OC54
            LDA #$55
            JSR _saa_write_data_to_register
            ;RTS

ppp:        LDA #$9
            LDX #$0
            LDY #$55
            JSR _saa_note_play
            RTS
            jmp ppp
            LDA #$0
            ;JSR _saa_note_stop

            ;LDA #8
          ;STA _note
            LDA #$40
            ;STA _volume
            LDA #$0
            ;STA _chan
            ;JSR _saa_play_note

            ;JSR _saa_note_play
            ;JSR _saa_mute
            ;JSR _simpletune
            RTS
