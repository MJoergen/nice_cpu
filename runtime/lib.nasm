; The NICE runtime library (doc/ISA.md §9.3). It goes after the program's
; own files, followed by muldiv_mpu.nasm or muldiv_soft.nasm, which hold the
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

; The device routines of §9.3: the console (SYSTEM §1), the performance counters
; (SYSTEM §3), and the emulator's character screen. Unlike the routines above,
; programs call them by their C names.
__nice.console  .EQU    0xFFFFFF00
__nice.cycle_lo .EQU    0xFFFFFF40
__nice.cycle_hi .EQU    0xFFFFFF41
__nice.instr_lo .EQU    0xFFFFFF42
__nice.instr_hi .EQU    0xFFFFFF43
__nice.screen   .EQU    0xFFFF0000              ; 80 columns, 25 rows

; nice_putc: writes bits 7..0 of R1 to the console. 2 steps.
_nice_putc
        MOVE    @__nice.console, R1
        MOVE    R15, @R13++

; nice_getc: R1 = the next input byte, waiting until there is one, or -1
; once the input has ended. A console read returns the byte with bit 8 set,
; 0 if none is waiting, or 0x200 at the end. Steps: 4 for a byte, 8 at the
; end, and 6 more for each read that finds no byte. Skipped instructions
; count as steps.
_nice_getc
        MOVE    R1, @__nice.console
        AND[M]  R0, R1, 0x100
        ?!Z AND R1, R1, 0xFF
        ?!Z MOVE R15, @R13++
        AND[M]  R0, R1, 0x200
        ?Z MOVE R15, _nice_getc
        MOVE    R1, -1
        MOVE    R15, @R13++

; nice_pollc: as nice_getc, but with one read: R1 = -2 if no byte is
; waiting. Steps: 4 for a byte, 8 otherwise.
_nice_pollc
        MOVE    R1, @__nice.console
        AND[M]  R0, R1, 0x100
        ?!Z AND R1, R1, 0xFF
        ?!Z MOVE R15, @R13++
        AND[M]  R0, R1, 0x200
        MOVE    R1, -2
        ?!Z MOVE R1, -1
        MOVE    R15, @R13++

; nice_print: writes the string at R1, one character per word, up to its
; first 0 word, to the console. Steps: 2 + 4n for n characters. Uses R2.
_nice_print
        MOVE[M] R2, @R1++
        ?Z MOVE R15, @R13++
        MOVE    @__nice.console, R2
        MOVE    R15, _nice_print

; nice_cycles, nice_instructions: R1:R2 = the counter, low word first.
; The read of the low word takes the snapshot that the read of the high
; word returns (SYSTEM §3). 3 steps.
_nice_cycles
        MOVE    R1, @__nice.cycle_lo
        MOVE    R2, @__nice.cycle_hi
        MOVE    R15, @R13++

_nice_instructions
        MOVE    R1, @__nice.instr_lo
        MOVE    R2, @__nice.instr_hi
        MOVE    R15, @R13++

; nice_screen_put: writes R3 to the screen at column R1 and row R2, the
; word 80 * R2 + R1. 80 * R2 = 64 * R2 + 16 * R2. 6 steps. Uses R2 and R4.
_nice_screen_put
        SHL     R4, R2, 6
        SHL     R2, R2, 4
        ADD     R2, R2, R4
        ADD     R2, R2, R1
        MOVE    @__nice.screen[R2], R3
        MOVE    R15, @R13++

; nice_screen_clear: writes 0x20 to the 2000 words of the screen, from the
; last down to the first. 6002 steps. Uses R1.
_nice_screen_clear
        MOVE    R1, 2000
_nice_screen_clear.loop
        DEC[M]  R1, R1
        MOVE    @__nice.screen[R1], 0x20
        ?!Z MOVE R15, _nice_screen_clear.loop
        MOVE    R15, @R13++
