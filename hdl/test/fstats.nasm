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
; stops them, and checks what any run of the loop must give: the
; histogram adds up to FS_CYCLES, FS_MIN <= FS_MAX <= FS_HELD_MAX <= 16,
; the buffer's depth, at least LOOPS - 1 flushes, and cycles in which
; DECODE waited for words. DECODE may take the first round's first
; instruction before the clear, so the program counts at least LOOPS - 1
; jumps, and the 6 words of LOOPS - 1 rounds. Stopped counters keep their
; values, and a clear sets them to 0, and FS_MIN to 31.
FS_CTRL     .EQU    0xFFFFFF50
FS_CYCLES   .EQU    0xFFFFFF51
FS_STARVE   .EQU    0xFFFFFF52
FS_PAIRS    .EQU    0xFFFFFF56
FS_WORDS    .EQU    0xFFFFFF57
FS_JUMPS    .EQU    0xFFFFFF58
FS_FLUSHES  .EQU    0xFFFFFF59
FS_MIN      .EQU    0xFFFFFF5A
FS_MAX      .EQU    0xFFFFFF5B
FS_HELD_MAX .EQU    0xFFFFFF5C
FS_HIST     .EQU    0xFFFFFF60
PC          .EQU    R15
LOOPS       .EQU    20
LOOPS_1     .EQU    19              ; LOOPS - 1
WORDS       .EQU    114             ; 6 * (LOOPS - 1)
DEPTH       .EQU    16

; 1. The counters run after reset.
        MOVE    R12, 1
        SUB[M]  R0, @FS_CTRL, 1
        ?!Z MOVE PC, fail

; 2. The loop, between a clear and a stop. Each round runs 3 instructions
; of 2 words each.
        MOVE    R12, 2
        MOVE    R1, LOOPS
        MOVE    @FS_CTRL, 3
loop    MOVE    PC, next
        HALT
next    SUB[M]  R1, R1, 1
        ?!Z MOVE PC, loop
        MOVE    @FS_CTRL, 0

; 3. The histogram adds up to FS_CYCLES, which is not 0.
        MOVE    R12, 3
        MOVE    R2, FS_HIST
        MOVE    R3, 32
        MOVE    R4, 0
hist    ADD     R4, R4, @R2++
        SUB[M]  R3, R3, 1
        ?!Z MOVE PC, hist
        SUB[M]  R0, R4, @FS_CYCLES
        ?!Z MOVE PC, fail
        MOVE[M] R0, R4
        ?Z MOVE PC, fail

; 4. FS_MIN <= FS_MAX <= FS_HELD_MAX <= DEPTH. C = 1 after SUB[M] if a < b.
        MOVE    R12, 4
        SUB[M]  R0, @FS_MAX, @FS_MIN
        ?C MOVE PC, fail
        SUB[M]  R0, @FS_HELD_MAX, @FS_MAX
        ?C MOVE PC, fail
        SUB[M]  R0, DEPTH, @FS_HELD_MAX
        ?C MOVE PC, fail

; 5. At least LOOPS - 1 jumps and flushes, and 6 * (LOOPS - 1) words. Some
; cycles waited for words, and some pairs arrived.
        MOVE    R12, 5
        SUB[M]  R0, @FS_JUMPS, LOOPS_1
        ?C MOVE PC, fail
        SUB[M]  R0, @FS_FLUSHES, LOOPS_1
        ?C MOVE PC, fail
        SUB[M]  R0, @FS_WORDS, WORDS
        ?C MOVE PC, fail
        MOVE[M] R0, @FS_STARVE
        ?Z MOVE PC, fail
        MOVE[M] R0, @FS_PAIRS
        ?Z MOVE PC, fail

; 6. Stopped counters keep their values.
        MOVE    R12, 6
        MOVE    R5, @FS_CYCLES
        SUB[M]  R0, R5, @FS_CYCLES
        ?!Z MOVE PC, fail
        MOVE[M] R0, @FS_CTRL
        ?!Z MOVE PC, fail

; 7. A clear without a run: FS_CYCLES and FS_MAX read 0, FS_MIN 31.
        MOVE    R12, 7
        MOVE    @FS_CTRL, 2
        MOVE[M] R0, @FS_CYCLES
        ?!Z MOVE PC, fail
        MOVE[M] R0, @FS_MAX
        ?!Z MOVE PC, fail
        SUB[M]  R0, @FS_MIN, 31
        ?!Z MOVE PC, fail

        MOVE    R12, 0
        HALT

fail    .DAT    0x0FE00000      ; a reserved word: halts with status 2
