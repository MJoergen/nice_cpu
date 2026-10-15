; The one-word multiply and divide routines and __mul64 of the NICE runtime
; library (doc/ISA.md §9.3), with the math unit of §8.4. It goes after
; lib.asm, instead of muldiv_soft.asm. Each routine writes its operands to
; A and B and reads the results.

__mpu.a         .EQU    0xFFFFFF10
__mpu.b         .EQU    0xFFFFFF11
__mpu.smul_lo   .EQU    0xFFFFFF12
__mpu.umul_lo   .EQU    0xFFFFFF14
__mpu.umul_hi   .EQU    0xFFFFFF15
__mpu.sdiv_q    .EQU    0xFFFFFF16
__mpu.sdiv_r    .EQU    0xFFFFFF17
__mpu.udiv_q    .EQU    0xFFFFFF18
__mpu.udiv_r    .EQU    0xFFFFFF19

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
