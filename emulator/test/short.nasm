; The one-word JMP, JMPR, and CALL (ISA.md §5.3): commands 4, 5, and 6, with
; the distance from the next instruction in bits 20..0. A skipped jump, a
; taken one forward, a CALL that pushes its next address through R13 and
; a RET, a backward JMPR taken twice, and a JMP forward.
;
;   word  instruction                 the word, by hand
;    0    MOVE R13, 0x100
;    2    CMP R0, 1                   Z = 0, C = N = X = 1
;    4    ?Z JMP fail                 3c800001: 6 - 5 = 1, skipped
;    5    ?!Z JMPR fwd                bca00001: 7 - 6 = 1, taken
;    6    fail: a reserved word, which halts
;    7    fwd: CALL routine           0cc00008: 16 - 8 = 8, mem[0xFF] = 8
;    8    MOVE R2, @0xFF              R2 = 8, the address after the CALL
;   10    MOVE R3, 3
;   12    SUB[M] R3, R3, 1
;   14    ?!Z JMPR :-                 bcbffffd: 12 - 15 = -3
;   15    JMP done                    0c800002: 18 - 16 = 2
;   16    routine: MOVE R1, R13       R1 = 0xFF, the SP in the routine
;   17    RET
;   18    done: HALT
;
; Steps: MOVE, CMP, the skipped JMP, JMPR, CALL, MOVE R1, RET, MOVE R2,
; MOVE R3, three times SUB[M] and JMPR, JMP, and HALT: 17. PC = 0x13. R13
; = 0x100 after the RET. The last SUB[M] gives 0, so R14 = 0x09000000. The
; dump shows the pushed 8 at 0xFF.
                MOVE    R13, 0x100
                CMP     R0, 1
        ?Z      JMP     fail
        ?!Z     JMPR    fwd
fail            .DAT    0x0FE00000
fwd             CALL    routine
                MOVE    R2, @0xFF
                MOVE    R3, 3
:               SUB[M]  R3, R3, 1
        ?!Z     JMPR    :-
                JMP     done
routine         MOVE    R1, R13
                RET
done            HALT
