; The bubbles of the pipelined core, measured with the cycle counter
; (SYSTEM.md §3): the cycles between a read of CYCLE_LO before and one
; after each kind of jump, and after a fall-through for comparison. The
; values are those of doc/review/third-repository-review.md §1.2, on a
; memory that never stalls, with a cycle more for each jump that WRITE
; resolves, since its redirect reaches FETCH from a register: such a jump
; costs 7 cycles over a fall-through, aligned or not; a jump that DECODE
; resolves 2 (MICROARCH.md §5.4), since the read before it holds the
; stream up a cycle while DECODE has the jump, which hides one cycle of
; the 3 it costs in a stream without reads; and an operation other than MOVE into
; R15 one more (§7.4). A backward conditional ADD R15, R15, offset, which
; DECODE predicts taken, costs the 2 of a jump DECODE resolves when taken,
; and the 7 of a jump WRITE resolves when skipped. The last three cases are four reads in a row: WRITE takes read
; data a cycle after its ACK, unless it only goes into a register
; (§5.3), so four ADDs from memory take 2 cycles more than four MOVEs, and
; four MOVEs from memory into memory 4 more than the 11 they took when
; WRITE took every read in the cycle of its ACK. Each store goes on the
; bus from DBUS's store register a cycle after WRITE runs it, and the read
; after it waits for that (§5.3, rule 3), which adds 4 more. The program
; checks itself: R12 counts the cases that gave another value, and is 0
; at the end if all passed. It runs on the pipelined core
; only, since the multi-cycle core has other bubbles and the emulator
; counts steps, not cycles. Each case starts on an even address, so that
; the layout of each is that of the review's programs.
CYCLES          .EQU    0xFFFFFF40
                MOVE    R12, 0
; a fall-through, the baseline: 3 cycles between the reads
                .ORG    0x40
                MOVE    R1, @CYCLES
                MOVE    R0, 0
                MOVE    R2, @CYCLES
                SUB     R4, R2, R1
                SUB[M]  R0, R4, 3
        ?!Z     ADD     R12, R12, 1
; a skipped conditional jump: 3, the same as the fall-through
                .ORG    0x80
                ADD[M]  R0, R0, 1       ; Z = 0
                MOVE    R1, @CYCLES
        ?Z      MOVE    R15, a1
a1              MOVE    R2, @CYCLES
                SUB     R4, R2, R1
                SUB[M]  R0, R4, 3
        ?!Z     ADD     R12, R12, 1
; a taken conditional jump, resolved in WRITE: 3 + 7
                .ORG    0xC0
                ADD[M]  R0, R0, 1
                MOVE    R1, @CYCLES
        ?!Z     MOVE    R15, a2
a2              MOVE    R2, @CYCLES
                SUB     R4, R2, R1
                SUB[M]  R0, R4, 10
        ?!Z     ADD     R12, R12, 1
; the same to a target on an odd address, whose instruction spans two
; pairs: a cycle more in the fall-through, and the same 7 for the jump
                .ORG    0x100
                ADD[M]  R0, R0, 1
                MOVE    R1, @CYCLES
        ?Z      MOVE    R15, a3
                MOVE    R0, R0
a3              MOVE    R2, @CYCLES
                SUB     R4, R2, R1
                SUB[M]  R0, R4, 4
        ?!Z     ADD     R12, R12, 1
                .ORG    0x140
                ADD[M]  R0, R0, 1
                MOVE    R1, @CYCLES
        ?!Z     MOVE    R15, a4
                MOVE    R0, R0
a4              MOVE    R2, @CYCLES
                SUB     R4, R2, R1
                SUB[M]  R0, R4, 11
        ?!Z     ADD     R12, R12, 1
; a jump that DECODE resolves: 3 + 2
                .ORG    0x180
                MOVE    R1, @CYCLES
                MOVE    R15, a5
a5              MOVE    R2, @CYCLES
                SUB     R4, R2, R1
                SUB[M]  R0, R4, 5
        ?!Z     ADD     R12, R12, 1
; MOVE R15, R3: the target is the source, ready in WRITE's first cycle: 3 + 7
                .ORG    0x1C0
                MOVE    R3, a6
                MOVE    R1, @CYCLES
                MOVE    R15, R3
                .DAT    0
a6              MOVE    R2, @CYCLES
                SUB     R4, R2, R1
                SUB[M]  R0, R4, 10
        ?!Z     ADD     R12, R12, 1
; ADD R15, R3, 0: a second cycle in WRITE: 3 + 8
                .ORG    0x200
                MOVE    R3, a7
                MOVE    R1, @CYCLES
                ADD     R15, R3, 0
a7              MOVE    R2, @CYCLES
                SUB     R4, R2, R1
                SUB[M]  R0, R4, 11
        ?!Z     ADD     R12, R12, 1
; four MOVEs from memory into a register, each in the cycle of its ACK: 8
                .ORG    0x240
                MOVE    R3, 0x400
                MOVE    R1, @CYCLES
                MOVE    R5, @R3
                MOVE    R5, @R3
                MOVE    R5, @R3
                MOVE    R5, @R3
                MOVE    R2, @CYCLES
                SUB     R4, R2, R1
                SUB[M]  R0, R4, 8
        ?!Z     ADD     R12, R12, 1
; four ADDs from memory, each a cycle after its ACK, two of them hidden: 10
                .ORG    0x280
                MOVE    R1, @CYCLES
                ADD     R5, R5, @R3
                ADD     R5, R5, @R3
                ADD     R5, R5, @R3
                ADD     R5, R5, @R3
                MOVE    R2, @CYCLES
                SUB     R4, R2, R1
                SUB[M]  R0, R4, 10
        ?!Z     ADD     R12, R12, 1
; four MOVEs from memory into memory, each store a cycle after its ACK,
; and each read after the store before: 19
                .ORG    0x2C0
                MOVE    R1, @CYCLES
                MOVE    @R3, @R3
                MOVE    @R3, @R3
                MOVE    @R3, @R3
                MOVE    @R3, @R3
                MOVE    R2, @CYCLES
                SUB     R4, R2, R1
                SUB[M]  R0, R4, 19
        ?!Z     ADD     R12, R12, 1
                MOVE    R15, s12
; a conditional ADD R15, R15, offset with a negative offset, a backward
; jump that DECODE predicts taken: taken, 3 + 2, the same as a jump that
; DECODE resolves. A NOP keeps the ADD[M] from holding the read before the
; jump up a cycle, which would hide one more cycle of the bubble.
                .ORG    0x300
a12             MOVE    R2, @CYCLES
                SUB     R4, R2, R1
                SUB[M]  R0, R4, 5
        ?!Z     ADD     R12, R12, 1
                MOVE    R15, s13
s12             ADD[M]  R0, R0, 1       ; Z = 0
                MOVE    R0, R0
                MOVE    R1, @CYCLES
        ?!Z     ADD     R15, R15, a12-t12
t12             HALT
; the same, skipped: WRITE flushes and refetches the next instruction,
; 3 + 7, the same as the taken jump at 0xC0, which has the layout of this
; one, without the NOP
                .ORG    0x340
s13             ADD[M]  R0, R0, 1       ; Z = 0
b13             MOVE    R1, @CYCLES
        ?Z      ADD     R15, R15, b13-a13
a13             MOVE    R2, @CYCLES
                SUB     R4, R2, R1
                SUB[M]  R0, R4, 10
        ?!Z     ADD     R12, R12, 1
                HALT
