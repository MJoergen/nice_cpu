; The saved-state instructions (ISA.md §5.3) right next to the
; instructions that use what they read or write: a register read at once
; as a value, an address, and with a side effect; SR read into R14 and
; then tested; a register loaded or stepped just before it is written to
; saved_pc; saved_pc and saved_sr written just before RTI; a jump with
; RDSPC R15; WRSPC R15; and a skipped one. The log at 0x300 is
; 5 (back1), 0x01000001, 0x45000001 (C and E set by WRSSR), 0x1A, 2.
        MOVE    R14, 1              ; VBASE = 1: the table is at 0x100
        MOVE    R13, 0x300
        INT     1
back1   ?C MOVE R2, 2               ; C comes from WRSSR in routine 1
        MOVE    @R13++, R14
        INT     2
        HALT                        ; skipped: routine 2 returns to back2
back2   MOVE    @R13++, R2
        HALT

isr1    RDSPC   R3                  ; back1
        ADD     R4, R3, 1           ; R3 at once, as a value
        MOVE    R5, @R3             ; as an address
        MOVE    @R13++, R3++        ; with a side effect
        RDSSR   R14                 ; I = 0 again
        ?I MOVE R6, 0xBAD
        ?!I MOVE R6, 1
        RDSSR   R7
        MOVE    @R13++, R7
        MOVE    R8, data
        MOVE    R9, @R8++           ; a load, then its register at once
        WRSPC   R9
        RDSSR   R10
        OR      R10, R10, 0x44000000 ; C and E
        WRSSR   R10                 ; just before RTI
        RTI

isr2    MOVE    R1, here2
        WRSPC   R1
        RDSPC   R15                 ; jumps to here2
        MOVE    R2, 0xBAD
here2   WRSPC   R15                 ; saved_pc = the next instruction
        RDSPC   R11
        SUB     R11, R11, here2     ; 1
        ADD     @R13++, R11, 0x19   ; 0x1A
        MOVE[M] R0, R11             ; Z = 0
        MOVE    R12, back2-1
        ?Z WRSPC R0                 ; skipped
        MOVE    R0, R12++           ; R12 stepped by a side effect, then written at once
        WRSPC   R12
        RTI

data    .DAT    back1
        .ORG    0x101
        .DAT    isr1
        .DAT    isr2
