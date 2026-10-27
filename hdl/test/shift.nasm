; Every shift (ISA.md §5.2), with C = 0 and C = 1 before it, for counts
; around 32 and 33 and for counts that test the reduction mod 33 of
; MICROARCH.md §7.3. The counts 0xC1F07C1F and 0x3E0F83E0 give its largest
; and smallest digit sums. The multicycle core's trace is compared with the
; emulator's, so the results are not written out here.
                MOVE    R1, 0x9ABCDEF1  ; the value to shift
                MOVE    R2, counts
                MOVE    R6, 29          ; the number of counts
loop            MOVE    R4, @R2++
                ADD[M]  R0, R0, R0      ; C = 0
                0<0[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                0<0[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                0<1[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                0<1[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                0<C[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                0<C[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                C<0[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                C<0[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                C<1[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                C<1[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                C<C[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                C<C[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                <<<[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                <<<[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                C<<[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                C<<[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                0>0[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                0>0[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                1>0[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                1>0[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                C>0[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                C>0[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                0>C[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                0>C[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                1>C[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                1>C[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                C>C[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                C>C[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                >>>[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                >>>[M]  R3, R1, R4
                ADD[M]  R0, R0, R0      ; C = 0
                >>C[M]  R3, R1, R4
                SUB[M]  R0, R0, 1       ; C = 1
                >>C[M]  R3, R1, R4
                SUB     R6, R6, 1
                MOVE[M] R0, R6
        ?!Z     MOVE    R15, loop
                HALT
counts
                .DAT    0x00000000
                .DAT    0x00000001
                .DAT    0x00000002
                .DAT    0x0000001F
                .DAT    0x00000020
                .DAT    0x00000021
                .DAT    0x00000022
                .DAT    0x00000023
                .DAT    0x0000003F
                .DAT    0x00000040
                .DAT    0x00000041
                .DAT    0x00000042
                .DAT    0x00000043
                .DAT    0x00000062
                .DAT    0x00000063
                .DAT    0x00000064
                .DAT    0x7FFFFFFF
                .DAT    0x80000000
                .DAT    0x80000001
                .DAT    0xFFFFFFFB
                .DAT    0xFFFFFFFC
                .DAT    0xFFFFFFFD
                .DAT    0xFFFFFFFE
                .DAT    0xFFFFFFFF
                .DAT    0xC1F07C1E
                .DAT    0xC1F07C1F
                .DAT    0x3E0F83E0
                .DAT    0x3E0F83E1
                .DAT    0x3E0F83DF
