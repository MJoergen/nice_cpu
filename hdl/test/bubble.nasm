; The bubbles of the pipelined core, measured with the cycle counter
; (SYSTEM.md §3): the cycles between a read of CYCLE_LO before and one
; after each kind of jump, and after a fall-through for comparison. The
; values are those of doc/review/third-repository-review.md §1.2, on a
; memory that never stalls: a jump that WRITE resolves costs 6 cycles over
; a fall-through, aligned or not; a jump that DECODE resolves 2
; (MICROARCH.md §5.4); and an operation other than MOVE into R15 one more
; (§7.4). The program checks itself: R12 counts the cases that gave another
; value, and is 0 at the end if all passed. It runs on the pipelined core
; only, since the multi-cycle core has other bubbles and the emulator
; counts steps, not cycles. Each case starts on an even address, so that
; the layout of each is that of the review's programs.
CYCLES  .EQU    0xFFFFFF40
        MOVE    R12, 0
; a fall-through, the baseline: 3 cycles between the reads
        .ORG    0x40
        MOVE    R1, @CYCLES
        MOVE    R0, 0
        MOVE    R2, @CYCLES
        SUB     R4, R2, R1
        SUB[M]  R0, R4, 3
        ?!Z ADD R12, R12, 1
; a skipped conditional jump: 3, the same as the fall-through
        .ORG    0x80
        ADD[M]  R0, R0, 1       ; Z = 0
        MOVE    R1, @CYCLES
        ?Z MOVE R15, a1
a1      MOVE    R2, @CYCLES
        SUB     R4, R2, R1
        SUB[M]  R0, R4, 3
        ?!Z ADD R12, R12, 1
; a taken conditional jump, resolved in WRITE: 3 + 6
        .ORG    0xC0
        ADD[M]  R0, R0, 1
        MOVE    R1, @CYCLES
        ?!Z MOVE R15, a2
a2      MOVE    R2, @CYCLES
        SUB     R4, R2, R1
        SUB[M]  R0, R4, 9
        ?!Z ADD R12, R12, 1
; the same to a target on an odd address, whose instruction spans two
; pairs: a cycle more in the fall-through, and the same 6 for the jump
        .ORG    0x100
        ADD[M]  R0, R0, 1
        MOVE    R1, @CYCLES
        ?Z MOVE R15, a3
        MOVE    R0, R0
a3      MOVE    R2, @CYCLES
        SUB     R4, R2, R1
        SUB[M]  R0, R4, 4
        ?!Z ADD R12, R12, 1
        .ORG    0x140
        ADD[M]  R0, R0, 1
        MOVE    R1, @CYCLES
        ?!Z MOVE R15, a4
        MOVE    R0, R0
a4      MOVE    R2, @CYCLES
        SUB     R4, R2, R1
        SUB[M]  R0, R4, 10
        ?!Z ADD R12, R12, 1
; a jump that DECODE resolves: 3 + 2
        .ORG    0x180
        MOVE    R1, @CYCLES
        MOVE    R15, a5
a5      MOVE    R2, @CYCLES
        SUB     R4, R2, R1
        SUB[M]  R0, R4, 5
        ?!Z ADD R12, R12, 1
; MOVE R15, R3: the target is the source, ready in WRITE's first cycle: 3 + 6
        .ORG    0x1C0
        MOVE    R3, a6
        MOVE    R1, @CYCLES
        MOVE    R15, R3
        .DAT    0
a6      MOVE    R2, @CYCLES
        SUB     R4, R2, R1
        SUB[M]  R0, R4, 9
        ?!Z ADD R12, R12, 1
; ADD R15, R3, 0: a second cycle in WRITE: 3 + 7
        .ORG    0x200
        MOVE    R3, a7
        MOVE    R1, @CYCLES
        ADD     R15, R3, 0
a7      MOVE    R2, @CYCLES
        SUB     R4, R2, R1
        SUB[M]  R0, R4, 10
        ?!Z ADD R12, R12, 1
        HALT
