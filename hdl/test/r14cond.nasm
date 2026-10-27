; SR written by side effects and two-cycle destinations, then conditional
; instructions and conditional reads; RTI and INT with conditions; R14 as
; the source and the destination of shifts.
COUNT           .EQU    0xFFFFFF01
                MOVE    R15, start
                .ORG    4
                .DAT    isr
                .ORG    0x100
start           MOVE    R10, scratch
                MOVE    R11, COUNT
                MOVE    @R11, 0
                MOVE    R14, 0x48FFFFFF  ; Z = 1, VBASE all ones
                MOVE    R1, R14++       ; R14 = 0x49000000: Z still 1
        ?Z      MOVE    R2, 1
        ?Z      MOVE    R3, @R10        ; a conditional read after a side-effect write of SR
                MOVE    R1, --R14       ; 0x48FFFFFF, bit 24 set: 0x49FFFFFF
        ?Z      MOVE    R2, 2
        ?!Z     MOVE    R3, @R10
                MOVE    R1, @R14++      ; reads 0x49FFFFFF, R14 = 0x4A000000 | bit 24 = 0x4B000000: X = 1, Z = 1
        ?X      MOVE    R2, 3
        ?Z      MOVE    R3, @R10
                MOVE    @R14++, 5       ; mem[0x4B000000] = 5, R14 = 0x4B000001
        ?Z      MOVE    R3, @R10
                MOVE    @--R14, 6       ; R14 = 0x4B000000, mem = 6
        ?X      MOVE    R3, @R10
                ADD[M]  @R14++, R0, R0  ; R14 = 0x4B000001, then Z = 1, X = 0, flags from r = 0
        ?Z      MOVE    R2, 4
        ?X      MOVE    R2, 0xBAD
        ?!X     MOVE    R3, @R10
                MOVE[M] @--R14, 0xFFFFFFFF  ; R14 = 0x4B000000, then X = 1, N = 1, Z = 0
        ?X      MOVE    R2, 5
        ?Z      MOVE    R2, 0xBAD
        ?N      MOVE    R3, @R10
                SUB[M]  R14--, R0, R0   ; register-direct: no flags; R14 = 0x01000000 then 0x01FFFFFF
        ?Z      MOVE    R2, 0xBAD
        ?!Z     MOVE    R3, @R10
                MOVE[M] R14++, 0x4FFFFFFF  ; 0x4FFFFFFF then 0x51000000: N = 1, E = 1
        ?N      MOVE    R2, 6
        ?E      MOVE    R3, @R10
        ?Z      MOVE    R2, 0xBAD
                MOVE    R1, @0x1[R14]   ; a read through SR with an adder, right after the two-cycle write
                ADD     R1, R14++, R14  ; s0 = SR, R14 + 1, s1 = new SR
        ?!N     MOVE    R2, 0xBAD
                MOVE    R14, 0x41000000  ; E = 1
; INT and RTI with conditions
                SUB[M]  R0, R0, R0      ; Z = 1
        ?Z      INT     4               ; the routine clears Z, RTI restores it
        ?Z      MOVE    R3, @R10        ; a conditional read right after RTI
        ?!Z     MOVE    R2, 0xBAD
                ADD[M]  R0, R0, 1       ; Z = 0
        ?!Z     INT     4               ; the routine sets Z
        ?Z      MOVE    R2, 0xBAD
        ?I      MOVE    R2, 0xBAD       ; I restored to 0 by RTI
                INT     4
        ?I      MOVE    R2, 0xBAD
; signed comparison with a read after it
                MOVE    R1, 0x80000000
                MOVE    R2, 1
                SUB[M]  R0, R1, R2      ; V = 1, N = 0
        ?V      XOR     R14, R14, 0x10000000
        ?N      MOVE    R3, @R10        ; signed less: runs
        ?!N     MOVE    R3, 0xBAD
                SUB[M]  R0, R2, R1      ; V = 1, N = 1
        ?V      XOR     R14, R14, 0x10000000
        ?N      MOVE    R3, 0xBAD
        ?!N     MOVE    R3, @1[R10]
; R14 as the source and the destination of shifts
                MOVE    R14, 0x41000000
                SUB[M]  R0, R0, 1       ; C = 1: 0x45000000
                0>0     R3, R14, 4      ; s0 = SR right after the flag write
                0>0[M]  R3, R14, 4
                0>0     R14, R14, 4     ; R14 = 0x04500000 | bit 24: C = 1, E = 0
        ?C      MOVE    R2, 7
        ?E      MOVE    R2, 0xBAD
                MOVE    R14, 0x41000000
                SUB[M]  R0, R0, R0      ; Z = 1
        ?Z      0<0     R3, R1, @cnt    ; a conditional late shift with a read
        ?!Z     0<0     R3, R1, @cnt    ; skipped: no read
                MOVE    R2, 3
        ?Z      0<0     R3, R1, R2++    ; late by a side effect: R2 = 4
        ?!Z     0<0     R3, R1, R2++    ; skipped: R2 stays 4
        ?!Z     C<C     R3, R1, --R2
        ?Z      C>C     R3, @R10, --R2  ; R2 = 3
                ADD[M]  R0, R0, 1       ; Z = 0
        ?Z      C>C     R3, @R10, @R10  ; skipped: no reads
                MOVE    R4, @R11        ; the read counter: counts the reads so far
                SUB[M]  R0, R0, R0      ; Z = 1
        ?Z      HALT                    ; stops here
                HALT
isr     ?Z      ADD[M]  R7, R7, 1       ; Z = 0 if it was 1
        ?!Z     SUB[M]  R7, R7, R7      ; Z = 1 if it was 0
                RTI
cnt             .DAT    5
                .ORG    0x1000
scratch         .DAT    0x111, 0x222
                .ORG    0x49FFFFFF
                .DAT    0x94
