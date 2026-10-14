; The NICE runtime library (doc/ISA.md §9.3). It goes last in the program.
; Every routine follows the C ABI of §9.3.

; __mul: R1 = R1 * R2, the low 32 bits. The same result serves signed and
; unsigned operands. Shift and add: each 1 bit of R2, from bit 0 up, adds
; R1 shifted left by that bit's position. Uses R2 and R3.
; Takes 3 + 4k steps, where k is the number of bits in R2 (1 if R2 = 0).
__mul   MOVE    R3, R1
        MOVE    R1, 0
__mul.loop
        0>C[M]  R2, R2, 1               ; C = next bit, Z = no bits left
        ?C ADD  R1, R1, R3
        SHL     R3, R3, 1               ; no M, so C and Z stay
        ?!Z MOVE R15, __mul.loop
        MOVE    R15, @R13++
