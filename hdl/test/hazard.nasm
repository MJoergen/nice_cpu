; The hazards of MICROARCH.md §5, each with no padding between the
; instructions that make it, for step 4 of the test order in MICROARCH.md §9.
; qnice_cpu's test/prog_hazard.asm and test/prog_pipeline.asm are the model.
;
;   1. Flags set by one instruction and tested by the next (§5.2).
;   2. Conditional data accesses after a write of SR (§5.2 and §5.3).
;   3. Registers written by one instruction and read by the next (§5.1).
;   4. R14 and R15 as pointers and with side effects (§5.4).
;   5. Stores into the next few instructions (§5.5).
;   6. Jumps over HALT (§5.4).
;
; The program checks itself. R12 holds the number of the section. A failed
; check jumps to fail, a reserved control word, so the program ends with
; exit status 2 instead of 0, and R12 names the section. The makefile
; checks that the emulator's run exits with 0, and then compares the core's
; trace with the emulator's. Every pair of side effects on one register is
; in sidefx_prog.py.
;
; The program runs with an NMI or an IRQ before any one of its steps, for
; step 5 of the test order (test/irq_sweep.py), and still passes its checks.
; So E = 1 almost everywhere, and VBASE is 0, 1, or 2 at every instruction
; boundary, each with a vector table entry for NMI (vector 8) and IRQ
; (vector 9). The routines change the flags, which RTI restores.
COUNT   .EQU    0xFFFFFF01      ; the read counter (SYSTEM.md §1)
SP      .EQU    R13
PC      .EQU    R15

NMI     .EQU    8               ; the vectors of test/irq_sweep.py
IRQ     .EQU    9

        MOVE    PC, start       ; words 0,1
        .ORG    4
        .DAT    isr             ; vector 4, for INT 4 (VBASE = 0)
        .ORG    NMI
        .DAT    nmi, irq
        .ORG    0x100+NMI
        .DAT    nmi, irq
        .ORG    0x200+NMI
        .DAT    nmi, irq

        .ORG    0x300
start   MOVE    SP, stack
        MOVE    R14, 0x40000000 ; E = 1

; 1. Each flag is set by a direct write of R14 and cleared by an instruction
; with M set, which the next instruction tests. Then it is set by an
; instruction with M set, which the next instruction tests again. A
; condition that reads SR from before the instruction in front of it gets
; each test wrong. R1 counts the instructions that run, and adds 0x100 for
; each that should have been skipped.
        MOVE    R12, 1
        MOVE    R1, 0
        MOVE    R2, 0x7FFFFFFF
        MOVE    R14, 0x49000000 ; Z = 1
        ADD[M]  R0, R0, 1       ; Z = 0
        ?Z ADD  R1, R1, 0x100
        SUB[M]  R0, R2, R2      ; Z = 1
        ?Z ADD  R1, R1, 1       ; 1
        MOVE    R14, 0x45000000 ; C = 1
        ADD[M]  R0, R0, R0      ; C = 0
        ?C ADD  R1, R1, 0x100
        SUB[M]  R0, R0, 1       ; C = 1
        ?C ADD  R1, R1, 1       ; 2
        MOVE    R14, 0x43000000 ; X = 1
        MOVE[M] R0, R2          ; X = 0
        ?X ADD  R1, R1, 0x100
        NOT[M]  R0, R0          ; X = 1
        ?X ADD  R1, R1, 1       ; 3
        MOVE    R14, 0x51000000 ; N = 1
        MOVE[M] R0, R2          ; N = 0
        ?N ADD  R1, R1, 0x100
        ADD[M]  R0, R2, 1       ; N = 1, V = 1
        ?N ADD  R1, R1, 1       ; 4
        MOVE    R14, 0x61000000 ; V = 1
        ADD[M]  R0, R2, 0       ; V = 0
        ?V ADD  R1, R1, 0x100
        ADD[M]  R0, R2, 1       ; V = 1
        ?V ADD  R1, R1, 1       ; 5
        MOVE    R14, 0x49000000 ; Z = 1
        ADD[M]  R0, R0, 1       ; Z = 0
        ?!Z ADD R1, R1, 1       ; 6
; I is changed only by writes of R14, here direct ones.
        MOVE    R14, 0xC1000000 ; I = 1
        ?I ADD  R1, R1, 1       ; 7
        AND     R14, R14, 0x7FFFFFFF ; I = 0
        ?I ADD  R1, R1, 0x100
; R14 changed by the side effect of its destination, then tested. Bit 24
; is set by each of the two writes. A side effect can carry into the flags
; only from VBASE = 0xFFFFFF, so the values pass through it within the
; instruction. Between instructions, the vector table would be in the I/O
; range.
        MOVE    R14++, 0x40FFFFFF ; 0x41FFFFFF, then 0x42000000 + bit 24
        ?X ADD  R1, R1, 1       ; 8
        MOVE    R14++, 0x4AFFFFFF ; 0x4BFFFFFF, then 0x4C000000 + bit 24
        ?C ADD  R1, R1, 1       ; 9
        ?Z ADD  R1, R1, 1       ; 10
        ?X ADD  R1, R1, 0x100
; An instruction with M set and R14 as a register destination computes no
; flags, though its result is 0. It clears E too, and an IRQ waits until
; the OR sets it again.
        MOVE[M] R14, 0          ; R14 = 0x01000000: Z = 0
        ?Z ADD  R1, R1, 0x100
        OR      R14, R14, 0x40000000
; An instruction without M keeps the flags.
        SUB[M]  R0, R0, R0      ; Z = 1
        ADD     R3, R0, 1
        ?Z ADD  R1, R1, 1       ; 11
; C as the carry input and as the fill bit of a shift, from the instruction
; before.
        MOVE    R4, 0xFFFFFFFF
        ADD[M]  R5, R4, 1       ; R5 = 0, C = 1
        ADD[CM] R6, R0, 0       ; R6 = 1, C = 0
        ADD[CM] R7, R0, 0       ; R7 = 0
        SUB[M]  R0, R0, 1       ; C = 1
        0<C     R8, R0, 1       ; R8 = 1
        SUB[M]  R0, R1, 11
        ?!Z MOVE PC, fail
        SUB[M]  R0, R5, 0
        ?!Z MOVE PC, fail
        SUB[M]  R0, R6, 1
        ?!Z MOVE PC, fail
        SUB[M]  R0, R7, 0
        ?!Z MOVE PC, fail
        SUB[M]  R0, R8, 1
        ?!Z MOVE PC, fail

; 2. Conditional reads and stores right after the instruction that decides
; their condition. The read counter shows the reads that happen.
        MOVE    R12, 2
        MOVE    R4, COUNT
        MOVE    R3, data
        MOVE    R5, 0x55
        MOVE    R7, 0x55
        MOVE    @R4, 0          ; count 0
        ADD[M]  R0, R0, 1       ; Z = 0
        ?Z MOVE R5, @R4         ; skipped: no read
        ?!Z MOVE R6, @R4        ; R6 = 0, count 1
        SUB[M]  R0, R0, R0      ; Z = 1
        ?!Z MOVE R7, @R3++      ; skipped: no read and no increment
        ?Z MOVE R8, @R4         ; R8 = 1, count 2
        ADD[M]  R0, R0, 1       ; Z = 0
        ?Z MOVE @R4, 50         ; skipped: no write
        ?!Z MOVE R9, @R4        ; R9 = 2, count 3
        SUB[M]  R0, R0, R0      ; Z = 1
        ?Z MOVE @R3++, 0x77     ; data = 0x77, R3 = data + 1
        ADD[M]  R0, R0, 1       ; Z = 0
        ?Z MOVE @R3++, 0x88     ; skipped
        ?!Z ADD R10, @R4, @--R3 ; 3 + 0x77: R10 = 0x7A, R3 = data, count 4
        MOVE    R11, @R4        ; R11 = 4
        SUB[M]  R0, R5, 0x55
        ?!Z MOVE PC, fail
        SUB[M]  R0, R6, 0
        ?!Z MOVE PC, fail
        SUB[M]  R0, R7, 0x55
        ?!Z MOVE PC, fail
        SUB[M]  R0, R8, 1
        ?!Z MOVE PC, fail
        SUB[M]  R0, R9, 2
        ?!Z MOVE PC, fail
        SUB[M]  R0, R10, 0x7A
        ?!Z MOVE PC, fail
        SUB[M]  R0, R11, 4
        ?!Z MOVE PC, fail
        SUB[M]  R0, R3, data
        ?!Z MOVE PC, fail
        SUB[M]  R0, @data+1, 0  ; the skipped store left data + 1 alone
        ?!Z MOVE PC, fail

; 3. A register written by one instruction and read by the next: as s0 and
; s1, as a pointer in each field, as the base of a constant, and after a
; side effect. Some reads are two instructions after the write.
        MOVE    R12, 3
        MOVE    R1, 5
        ADD     R2, R1, R1      ; R2 = 10
        SUB     R3, R0, R2      ; R3 = -10
        MOVE    R4, data+1
        MOVE    @R4, R3         ; data + 1 = -10
        MOVE    R5, data
        ADD     R6, @R5, @R4    ; 0x77 - 10 = 0x6D
        MOVE    R7, data-3
        MOVE    R8, @3[R7]      ; R8 = 0x77
        MOVE    R7, 2
        ADD     R8, R8, 1[R7]   ; R8 = 0x77 + 3 = 0x7A
        MOVE    R9, @R5++       ; R9 = 0x77, R5 = data + 1
        MOVE    R10, @R5        ; R10 = -10
        MOVE    @--R5, R10      ; data = -10, R5 = data
        MOVE    R11, @R5        ; R11 = -10
        SUB[M]  R0, R6, 0x6D
        ?!Z MOVE PC, fail
        SUB[M]  R0, R8, 0x7A
        ?!Z MOVE PC, fail
        SUB[M]  R0, R9, 0x77
        ?!Z MOVE PC, fail
        SUB[M]  R0, R11, -10
        ?!Z MOVE PC, fail
; A chain through four instructions, and the two writes of a register
; destination with a side effect, merged.
        MOVE    R1, 7
        MOVE    R2, R1
        MOVE    R3, R2
        MOVE    R4, R3
        MOVE    R1++, R4        ; R1 = 8
        ADD     R2, R1, R1      ; R2 = 16
        MOVE    R2--, R2        ; R2 = 15
        SUB[M]  R0, R2, 15
        ?!Z MOVE PC, fail
; A skipped instruction writes nothing, and its side effects do not happen.
        MOVE    R1, 7
        ?!1 MOVE R1, 9
        MOVE    R2, R1          ; R2 = 7
        ?!1 MOVE R3, @R1++
        MOVE    R3, R1          ; R3 = 7
        ?!1 MOVE R1++, 9
        ADD     R3, R3, R1      ; R3 = 14
        SUB[M]  R0, R2, 7
        ?!Z MOVE PC, fail
        SUB[M]  R0, R3, 14
        ?!Z MOVE PC, fail
; A pop, which takes two micro-operations, then a read of both registers it
; writes. Then s1 reads the register that s0 changes.
        MOVE    @--SP, 0x30     ; push
        MOVE    R4, @SP++       ; pop: R4 = 0x30
        ADD     R5, SP, R4      ; R5 = stack + 0x30
        SUB[M]  R0, R5, stack+0x30
        ?!Z MOVE PC, fail
        MOVE    R2, data+4
        MOVE    @R2, 0x100
        MOVE    @1[R2], 0x200   ; data + 5 = 0x200
        ADD     R1, R2++, R2    ; R1 = (data + 4) + (data + 5)
        ADD     R3, @R2, @--R2  ; R3 = 0x200 + 0x100, R2 = data + 4
        SUB[M]  R0, R1, data+data+9
        ?!Z MOVE PC, fail
        SUB[M]  R0, R3, 0x300
        ?!Z MOVE PC, fail
        SUB[M]  R0, R2, data+4
        ?!Z MOVE PC, fail

; 4. R14 and R15 as pointers. R14 = 0x41000000 points to the words at
; r14data. When an instruction with M set changes the flags, R14 points
; elsewhere.
        MOVE    R12, 4
        MOVE    R14, 0x41000000
        MOVE    R1, @R14        ; R1 = 0x14
        MOVE    R2, @R14++      ; R2 = 0x14, R14 = 0x41000001
        MOVE    R3, @R14        ; R3 = 0x15
        MOVE    @R14++, 0x16    ; R14 = 0x41000002
        MOVE    R4, @--R14      ; R4 = 0x16, R14 = 0x41000001
        MOVE    R14, 0x41000000
        SUB[M]  R0, R0, R0      ; Z = 1: R14 = 0x49000000
        MOVE    R5, @R14        ; R5 = 0x94
        ADD     R6, R1, R2
        ADD     R6, R6, R3
        ADD     R6, R6, R4      ; R6 = 0x14 + 0x14 + 0x15 + 0x16 = 0x53
        SUB[M]  R0, R6, 0x53
        ?!Z MOVE PC, fail
        SUB[M]  R0, R5, 0x94
        ?!Z MOVE PC, fail
; R15 reads as the address of the next instruction, also as a pointer.
        MOVE    R1, @R15        ; the word at x1
x1      SUB[M]  R0, R1, @x1
        ?!Z MOVE PC, fail
        MOVE    R1, @R15++      ; reads the HALT and jumps over it
        HALT
        SUB[M]  R0, R1, 0x0C000000
        ?!Z MOVE PC, fail
        MOVE    R1, @2[R15]     ; the word after the jump: 0x1234
        MOVE    PC, x2
        .DAT    0x1234
x2      SUB[M]  R0, R1, 0x1234
        ?!Z MOVE PC, fail
        MOVE    R1, R15++       ; jumps over the HALT, R1 = x3
x3      HALT
        SUB[M]  R0, R1, x3
        ?!Z MOVE PC, fail
; s0 moves R15 back onto the constant word of s1, which s1 then reads as
; its base: R1 = x4 + 1. The next instruction is that constant word, 0,
; a NOP.
x4      ADD     R1, @--R15, 0[R15]
        SUB[M]  R0, R1, x4+1
        ?!Z MOVE PC, fail
        MOVE    R15++, x5       ; R15 = x5 + 1
x5      HALT
        MOVE    R15--, x6+1     ; R15 = x6
        HALT
x6      MOVE    R14, 0x41000000 ; VBASE = 0 again, for INT 4 in section 6

; 5. Stores into the words just fetched (MICROARCH.md §5.5): a NOP over a
; HALT in the next word and up to six words further, through a constant
; address, a pointer, and R15, a new constant word for the next
; instruction, the target of a jump, and the storing instruction's own
; words.
        MOVE    R12, 5
        MOVE    @n1, 0          ; 3 words
n1      HALT
        MOVE    @n2, 0
        MOVE    R0, R0
n2      HALT
        MOVE    @n3, 0
        MOVE    R0, R0
        MOVE    R0, R0
n3      HALT
        MOVE    @n4, 0
        MOVE    R0, R0
        MOVE    R0, R0
        MOVE    R0, R0
n4      HALT
        MOVE    @n7, 0
        MOVE    R1, 1           ; 2 words
        MOVE    R1, 2           ; 2 words
        MOVE    R1, 3           ; 2 words
n7      HALT
        MOVE    R2, n8
        MOVE    @R2, 0
n8      HALT
        MOVE    R2, n9
        MOVE    @R2++, 0        ; R2 = n9 + 1
n9      HALT
        SUB[M]  R0, R2, n9+1
        ?!Z MOVE PC, fail
        MOVE    @R15, 0         ; the next word
        HALT
        MOVE    @R15++, 0       ; the next word, and jump over it
        HALT
        MOVE    1[R15], 0       ; the word after the next
        MOVE    R0, R0
        HALT
        MOVE    @k1+1, 0x55     ; the constant word of the next instruction
k1      MOVE    R1, 0x11        ; R1 = 0x55
        SUB[M]  R0, R1, 0x55
        ?!Z MOVE PC, fail
        MOVE    @t1, 0
        MOVE    PC, t1          ; DECODE can resolve this jump
        HALT
t1      HALT
; The destination moves R15 back onto the instruction's constant word and
; stores into it, which changes ONE R6 to ONE R7. That word runs next.
; R7 = 0x4000 before.
        MOVE    R6, 6
        MOVE    R7, 0x4000
        ADD     @--R15, R7, 0x01C18000
        SUB[M]  R0, R6, 6
        ?!Z MOVE PC, fail
        SUB[M]  R0, R7, 1
        ?!Z MOVE PC, fail
; A loop of two passes changes its own code. The first ADD adds 1 in the
; first pass and 10 in the second. The ADD at s1 stores into its own
; constant word, which it reads in the next pass: 1 + 5 = 6, then 11 + 6.
        MOVE    R1, 0
        MOVE    R3, 2
loop1   ADD     R1, R1, 1
        MOVE    @loop1+1, 10
s1      ADD     @s1+2, R1, 5    ; s1 + 2 holds the constant 5
        SUB[M]  R3, R3, 1
        ?!Z MOVE PC, loop1
        SUB[M]  R0, R1, 11
        ?!Z MOVE PC, fail
        SUB[M]  R0, @s1+2, 17
        ?!Z MOVE PC, fail

; 6. Jumps over HALT: unconditional and conditional, through a register,
; through memory, by a side effect, to a jump, to the next instruction,
; into the constant word of an instruction, and with INT and RTI.
        MOVE    R12, 6
        MOVE    PC, j1
        HALT
        HALT
j1      ADD     PC, PC, 2
        HALT
        HALT
        SUB[M]  R0, R0, R0      ; Z = 1
        ?Z MOVE PC, j2
        HALT
j2      ?!Z MOVE PC, fail       ; not taken
        ?!Z HALT                ; skipped
        .DAT    0x8FE00000      ; a reserved word, never run: skipped
        MOVE    R2, j3
        MOVE    PC, R2
        HALT
j3      MOVE    PC, @jt3
        HALT
j4      ADD[M]  R0, R0, R0      ; Z = 1
        ?Z MOVE PC, @jt4
        HALT
j5      ADD[M]  R0, R0, 1       ; Z = 0
        ?Z MOVE PC, @jtf        ; skipped, with no read
        MOVE    PC, j6
j6      MOVE    PC, j7
        HALT
j7      MOVE    PC, j8
j8      ADD     @--SP, 2, PC    ; call
        MOVE    PC, subr
        MOVE    R0, R15++       ; jumps over the HALT
        HALT
        MOVE    R7, 0
        MOVE    PC, j9+1        ; to the constant word: ONE R7
        HALT
j9      MOVE    R1, 0x01C1C000
        SUB[M]  R0, R7, 1
        ?!Z MOVE PC, fail
; INT right after the instruction that decides its condition. The routine
; clears Z, and the instruction after RTI tests Z as it was before INT.
        MOVE    R7, 0
        ADD[M]  R0, R0, 1       ; Z = 0
        ?Z INT  4               ; skipped
        SUB[M]  R0, R0, R0      ; Z = 1
        ?Z INT  4               ; R7 = 1
        ?Z ADD  R7, R7, 0x10    ; R7 = 0x11
        SUB[M]  R0, R7, 0x11
        ?!Z MOVE PC, fail
        MOVE    R12, 0          ; passed
        HALT

; The routine of INT 4. It clears Z, which RTI restores.
isr     ADD[M]  R7, R7, 1       ; Z = 0
        RTI

; The routines of NMI and IRQ. Each counts itself and changes the flags.
nmi     ADD[M]  @nmis, @nmis, 1
        RTI
irq     ADD[M]  @irqs, @irqs, 1
        RTI

; A subroutine that returns at once: the jump reads its target from memory.
subr    MOVE    PC, @SP++

fail    .DAT    0x0FE00000      ; a reserved word: halts with status 2

jt3     .DAT    j4
jt4     .DAT    j5
jtf     .DAT    fail
nmis    .DAT    0
irqs    .DAT    0

        .ORG    0x800
data    .BLK    16
        .ORG    0x8F0
        .BLK    16
stack

        .ORG    0x41000000
r14data .DAT    0x14, 0x15
        .ORG    0x49000000
        .DAT    0x94
