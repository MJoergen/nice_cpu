; get(i) = i + 100, imported by sum5.c from env. It also scrambles R2-R6,
; which a callee may change (ABI.md).
_get            ADD     R1, R1, 100
                MOVE    R2, 0xDEAD0002
                MOVE    R3, 0xDEAD0003
                MOVE    R4, 0xDEAD0004
                MOVE    R5, 0xDEAD0005
                MOVE    R6, 0xDEAD0006
                MOVE    R15, @R13++
