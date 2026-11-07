; Run after start.nasm. Calls __clz on 2^k and on 2^(k+1) - 1 for k from 0
; to 31, which have the same count, 31 - k, and so reach every count from
; 31 to 0 down each path of the search by halves. 2^32 - 1 is 0xFFFFFFFF,
; as 2 * 2^31 wraps to 0. The 64 results go to results (0x24-0x63), in
; pairs: 31, 31, 30, 30, and so on down to 0, 0.
;
; Code: start.nasm is words 0-10, with its vectors at 9-10, main
; 0x0B-0x23, and results 0x24.
;
; Steps: a call is 2 steps and __clz 19 for a value other than 0. A pass
; is 10 instructions, of which two are calls, so 12 + 2 * 19 = 50 steps.
; The total is 5 (start up) + 3 (set up) + 32 * 50 + 1 (return) + 1
; (HALT) = 1610.
;
; At the end R1 = 0, the last count, and R2 = 1, bit 31 of 0xFFFFFFFF,
; which __clz leaves there. R7 = 0, as 2^31 is shifted out, R8 = 0x64,
; and R9 = 0. R14 = 0x09000000: Z from the last DEC[M].

_main           MOVE    R7, 1           ; 2^k
                MOVE    R8, results
                MOVE    R9, 32          ; number of passes
loop            MOVE    R1, R7
                CALL    __clz
                MOVE    @R8++, R1
                DBL     R1, R7
                DEC     R1, R1          ; 2^(k+1) - 1
                CALL    __clz
                MOVE    @R8++, R1
                SHL     R7, R7, 1
                DEC[M]  R9, R9
        ?!Z     JMP     loop
                RET

results         .BLK    64
