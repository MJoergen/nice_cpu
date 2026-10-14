; The program of tb_trace.vhd, run with --nmi 5:0x20. Its steps cover each
; kind of trace line. tb_trace.vhd stands in for the core and reports the
; effect of each step by hand, so the expected values are written there.
;    0    a memory write
;    1    a console byte before the line
;    2    a jump: R15 is listed
;    3    skipped: Z = 0 after reset
;    4    R2 and the flags in R14 change
;    5    NMI 20: R14 and R15
;    6    a newline to the console: a blank line before the line
;    7    INT inside the NMI routine halts, with exit status 2
CONSOLE .EQU    0xFFFFFF00
        MOVE    @0x50, 7        ; words 0-2
        MOVE    @CONSOLE, 0x48  ; words 3-5: "H"
        MOVE    R15, skip       ; words 6,7
        HALT                    ; word 8: jumped over
skip    ?Z MOVE R1, 1           ; words 9,10
        DEC[M]  R2, R2          ; word 11: R2 = 0xFFFFFFFF, C = 1, N = 1
        HALT                    ; word 12: not reached
        .ORG    0x20
        .DAT    nmi             ; vector 0x20, with VBASE = 0
nmi     MOVE    @CONSOLE, 10    ; words 0x21-0x23
        INT     0               ; word 0x24
