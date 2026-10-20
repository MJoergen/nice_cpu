; R0 in every place (ISA.md §4.3), with shifts and two-cycle destinations.
        MOVE    R1, 0x9ABCDEF1
        MOVE    @0, 0x0C000000      ; word 0 (already run) becomes a HALT
        MOVE    R2, @0
        MOVE    R0++, 5             ; discarded, one cycle
        MOVE    R0--, R1
        ADD     R0++, R0++, --R0
        MOVE    R3, --R0            ; 0
        MOVE    R3, R0++
        0<0[M]  R3, R1, --R0        ; count 0
        0<0[M]  R3, R1, R0++
        C<C[M]  R3, R1, --R0        ; rotation through C by --R0, count 0
        C>C[M]  R3, R1, R0++
        C>C[M]  R3, R1, @R0++       ; count = mem[0] = 0x0C000000
        0<0[M]  R3, R1, @--R0       ; count = mem[0]
        MOVE    R4, @--R0
        MOVE    @R0++, 0x0C000000   ; word 0 again
        MOVE    @--R0, 0x0C000000
        ADD     R4, R15, R0++
        ADD     R4, R0++, R15
        MOVE    R0, @R0++
        0<0     R0, R1, @R0         ; count from memory, result discarded
        0<0[M]  R0, R1, 3           ; flags from the discarded result
        ?Z MOVE R4, 0xBAD
        C<C[M]  R0--, R1, @0        ; no second cycle for R0
        MOVE    R5, R0
        ADD     @R0, R0, R0         ; mem[0] = 0
        MOVE    R6, @0
        MOVE    @0, 0x0C000000
        HALT
