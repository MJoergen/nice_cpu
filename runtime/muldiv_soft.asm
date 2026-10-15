; The one-word multiply and divide routines and __mul64 of the NICE runtime
; library (doc/ISA.md §9.3), in software, for a system without the math
; unit of §8.4. It goes after lib.asm, instead of muldiv_mpu.asm.

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

; __udivmod: R1 = R1 / R2 and R3 = R1 % R2, unsigned. Not a C routine:
; __udiv, __umod, __div, and __mod share it. Restoring division: 32 times,
; shift the next dividend bit into the remainder, and subtract the divisor
; if it fits. The remainder may need 33 bits after the shift, so R6 holds
; its bit 32, and the subtraction is from R6:R3. The quotient bits take the
; dividend's place in R1. Every pass takes 9 steps, whatever the operands,
; so __udivmod takes 2 + 32 * 9 + 1 = 291. Uses R3-R6.
__udivmod
        MOVE    R3, 0                   ; remainder
        MOVE    R4, 32                  ; passes to go
__udivmod.loop
        C<0[M]  R1, R1, 1               ; C = next dividend bit; quotient bit = 0
        C<C[M]  R3, R3, 1               ; into the remainder; C = its bit 32
        ADD[C]  R6, R0, R0              ; R6 = that bit
        SUB[M]  R5, R3, R2
        SUB[CM] R0, R6, 0               ; C = R6:R3 < R2
        ?!C MOVE R3, R5
        ?!C OR  R1, R1, 1
        DEC[M]  R4, R4
        ?!Z MOVE R15, __udivmod.loop
        MOVE    R15, @R13++

; __udiv: R1 = R1 / R2, unsigned. 1 + 291 = 292 steps.
__udiv  MOVE    R15, __udivmod          ; which returns to our caller

; __umod: R1 = R1 % R2, unsigned. 4 + 291 = 295 steps.
__umod  ADD     @--R13, 2, R15
        MOVE    R15, __udivmod
        MOVE    R1, R3
        MOVE    R15, @R13++

; __div: R1 = R1 / R2, signed, rounding toward zero. Divides the absolute
; values, then negates the quotient if the signs differ. 10 + 291 = 301
; steps. The most negative number divided by -1 overflows; the result is
; then the most negative number, which C allows, as the case is undefined.
__div   XOR     @--R13, R1, R2          ; bit 31: the signs differ
        MOVE[M] R1, R1
        ?N SUB  R1, 0, R1
        MOVE[M] R2, R2
        ?N SUB  R2, 0, R2
        ADD     @--R13, 2, R15
        MOVE    R15, __udivmod
        MOVE[M] R0, @R13++
        ?N SUB  R1, 0, R1
        MOVE    R15, @R13++

; __mod: R1 = R1 % R2, signed. The remainder has the dividend's sign, as C
; requires. 11 + 291 = 302 steps.
__mod   MOVE    @--R13, R1              ; bit 31: the dividend's sign
        MOVE[M] R1, R1
        ?N SUB  R1, 0, R1
        MOVE[M] R2, R2
        ?N SUB  R2, 0, R2
        ADD     @--R13, 2, R15
        MOVE    R15, __udivmod
        MOVE    R1, R3
        MOVE[M] R0, @R13++
        ?N SUB  R1, 0, R1
        MOVE    R15, @R13++

; __mul64: R1:R2 = R1:R2 * R3:R4, the low 64 bits, for signed and unsigned
; operands. Each pair is low word first (§9.3). Shift and add, as __mul:
; each 1 bit of R3:R4, from bit 0 up, adds R1:R2 shifted left by that
; bit's position into R5:R6. A pass takes 7 steps, or 9 for a 1 bit. So
; __mul64 takes 2 + 7k + 2j + 3 steps, where k is the number of bits in
; R3:R4 (1 if it is 0) and j the number of 1 bits. Uses R3-R6.
__mul64 MOVE    R5, 0
        MOVE    R6, 0
__mul64.loop
        0>C[M]  R4, R4, 1               ; shift R3:R4 right; C = its bit 0
        C>C[M]  R3, R3, 1
        ?!C MOVE R15, __mul64.next
        ADD[M]  R5, R5, R1
        ADD[C]  R6, R6, R2
__mul64.next
        C<0[M]  R1, R1, 1               ; shift R1:R2 left
        0<C     R2, R2, 1
        OR[M]   R0, R3, R4              ; Z = no bits left
        ?!Z MOVE R15, __mul64.loop
        MOVE    R1, R5
        MOVE    R2, R6
        MOVE    R15, @R13++
