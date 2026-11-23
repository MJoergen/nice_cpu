; The program of tb_trace.vhd. Its steps cover each kind of trace line.
; tb_trace.vhd stands in for the core and reports the effect of each step
; by hand, so the expected values are written there.
;    0    a memory write
;    1    a console byte before the line
;    2    a jump: R15 is listed
;    3    skipped: Z = 0 after reset
;    4    R2 and the flags in R14 change
;    5    a newline to the console: a blank line before the line
;    6    a reserved control command halts, with exit status 2
CONSOLE         .EQU    0xFFFFFF00
                MOVE    @0x50, 7        ; words 0-2
                MOVE    @CONSOLE, 0x48  ; words 3-5: "H"
                JMP     skip            ; word 6
                HALT                    ; word 7: jumped over
skip    ?Z      MOVE    R1, 1           ; words 8,9
                DEC[M]  R2, R2          ; word 10: R2 = 0xFFFFFFFF, C = 1, N = 1
                MOVE    @CONSOLE, 10    ; words 11-13
                .DAT    0x0FE00000      ; word 14: control command 31, reserved
