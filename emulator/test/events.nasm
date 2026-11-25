; The event counters (DEVICES.md §3). A read of a counter returns the
; events before it, but for the data reads of its own instruction before
; it. A store counts also when the device ignores it. SPARE, the first
; word after the counters, counts nothing and reads 0. Every core counts
; the same, so the trace is the same on all.
;
;   step  reads stores skips jumps, after the step
;    0      1                          MOVE R1, @READ_LO     R1 = 0
;    1      3                          ADD R2, @READ_LO, @READ_LO  1 + 2: R2 = 3
;    2            1                    MOVE @data, 7
;    3            2                    MOVE @READ_LO, 0x55   ignored
;    4      4                          MOVE R3, @STORE_LO    R3 = 2
;    5                   1             ?Z MOVE R4, @READ_LO  skipped (Z = 0 after reset)
;    6      5                          MOVE R4, @SKIP_LO     R4 = 1
;    7                         1       JMP next
;    8      6                          MOVE R5, @JUMP_LO     R5 = 1
;    9                   2             ?Z JMP fail           skipped
;   10      7                  2       MOVE R6, @PC++        R6 = 0x1234, a side effect on R15
;   11      8                          MOVE R7, @JUMP_LO     R7 = 2
;   12      9                          MOVE R8, @SPARE       R8 = 0
;   13     10                          MOVE R10, @JUMP_LO    R10 = 2
;   14     11                          MOVE R11, @READ_LO    R11 = 10 = 0xA
;   15     12                          MOVE R12, @READ_HI    the snapshot's high word: R12 = 0
;   16     13                          MOVE R13, @SKIP_LO    R13 = 2
;   17                                 HALT
;
; 18 steps. PC = 0x24 after the HALT at 0x23. The dump reads the counters
; without taking snapshots: 13 = 0xD reads, 2 stores, 2 skips, 2 jumps,
; and SPARE 0, and the snapshots' high words, 0. The store to data
; shows in memory; the one to READ_LO does not.
READ_LO         .EQU    0xFFFFFF4A
READ_HI         .EQU    0xFFFFFF4B
STORE_LO        .EQU    0xFFFFFF4C
SKIP_LO         .EQU    0xFFFFFF4E
JUMP_LO         .EQU    0xFFFFFF50
SPARE           .EQU    0xFFFFFF52
PC              .EQU    R15
                MOVE    R1, @READ_LO    ; words 0,1
                ADD     R2, @READ_LO, @READ_LO  ; words 2-4
                MOVE    @data, 7        ; words 5-7
                MOVE    @READ_LO, 0x55  ; words 8-10
                MOVE    R3, @STORE_LO   ; words 11,12
        ?Z      MOVE    R4, @READ_LO    ; words 13,14
                MOVE    R4, @SKIP_LO    ; words 15,16
                JMP     next            ; word 17
next            MOVE    R5, @JUMP_LO    ; words 18,19
        ?Z      JMP     fail            ; word 20
                MOVE    R6, @PC++       ; word 21
                .DAT    0x00001234      ; word 22
                MOVE    R7, @JUMP_LO    ; words 23,24
                MOVE    R8, @SPARE      ; words 25,26
                MOVE    R10, @JUMP_LO   ; words 27,28
                MOVE    R11, @READ_LO   ; words 29,30
                MOVE    R12, @READ_HI   ; words 31,32
                MOVE    R13, @SKIP_LO   ; words 33,34
                HALT                    ; word 35
data            .DAT    0               ; word 36
fail            .DAT    0x0FE00000      ; word 37: a reserved word, which halts
