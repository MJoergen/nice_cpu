; The NICE runtime library (doc/ISA.md §9.3). It goes last in the program.
; Every routine follows the C ABI of §9.3.

; ___wasm_trap_vector: wasm traps jump through this word (§9.4). It holds
; the default handler until a program stores its own.
___wasm_trap_vector
        .DAT    ___wasm_trap

; ___wasm_trap: the default trap handler. It is the reserved control word
; 0x0FE00000 (§5.3), which halts with R1 and R2 as the trap left them. The
; emulator reports a reserved control instruction and exits with status 2,
; so a trap does not look like the normal end of the program.
___wasm_trap
        .DAT    0x0FE00000

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

; __udivmod64: R1:R2 = R1:R2 / R3:R4 and R5:R6 = R1:R2 % R3:R4, unsigned.
; Not a C routine: __udiv64, __umod64, __div64, and __mod64 share it. The
; same restoring division as __udivmod, with 64 passes. All six registers
; hold operands, so four words on the stack hold the passes to go, the
; remainder's bit 64, and the remainder minus the divisor. Every pass
; takes 13 steps, so __udivmod64 takes 4 + 64 * 13 + 2 = 838.
__udivmod64
        MOVE    R5, 0                   ; remainder
        MOVE    R6, 0
        SUB     R13, R13, 3             ; @1[R13]: bit 64, @2 and @3: the difference
        MOVE    @--R13, 64              ; @R13: passes to go
__udivmod64.loop
        C<0[M]  R1, R1, 1               ; C = next dividend bit
        C<C[M]  R2, R2, 1
        C<C[M]  R5, R5, 1               ; into the remainder
        C<C[M]  R6, R6, 1               ; C = its bit 64
        ADD[C]  @1[R13], R0, R0
        SUB[M]  @2[R13], R5, R3
        SUB[CM] @3[R13], R6, R4
        SUB[CM] R0, @1[R13], 0          ; C = the remainder < R3:R4
        ?!C MOVE R5, @2[R13]
        ?!C MOVE R6, @3[R13]
        ?!C OR  R1, R1, 1
        DEC[M]  @R13, @R13
        ?!Z MOVE R15, __udivmod64.loop
        ADD     R13, R13, 4
        MOVE    R15, @R13++

; __udiv64: R1:R2 = R1:R2 / R3:R4, unsigned. 1 + 838 = 839 steps.
__udiv64
        MOVE    R15, __udivmod64        ; which returns to our caller

; __umod64: R1:R2 = R1:R2 % R3:R4, unsigned. 5 + 838 = 843 steps.
__umod64
        ADD     @--R13, 2, R15
        MOVE    R15, __udivmod64
        MOVE    R1, R5
        MOVE    R2, R6
        MOVE    R15, @R13++

; __div64: R1:R2 = R1:R2 / R3:R4, signed, rounding toward zero. Like __div.
; Negating a pair takes two instructions, so the signs are tested with
; jumps. Steps: 1 + a + b + 2 + 838 + q, where a and b are 2 for an
; operand that is not negative and 4 for one that is, and q is 2 for a
; quotient that is not negated and 5 for one that is.
__div64 XOR     @--R13, R2, R4          ; bit 31: the signs differ
        MOVE[M] R2, R2
        ?!N MOVE R15, __div64.a
        SUB[M]  R1, 0, R1
        SUB[C]  R2, 0, R2
__div64.a
        MOVE[M] R4, R4
        ?!N MOVE R15, __div64.b
        SUB[M]  R3, 0, R3
        SUB[C]  R4, 0, R4
__div64.b
        ADD     @--R13, 2, R15
        MOVE    R15, __udivmod64
        MOVE[M] R0, @R13++
        ?!N MOVE R15, @R13++
        SUB[M]  R1, 0, R1
        SUB[C]  R2, 0, R2
        MOVE    R15, @R13++

; __mod64: R1:R2 = R1:R2 % R3:R4, signed, with the dividend's sign. Steps:
; 1 + a + b + 2 + 838 + 2 + q, with a, b, and q as for __div64.
__mod64 MOVE    @--R13, R2              ; bit 31: the dividend's sign
        MOVE[M] R2, R2
        ?!N MOVE R15, __mod64.a
        SUB[M]  R1, 0, R1
        SUB[C]  R2, 0, R2
__mod64.a
        MOVE[M] R4, R4
        ?!N MOVE R15, __mod64.b
        SUB[M]  R3, 0, R3
        SUB[C]  R4, 0, R4
__mod64.b
        ADD     @--R13, 2, R15
        MOVE    R15, __udivmod64
        MOVE    R1, R5
        MOVE    R2, R6
        MOVE[M] R0, @R13++
        ?!N MOVE R15, @R13++
        SUB[M]  R1, 0, R1
        SUB[C]  R2, 0, R2
        MOVE    R15, @R13++

; __clz: R1 = the number of leading 0 bits in R1, 32 for 0. Shifts R1
; right until it is 0, counting down from 32. Steps: 3 for 0, else 4 + 3k,
; where k is the number of bits in R1. Uses R2.
__clz   MOVE[M] R2, R1
        MOVE    R1, 32
        ?Z MOVE R15, @R13++
__clz.loop
        DEC     R1, R1
        SHR[M]  R2, R2, 1
        ?!Z MOVE R15, __clz.loop
        MOVE    R15, @R13++

; __ctz: R1 = the number of trailing 0 bits in R1, 32 for 0. Steps: 3 for
; 0, else 6 + 4t, where t is the result. Uses R2.
__ctz   MOVE[M] R2, R1
        MOVE    R1, 32
        ?Z MOVE R15, @R13++
        MOVE    R1, 0
__ctz.loop
        0>C[M]  R2, R2, 1               ; C = the bit shifted out
        ?C MOVE R15, @R13++
        ADD     R1, R1, 1
        MOVE    R15, __ctz.loop

; __popcnt: R1 = the number of 1 bits in R1. Steps: 3 + 3k, where k is
; the number of bits in R1 (1 if it is 0). Uses R2.
__popcnt
        MOVE    R2, R1
        MOVE    R1, 0
__popcnt.loop
        0>C[M]  R2, R2, 1               ; C = the bit shifted out, Z = none left
        ADD[C]  R1, R1, 0               ; add C
        ?!Z MOVE R15, __popcnt.loop
        MOVE    R15, @R13++

; __clz64, __ctz64, __popcnt64: R1:R2 = the same counts for the 64-bit
; number in R1:R2. The result is at most 64, so R2 = 0.
; __clz64 steps: 7 + __clz(R2) if R2 is not 0, else 7 + __clz(R1).
__clz64 MOVE[M] R0, R2
        ?Z MOVE R15, __clz64.lo
        MOVE    R1, R2
        ADD     @--R13, 2, R15
        MOVE    R15, __clz
        MOVE    R2, 0
        MOVE    R15, @R13++
__clz64.lo
        ADD     @--R13, 2, R15
        MOVE    R15, __clz
        ADD     R1, R1, 32
        MOVE    R2, 0
        MOVE    R15, @R13++

; __ctz64 steps: 6 + __ctz(R1) if R1 is not 0, else 8 + __ctz(R2).
__ctz64 MOVE[M] R0, R1
        ?Z MOVE R15, __ctz64.hi
        ADD     @--R13, 2, R15
        MOVE    R15, __ctz
        MOVE    R2, 0
        MOVE    R15, @R13++
__ctz64.hi
        MOVE    R1, R2
        ADD     @--R13, 2, R15
        MOVE    R15, __ctz
        ADD     R1, R1, 32
        MOVE    R2, 0
        MOVE    R15, @R13++

; __popcnt64 steps: 10 + __popcnt(R1) + __popcnt(R2). Uses R3 and R4.
__popcnt64
        MOVE    R4, R2
        ADD     @--R13, 2, R15
        MOVE    R15, __popcnt
        MOVE    R3, R1
        MOVE    R1, R4
        ADD     @--R13, 2, R15
        MOVE    R15, __popcnt
        ADD     R1, R1, R3
        MOVE    R2, 0
        MOVE    R15, @R13++
