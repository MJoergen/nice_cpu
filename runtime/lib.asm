; The NICE runtime library (doc/ISA.md §9.3). It goes after the program's
; own files, followed by muldiv_mpu.asm or muldiv_soft.asm, which hold the
; multiply and divide routines. Every routine follows the C ABI of §9.3.

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
