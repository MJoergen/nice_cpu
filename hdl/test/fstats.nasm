; The fetch statistics (MICROARCH.md §8.1) on the pipelined core. The
; emulator has none, so this program runs only on that core, and checks
; itself.
; R12 holds the number of the check. A failed check jumps to fail, a
; reserved control word, so the program ends with exit status 2 instead of
; 0, and R12 names the check.
;
; The counters run from reset. The program clears them and runs a loop of
; LOOPS rounds. Each round makes one jump that DECODE resolves, MOVE PC, c,
; and one that WRITE takes, ?!Z MOVE PC, c, except the last round. Then it
; stops them, and checks what any run of the loop must give: the causes
; add up to FS_CYCLES, at least 3 * (LOOPS - 1) micro-operations retired,
; at least LOOPS - 1 flushes for a jump and none for another cause, and
; cycles of refill after a flush and after a jump that DECODE resolved.
; DECODE may take the first round's first instruction before the clear,
; so the program counts at least LOOPS - 1 jumps. Then a store into the
; word after it flushes once, for a store into fetched code. Stopped
; counters keep their values, and a clear sets them to 0.
FS_CTRL         .EQU    0xFFFFFF60
FS_CYCLES       .EQU    0xFFFFFF61
FS_JUMPS        .EQU    0xFFFFFF64
FS_FLUSH        .EQU    0xFFFFFF68      ; + the cause of the flush
FS_F_JUMP       .EQU    0xFFFFFF68
FS_F_SKIP       .EQU    0xFFFFFF69
FS_F_STORE      .EQU    0xFFFFFF6A
FS_F_INTR       .EQU    0xFFFFFF6B
FS_F_OTHER      .EQU    0xFFFFFF6C
FS_CAUSE        .EQU    0xFFFFFF70      ; + the cause of the cycle
FS_RETIRE       .EQU    0xFFFFFF70
FS_REFILL       .EQU    0xFFFFFF71
FS_BUBBLE       .EQU    0xFFFFFF72
CAUSES          .EQU    15
PC              .EQU    R15
LOOPS           .EQU    20
LOOPS_1         .EQU    19              ; LOOPS - 1
UOPS            .EQU    57              ; 3 * (LOOPS - 1)

; 1. The counters run after reset.
                MOVE    R12, 1
                CMP     @FS_CTRL, 1
        ?!Z     JMP     fail

; 2. The loop, between a clear and a stop. Each round runs 3 instructions
; of one micro-operation each.
                MOVE    R12, 2
                MOVE    R1, LOOPS
                MOVE    @FS_CTRL, 3
loop            JMP     next
                HALT
next            SUB[M]  R1, R1, 1
        ?!Z     JMP     loop
                MOVE    @FS_CTRL, 0

; 3. The causes add up to FS_CYCLES, which is not 0.
                MOVE    R12, 3
                MOVE    R2, FS_CAUSE
                MOVE    R3, CAUSES
                MOVE    R4, 0
causes          ADD     R4, R4, @R2++
                SUB[M]  R3, R3, 1
        ?!Z     JMP     causes
                CMP     R4, @FS_CYCLES
        ?!Z     JMP     fail
                TST     R4
        ?Z      JMP     fail

; 4. At least 3 * (LOOPS - 1) micro-operations retired, and LOOPS - 1
; jumps that DECODE resolved. C = 1 after SUB[M] if a < b.
                MOVE    R12, 4
                CMP     @FS_RETIRE, UOPS
        ?C      JMP     fail
                CMP     @FS_JUMPS, LOOPS_1
        ?C      JMP     fail

; 5. At least LOOPS - 1 flushes for a jump, and none for another cause.
; The refills after them, and after the jumps that DECODE resolved, took
; cycles.
                MOVE    R12, 5
                CMP     @FS_F_JUMP, LOOPS_1
        ?C      JMP     fail
                TST     @FS_F_SKIP
        ?!Z     JMP     fail
                TST     @FS_F_STORE
        ?!Z     JMP     fail
                TST     @FS_F_INTR
        ?!Z     JMP     fail
                TST     @FS_F_OTHER
        ?!Z     JMP     fail
                TST     @FS_REFILL
        ?Z      JMP     fail
                TST     @FS_BUBBLE
        ?Z      JMP     fail

; 6. Stopped counters keep their values.
                MOVE    R12, 6
                MOVE    R5, @FS_CYCLES
                CMP     R5, @FS_CYCLES
        ?!Z     JMP     fail
                TST     @FS_CTRL
        ?!Z     JMP     fail

; 7. A store into the word after it flushes the pipeline once, for a store
; into fetched code, and for nothing else.
                MOVE    R12, 7
                MOVE    @FS_CTRL, 3
                MOVE    @data, 5
data            .DAT    0x00000000      ; a NOP, which the store makes 5
                MOVE    @FS_CTRL, 0
                CMP     @FS_F_STORE, 1
        ?!Z     JMP     fail
                TST     @FS_F_JUMP
        ?!Z     JMP     fail
                CMP     @data, 5
        ?!Z     JMP     fail

; 8. A clear without a run: FS_CYCLES and the causes read 0.
                MOVE    R12, 8
                MOVE    @FS_CTRL, 2
                TST     @FS_CYCLES
        ?!Z     JMP     fail
                TST     @FS_RETIRE
        ?!Z     JMP     fail
                TST     @FS_F_STORE
        ?!Z     JMP     fail

                MOVE    R12, 0
                HALT

fail            .DAT    0x0FE00000      ; a reserved word: halts with status 2
