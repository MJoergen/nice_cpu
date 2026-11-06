; The event counters (SYSTEM.md §3), run with --nmi 12:0x41. A read of a
; counter returns the events before it, but for the data reads of its own
; instruction before it. A store counts also when the device ignores it.
; Every core counts the same, so the trace is the same on all.
;
;   step  reads stores skips jumps intrs, after the step
;    0      1                                MOVE R1, @READ_LO     R1 = 0
;    1      3                                ADD R2, @READ_LO, @READ_LO  1 + 2: R2 = 3
;    2            1                          MOVE @data, 7
;    3            2                          MOVE @READ_LO, 0x55   ignored
;    4      4                                MOVE R3, @STORE_LO    R3 = 2
;    5                   1                   ?Z MOVE R4, @READ_LO  skipped (Z = 0 after reset)
;    6      5                                MOVE R4, @SKIP_LO     R4 = 1
;    7                         1             JMP next
;    8      6                                MOVE R5, @JUMP_LO     R5 = 1
;    9                   2                   ?Z JMP fail           skipped
;   10      7                  2             MOVE R6, @PC++        R6 = 0x1234, a side effect on R15
;   11      8                                MOVE R7, @JUMP_LO     R7 = 2
;   12      9                        1       NMI, through 0x41: the vector read counts
;   13     10                                MOVE R8, @INTR_LO     R8 = 1
;   14                         3             RTI
;   15     11                        2       INT 0x40, through 0x40
;   16     12                                MOVE R9, @INTR_LO     R9 = 2
;   17                         4             RTI
;   18     13                                MOVE R10, @JUMP_LO    R10 = 4
;   19     14                                MOVE R11, @READ_LO    R11 = 13 = 0xD
;   20     15                                MOVE R12, @READ_HI    the snapshot's high word: R12 = 0
;   21     16                                MOVE R13, @SKIP_LO    R13 = 2
;   22                                       HALT
;
; 23 steps. PC = 0x25 after the HALT at 0x24. The dump reads the counters
; without taking snapshots: 16 = 0x10 reads, 2 stores, 2 skips, 4 jumps,
; and 2 interrupts, and the snapshots' high words, 0. The store to data
; shows in memory; the one to READ_LO does not.
READ_LO         .EQU    0xFFFFFF4A
READ_HI         .EQU    0xFFFFFF4B
STORE_LO        .EQU    0xFFFFFF4C
SKIP_LO         .EQU    0xFFFFFF4E
JUMP_LO         .EQU    0xFFFFFF50
INTR_LO         .EQU    0xFFFFFF52
PC              .EQU    R15
                MOVE    R1, @READ_LO    ; words 0,1
                ADD     R2, @READ_LO, @READ_LO  ; words 2-4
                MOVE    @data, 7        ; words 5-7
                MOVE    @READ_LO, 0x55  ; words 8-10
                MOVE    R3, @STORE_LO   ; words 11,12
        ?Z      MOVE    R4, @READ_LO    ; words 13,14
                MOVE    R4, @SKIP_LO    ; words 15,16
                JMP     next            ; words 17,18
next            MOVE    R5, @JUMP_LO    ; words 19,20
        ?Z      JMP     fail            ; words 21,22
                MOVE    R6, @PC++       ; word 23
                .DAT    0x00001234      ; word 24
                MOVE    R7, @JUMP_LO    ; words 25,26
                INT     0x40            ; word 27
                MOVE    R10, @JUMP_LO   ; words 28,29
                MOVE    R11, @READ_LO   ; words 30,31
                MOVE    R12, @READ_HI   ; words 32,33
                MOVE    R13, @SKIP_LO   ; words 34,35
                HALT                    ; word 36
on_nmi          MOVE    R8, @INTR_LO    ; words 37,38
                RTI                     ; word 39
on_int          MOVE    R9, @INTR_LO    ; words 40,41
                RTI                     ; word 42
data            .DAT    0               ; word 43
fail            .DAT    0x0FE00000      ; word 44: a reserved word, which halts
                .ORG    0x40
                .DAT    on_int
                .DAT    on_nmi
