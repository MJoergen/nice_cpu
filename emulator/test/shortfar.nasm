; The reach of the one-word JMP and CALL (ISA.md §5.3): a CALL to the
; farthest word forward, 0xFFFFF words from the next instruction, and a
; JMP from there to the farthest back, -0x100000 words.
;
;   word      instruction            the word, by hand
;   0         MOVE R13, 0x100
;   2         CALL far               0ccfffff: 3 + 0xFFFFF = 0x100002
;   3         a reserved word, which halts, never reached
;   4         HALT
;   0x100002  far: MOVE R1, @R13     R1 = 3, the address the CALL pushed
;   0x100003  JMP 4                  0c900000: 4 - 0x100004 = -0x100000
;
; Steps: MOVE, CALL, MOVE, JMP, and HALT: 5. PC = 5. R13 = 0xFF, as the
; program never returns. The dump shows the pushed 3 at 0xFF.
                MOVE    R13, 0x100
                CALL    far
                .DAT    0x0FE00000
                HALT
                .ORG    0x100002
far             MOVE    R1, @R13
                JMP     4
