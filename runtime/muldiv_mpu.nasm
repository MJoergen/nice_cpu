; The multiply and divide routines of the NICE runtime library
; (doc/ISA.md §9.3), for one word and for long long, with the math unit of
; §8.4. It goes after lib.nasm, instead of muldiv_soft.nasm. Each routine
; writes its operands to A and B, or C and D, and reads the results.

__mpu.a         .EQU    0xFFFFFF20
__mpu.b         .EQU    0xFFFFFF21
__mpu.smul_lo   .EQU    0xFFFFFF22
__mpu.umul_lo   .EQU    0xFFFFFF24
__mpu.umul_hi   .EQU    0xFFFFFF25
__mpu.sdiv_q    .EQU    0xFFFFFF26
__mpu.sdiv_r    .EQU    0xFFFFFF27
__mpu.udiv_q    .EQU    0xFFFFFF28
__mpu.udiv_r    .EQU    0xFFFFFF29
__mpu.c_lo      .EQU    0xFFFFFF30
__mpu.c_hi      .EQU    0xFFFFFF31
__mpu.d_lo      .EQU    0xFFFFFF32
__mpu.d_hi      .EQU    0xFFFFFF33
__mpu.sdiv64_q  .EQU    0xFFFFFF34              ; and +1 for the high word
__mpu.sdiv64_r  .EQU    0xFFFFFF36
__mpu.udiv64_q  .EQU    0xFFFFFF38
__mpu.udiv64_r  .EQU    0xFFFFFF3A

; __mul: R1 = R1 * R2, the low 32 bits, for signed and unsigned operands.
; 4 steps.
__mul   MOVE    @__mpu.a, R1
        MOVE    @__mpu.b, R2
        MOVE    R1, @__mpu.umul_lo
        MOVE    R15, @R13++

; __udiv: R1 = R1 / R2, unsigned. 4 steps.
__udiv  MOVE    @__mpu.a, R1
        MOVE    @__mpu.b, R2
        MOVE    R1, @__mpu.udiv_q
        MOVE    R15, @R13++

; __umod: R1 = R1 % R2, unsigned. 4 steps.
__umod  MOVE    @__mpu.a, R1
        MOVE    @__mpu.b, R2
        MOVE    R1, @__mpu.udiv_r
        MOVE    R15, @R13++

; __div: R1 = R1 / R2, signed, rounding toward zero. 4 steps. The most
; negative number divided by -1 gives the most negative number (§8.4).
__div   MOVE    @__mpu.a, R1
        MOVE    @__mpu.b, R2
        MOVE    R1, @__mpu.sdiv_q
        MOVE    R15, @R13++

; __mod: R1 = R1 % R2, signed, with the dividend's sign. 4 steps.
__mod   MOVE    @__mpu.a, R1
        MOVE    @__mpu.b, R2
        MOVE    R1, @__mpu.sdiv_r
        MOVE    R15, @R13++

; __mul64: R1:R2 = R1:R2 * R3:R4, the low 64 bits, for signed and unsigned
; operands. Each pair is low word first (§9.3). With a = R2:R1 and
; b = R4:R3, the product mod 2^64 is R1 * R3 + 2^32 * (R1 * R4 + R2 * R3).
; Only the low words of the last two products count. 10 steps. Uses R5.
__mul64 MOVE    @__mpu.a, R1
        MOVE    @__mpu.b, R3
        MOVE    R1, @__mpu.umul_lo
        MOVE    R5, @__mpu.umul_hi
        MOVE    @__mpu.b, R4            ; A is still the old R1
        ADD     R5, R5, @__mpu.umul_lo
        MOVE    @__mpu.a, R2
        MOVE    @__mpu.b, R3
        ADD     R2, R5, @__mpu.umul_lo
        MOVE    R15, @R13++

; __udiv64: R1:R2 = R1:R2 / R3:R4, unsigned. 7 steps.
__udiv64
        MOVE    @__mpu.c_lo, R1
        MOVE    @__mpu.c_hi, R2
        MOVE    @__mpu.d_lo, R3
        MOVE    @__mpu.d_hi, R4
        MOVE    R1, @__mpu.udiv64_q
        MOVE    R2, @__mpu.udiv64_q+1
        MOVE    R15, @R13++

; __umod64: R1:R2 = R1:R2 % R3:R4, unsigned. 7 steps.
__umod64
        MOVE    @__mpu.c_lo, R1
        MOVE    @__mpu.c_hi, R2
        MOVE    @__mpu.d_lo, R3
        MOVE    @__mpu.d_hi, R4
        MOVE    R1, @__mpu.udiv64_r
        MOVE    R2, @__mpu.udiv64_r+1
        MOVE    R15, @R13++

; __div64: R1:R2 = R1:R2 / R3:R4, signed, rounding toward zero. 7 steps.
; The most negative number divided by -1 gives the most negative number.
__div64 MOVE    @__mpu.c_lo, R1
        MOVE    @__mpu.c_hi, R2
        MOVE    @__mpu.d_lo, R3
        MOVE    @__mpu.d_hi, R4
        MOVE    R1, @__mpu.sdiv64_q
        MOVE    R2, @__mpu.sdiv64_q+1
        MOVE    R15, @R13++

; __mod64: R1:R2 = R1:R2 % R3:R4, signed, with the dividend's sign. 7 steps.
__mod64 MOVE    @__mpu.c_lo, R1
        MOVE    @__mpu.c_hi, R2
        MOVE    @__mpu.d_lo, R3
        MOVE    @__mpu.d_hi, R4
        MOVE    R1, @__mpu.sdiv64_r
        MOVE    R2, @__mpu.sdiv64_r+1
        MOVE    R15, @R13++
