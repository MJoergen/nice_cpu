; bench.c by hand: the same benchmark in NICE assembly, written as well as
; a programmer can, for comparison with what nicewasm makes of bench.wasm.
;
; The rules it keeps to, so that the two measure the same work:
; - The same phases, sizes, algorithms, and results as bench.c, and the
;   same table. The tricks are at the instruction level: operands in
;   memory, conditional instructions instead of jumps, flags from the
;   operation itself, side effects on pointers, tail calls, and the math
;   unit used directly, with an operand left in place where it does not
;   change.
; - A conditional jump back that is mostly taken, such as a loop's back
;   edge, is ADD PC, PC, label-next, where next labels the instruction
;   after the jump. DECODE predicts it taken, so it costs what an
;   unconditional jump does (MICROARCH.md §5.4). One that is mostly
;   skipped stays a MOVE PC, label, which costs nothing when skipped. A
;   loop is laid out so that its hot jump goes back: a block that is
;   mostly reached by a jump is placed before the jump (str.diff).
; - A conditional return is a MOVE PC, label to a MOVE PC, @SP++ that
;   others share (hs.ret). Skipped, it costs nothing, where a conditional
;   MOVE PC, @SP++ costs the two cycles of its read and its jump.
; - The data layout is the natural one for a word-addressed machine. The
;   byte buffer stays packed, four bytes to a word, as in linear memory.
;   The strings have one character per word, as a C char does in ISA.md
;   ABI.md, the interpreter's program has one word per opcode or operand, and
;   pointers are word addresses. The tree's nodes are four words, as in
;   the wasm version.
; - The C library routines of the strings phase are written inline.
;
; Joined with runtime/start.nasm, which calls _main (ABI.md). The
; phases may use R1-R12; main keeps nothing in registers across them.

PC              .EQU    R15
SP              .EQU    R13

CONSOLE         .EQU    0xFFFFFF00
CYC_LO          .EQU    0xFFFFFF40
CYC_HI          .EQU    0xFFFFFF41
INS_LO          .EQU    0xFFFFFF42
INS_HI          .EQU    0xFFFFFF43
MPU_A           .EQU    0xFFFFFF20
MPU_B           .EQU    0xFFFFFF21
UMUL_LO         .EQU    0xFFFFFF24
UMUL_HI         .EQU    0xFFFFFF25
UDIV_R          .EQU    0xFFFFFF29
MPU_C_LO        .EQU    0xFFFFFF30
MPU_C_HI        .EQU    0xFFFFFF31
MPU_D_LO        .EQU    0xFFFFFF32
MPU_D_HI        .EQU    0xFFFFFF33
UDIV64_Q_LO     .EQU    0xFFFFFF38
UDIV64_Q_HI     .EQU    0xFFFFFF39
UDIV64_R_LO     .EQU    0xFFFFFF3A

; The sizes, as in bench.c.
BUF_WORDS       .EQU    1024            ; 4096 bytes, four to a word
ARR_WORDS       .EQU    1024
VM_LOOPS        .EQU    2000
STR_COUNT       .EQU    64
STR_MAXLEN      .EQU    12

; From expected.py, as in bench.c.
EXPECT_RNG64    .EQU    0x0E18CD0A
EXPECT_CRC32    .EQU    0x2DF3B109
EXPECT_BST      .EQU    0x55A72225
EXPECT_HEAPSORT .EQU    0xBDB22882
EXPECT_VM       .EQU    0x04156880
EXPECT_STRINGS  .EQU    0xD9867CF6

FNV_BASIS       .EQU    0x811C9DC5
FNV_PRIME       .EQU    16777619
SIGN_N          .EQU    0x10000000      ; the N flag in R14 (ISA.md §9.2)

; ---------------------------------------------------------------------------
; main: prints the header, runs each phase through run, prints the total,
; and returns the number of phases with a wrong result.

_main           MOVE    @--SP, R7
                MOVE    @--SP, R8
                MOVE    @--SP, R9
                MOVE    @--SP, R10
                MOVE    @--SP, R11
                MOVE    @--SP, R12
                MOVE    R1, header
                ADD     @--SP, 2, PC
                MOVE    PC, puts
                MOVE    @CONSOLE, 10

                MOVE    R1, name.rng64
                MOVE    R2, rng64
                MOVE    R3, EXPECT_RNG64
                ADD     @--SP, 2, PC
                MOVE    PC, run
                MOVE    R1, name.crc32
                MOVE    R2, crc32
                MOVE    R3, EXPECT_CRC32
                ADD     @--SP, 2, PC
                MOVE    PC, run
                MOVE    R1, name.bst
                MOVE    R2, bst
                MOVE    R3, EXPECT_BST
                ADD     @--SP, 2, PC
                MOVE    PC, run
                MOVE    R1, name.heapsort
                MOVE    R2, heapsort
                MOVE    R3, EXPECT_HEAPSORT
                ADD     @--SP, 2, PC
                MOVE    PC, run
                MOVE    R1, name.vm
                MOVE    R2, vm
                MOVE    R3, EXPECT_VM
                ADD     @--SP, 2, PC
                MOVE    PC, run
                MOVE    R1, name.strings
                MOVE    R2, strings
                MOVE    R3, EXPECT_STRINGS
                ADD     @--SP, 2, PC
                MOVE    PC, run

                MOVE    R1, name.total
                ADD     @--SP, 2, PC
                MOVE    PC, puts
                MOVE    R1, @total.ins_lo
                MOVE    R2, @total.ins_hi
                ADD     @--SP, 2, PC
                MOVE    PC, print_u64
                MOVE    @CONSOLE, 32
                MOVE    R1, @total.cyc_lo
                MOVE    R2, @total.cyc_hi
                ADD     @--SP, 2, PC
                MOVE    PC, print_u64
                MOVE    @CONSOLE, 10

                MOVE    R1, @failures
                MOVE    R12, @SP++
                MOVE    R11, @SP++
                MOVE    R10, @SP++
                MOVE    R9, @SP++
                MOVE    R8, @SP++
                MOVE    R7, @SP++
                MOVE    PC, @SP++

; run: R1 = the name, R2 = the phase, R3 = the expected result. Reads the
; counters, calls the phase, and prints the row. The instructions counted
; are those between the two reads of INS_LO: the read of INS_HI, the two of
; the call, and the phase with its return.

run             MOVE    @run.name, R1
                MOVE    @run.expect, R3
                MOVE    @run.cyc_lo, @CYC_LO
                MOVE    @run.cyc_hi, @CYC_HI
                MOVE    @run.ins_lo, @INS_LO
                MOVE    @run.ins_hi, @INS_HI
                ADD     @--SP, 1, PC
                MOVE    PC, R2
                MOVE    R10, @INS_LO
                MOVE    R11, @INS_HI
                MOVE    R8, @CYC_LO
                MOVE    R9, @CYC_HI
                MOVE    R7, R1          ; the result
                SUB[M]  R10, R10, @run.ins_lo
                SUB[C]  R11, R11, @run.ins_hi
                SUB[M]  R8, R8, @run.cyc_lo
                SUB[C]  R9, R9, @run.cyc_hi
                ADD[M]  @total.ins_lo, @total.ins_lo, R10
                ADD[C]  @total.ins_hi, @total.ins_hi, R11
                ADD[M]  @total.cyc_lo, @total.cyc_lo, R8
                ADD[C]  @total.cyc_hi, @total.cyc_hi, R9
                MOVE    R1, @run.name
                ADD     @--SP, 2, PC
                MOVE    PC, puts
                MOVE    R1, R10
                MOVE    R2, R11
                ADD     @--SP, 2, PC
                MOVE    PC, print_u64
                MOVE    @CONSOLE, 32
                MOVE    R1, R8
                MOVE    R2, R9
                ADD     @--SP, 2, PC
                MOVE    PC, print_u64
                MOVE    @CONSOLE, 32
                MOVE    @CONSOLE, 32
                MOVE    R1, R7
                ADD     @--SP, 2, PC
                MOVE    PC, print_hex
                MOVE    R1, str.ok
                SUB[M]  R0, R7, @run.expect
        ?!Z     MOVE    R1, str.fail
        ?!Z     ADD     @failures, @failures, 1
                ADD     @--SP, 2, PC
                MOVE    PC, puts
                MOVE    @CONSOLE, 10
                MOVE    PC, @SP++

; puts: prints the string at R1, one character per word, up to its 0.
; Uses R1 and R2.

puts            MOVE[M] R2, @R1++
        ?Z      MOVE    PC, @SP++
                MOVE    @CONSOLE, R2
                MOVE    PC, puts

; print_u64: prints R2:R1 in decimal, right-aligned in 12 characters. Uses
; the 64-bit division of the math unit, and R1-R4.

print_u64
                MOVE    R3, digits.end
                MOVE    @MPU_D_LO, 10
                MOVE    @MPU_D_HI, 0
pu.loop         MOVE    @MPU_C_LO, R1
                MOVE    @MPU_C_HI, R2
                ADD     @--R3, @UDIV64_R_LO, 48
                MOVE    R1, @UDIV64_Q_LO
                MOVE[M] R2, @UDIV64_Q_HI
        ?!Z     MOVE    PC, pu.loop
                MOVE[M] R0, R1
        ?!Z     ADD     PC, PC, pu.loop-pu.b1
pu.b1           SUB     R4, digits.end, R3  ; the digits
                SUB[M]  R4, 12, R4      ; the spaces before them
        ?C      MOVE    PC, pu.out      ; more than 12 digits
        ?Z      MOVE    PC, pu.out
pu.pad          MOVE    @CONSOLE, 32
                DEC[M]  R4, R4
        ?!Z     ADD     PC, PC, pu.pad-pu.out
pu.out          MOVE    R1, R3
                MOVE    PC, puts

; print_hex: prints R1 as 8 hex digits. Uses R1-R3.

print_hex
                MOVE    R3, 8
ph.loop         ROL     R1, R1, 4
                AND     R2, R1, 15
                ADD     R2, R2, 48
                SUB[M]  R0, R2, 58
        ?!C     ADD     R2, R2, 39      ; 58 + 39 = 97 = 'a'
                MOVE    @CONSOLE, R2
                DEC[M]  R3, R3
        ?!Z     ADD     PC, PC, ph.loop-ph.b1
ph.b1           MOVE    PC, @SP++

; ---------------------------------------------------------------------------
; rng64: xorshift64*, with the state in R2:R1. Each value takes three
; shift-and-xor steps of six instructions on the two words, then the 64-bit
; product in seven instructions through the math unit, which keeps one
; operand from the step before. The multiplier's words alternate in B, so
; the loops are unrolled by two. The buffer gets both words of 512 values
; and the array the high word of 1024 more.

rng64           MOVE    R1, 0x7F4A7C15  ; the seed
                MOVE    R2, 0x9E3779B9
                MOVE    R7, buf
                MOVE    R8, 256         ; pairs of values
                MOVE    @MPU_B, 0x4F6CDD1D  ; the multiplier's low word
rng.buf
                ; x ^= x >> 12
                SHR     R3, R1, 12
                SHL     R4, R2, 20
                OR      R3, R3, R4
                XOR     R1, R1, R3
                SHR     R3, R2, 12
                XOR     R2, R2, R3
                ; x ^= x << 25
                SHL     R3, R2, 25
                SHR     R4, R1, 7
                OR      R3, R3, R4
                XOR     R2, R2, R3
                SHL     R3, R1, 25
                XOR     R1, R1, R3
                ; x ^= x >> 27
                SHR     R3, R1, 27
                SHL     R4, R2, 5
                OR      R3, R3, R4
                XOR     R1, R1, R3
                SHR     R3, R2, 27
                XOR     R2, R2, R3
                ; v = x * M, with B = the low word of M
                MOVE    @MPU_A, R2
                MOVE    R6, @UMUL_LO    ; hi * Mlo
                MOVE    @MPU_A, R1
                MOVE    R5, @UMUL_LO    ; lo * Mlo
                ADD     R6, R6, @UMUL_HI
                MOVE    @MPU_B, 0x2545F491
                ADD     R6, R6, @UMUL_LO  ; lo * Mhi
                MOVE    @R7++, R5
                MOVE    @R7++, R6
                ; the same again, with B = the high word of M
                SHR     R3, R1, 12
                SHL     R4, R2, 20
                OR      R3, R3, R4
                XOR     R1, R1, R3
                SHR     R3, R2, 12
                XOR     R2, R2, R3
                SHL     R3, R2, 25
                SHR     R4, R1, 7
                OR      R3, R3, R4
                XOR     R2, R2, R3
                SHL     R3, R1, 25
                XOR     R1, R1, R3
                SHR     R3, R1, 27
                SHL     R4, R2, 5
                OR      R3, R3, R4
                XOR     R1, R1, R3
                SHR     R3, R2, 27
                XOR     R2, R2, R3
                MOVE    @MPU_A, R1
                MOVE    R6, @UMUL_LO    ; lo * Mhi
                MOVE    @MPU_B, 0x4F6CDD1D
                MOVE    R5, @UMUL_LO    ; lo * Mlo
                ADD     R6, R6, @UMUL_HI
                MOVE    @MPU_A, R2
                ADD     R6, R6, @UMUL_LO  ; hi * Mlo
                MOVE    @R7++, R5
                MOVE    @R7++, R6
                DEC[M]  R8, R8
        ?!Z     ADD     PC, PC, rng.buf-rng.b1

rng.b1
                MOVE    R7, arr
                MOVE    R8, 512
rng.arr
                SHR     R3, R1, 12
                SHL     R4, R2, 20
                OR      R3, R3, R4
                XOR     R1, R1, R3
                SHR     R3, R2, 12
                XOR     R2, R2, R3
                SHL     R3, R2, 25
                SHR     R4, R1, 7
                OR      R3, R3, R4
                XOR     R2, R2, R3
                SHL     R3, R1, 25
                XOR     R1, R1, R3
                SHR     R3, R1, 27
                SHL     R4, R2, 5
                OR      R3, R3, R4
                XOR     R1, R1, R3
                SHR     R3, R2, 27
                XOR     R2, R2, R3
                MOVE    @MPU_A, R2
                MOVE    R6, @UMUL_LO
                MOVE    @MPU_A, R1
                ADD     R6, R6, @UMUL_HI
                MOVE    @MPU_B, 0x2545F491
                ADD     @R7++, R6, @UMUL_LO  ; the high word only
                SHR     R3, R1, 12
                SHL     R4, R2, 20
                OR      R3, R3, R4
                XOR     R1, R1, R3
                SHR     R3, R2, 12
                XOR     R2, R2, R3
                SHL     R3, R2, 25
                SHR     R4, R1, 7
                OR      R3, R3, R4
                XOR     R2, R2, R3
                SHL     R3, R1, 25
                XOR     R1, R1, R3
                SHR     R3, R1, 27
                SHL     R4, R2, 5
                OR      R3, R3, R4
                XOR     R1, R1, R3
                SHR     R3, R2, 27
                XOR     R2, R2, R3
                MOVE    @MPU_A, R1
                MOVE    R6, @UMUL_LO
                MOVE    @MPU_B, 0x4F6CDD1D
                ADD     R6, R6, @UMUL_HI
                MOVE    @MPU_A, R2
                ADD     @R7++, R6, @UMUL_LO
                DEC[M]  R8, R8
        ?!Z     ADD     PC, PC, rng.arr-rng.b2
rng.b2          XOR     R1, R1, R2      ; the two words of the state
                MOVE    PC, @SP++

; ---------------------------------------------------------------------------
; crc32: the table first, with the bit shifted out going to C and the
; polynomial applied under ?C, then the sum, four bytes from each word.

crc32           MOVE    R3, table
crc.tab         SUB     R2, R3, table   ; the index
                0>C[M]  R2, R2, 1
        ?C      XOR     R2, R2, 0xEDB88320
                0>C[M]  R2, R2, 1
        ?C      XOR     R2, R2, 0xEDB88320
                0>C[M]  R2, R2, 1
        ?C      XOR     R2, R2, 0xEDB88320
                0>C[M]  R2, R2, 1
        ?C      XOR     R2, R2, 0xEDB88320
                0>C[M]  R2, R2, 1
        ?C      XOR     R2, R2, 0xEDB88320
                0>C[M]  R2, R2, 1
        ?C      XOR     R2, R2, 0xEDB88320
                0>C[M]  R2, R2, 1
        ?C      XOR     R2, R2, 0xEDB88320
                0>C[M]  R2, R2, 1
        ?C      XOR     R2, R2, 0xEDB88320
                MOVE    @R3++, R2
                SUB[M]  R0, R3, table+256
        ?!Z     ADD     PC, PC, crc.tab-crc.b1

crc.b1
                MOVE    R1, 0xFFFFFFFF  ; the crc
                MOVE    R3, buf
                MOVE    R5, BUF_WORDS
crc.sum         MOVE    R2, @R3++
                XOR     R4, R1, R2
                AND     R4, R4, 255
                SHR     R1, R1, 8
                XOR     R1, R1, @table[R4]
                SHR     R2, R2, 8
                XOR     R4, R1, R2
                AND     R4, R4, 255
                SHR     R1, R1, 8
                XOR     R1, R1, @table[R4]
                SHR     R2, R2, 8
                XOR     R4, R1, R2
                AND     R4, R4, 255
                SHR     R1, R1, 8
                XOR     R1, R1, @table[R4]
                SHR     R2, R2, 8
                XOR     R4, R1, R2
                AND     R4, R4, 255
                SHR     R1, R1, 8
                XOR     R1, R1, @table[R4]
                DEC[M]  R5, R5
        ?!Z     ADD     PC, PC, crc.sum-crc.b2
crc.b2          NOT     R1, R1
                MOVE    PC, @SP++

; ---------------------------------------------------------------------------
; bst: a node is four words: key, count, left, right. A null pointer is 0.
; The insertion keeps the address of the link to follow in R2, and picks
; left or right with one conditional instruction. The walk is recursive,
; with the hash in R3, and the call for the right child is a tail call.

bst             MOVE    R9, arr
                MOVE    R10, arr+ARR_WORDS
                MOVE    R11, nodes      ; the next free node
                MOVE    @root, 0
bst.ins         MOVE    R1, @R9++       ; the key
                MOVE    R2, root        ; the link
                MOVE[M] R3, @R2         ; the node it points to
        ?Z      MOVE    PC, bst.new
bst.walk
                SUB[M]  R0, R1, @R3     ; key - node's key
        ?Z      MOVE    PC, bst.dup
        ?V      XOR     R14, R14, SIGN_N
                ADD     R2, R3, 3       ; the right link
        ?N      SUB     R2, R2, 1       ; or the left one if key is less
                MOVE[M] R3, @R2
        ?!Z     ADD     PC, PC, bst.walk-bst.new
bst.new         MOVE    @R2, R11
                MOVE    @R11++, R1
                MOVE    @R11++, 1
                MOVE    @R11++, 0
                MOVE    @R11++, 0
bst.next
                SUB[M]  R0, R9, R10
        ?!Z     ADD     PC, PC, bst.ins-bst.b1

bst.b1
                MOVE    R2, 1           ; the depth
                MOVE    R3, FNV_BASIS   ; the hash
                MOVE[M] R1, @root
        ?!Z     ADD     @--SP, 2, PC
        ?!Z     MOVE    PC, bst.walkf
                MOVE    R1, R3
                MOVE    PC, @SP++

bst.dup         ADD     @1[R3], @1[R3], 1  ; the key is there: count it
                MOVE    PC, bst.next

; bst.walkf: R1 = a node that is not null, R2 = its depth, R3 = the hash,
; which it returns in R3. Uses R1 and R2. The call for a child is two
; conditional instructions, skipped for a null child, and the one for the
; right child is a tail call.
bst.walkf
                MOVE    @--SP, R1
                MOVE    @--SP, R2
                ADD     R2, R2, 1
                MOVE[M] R1, @2[R1]      ; left
        ?!Z     ADD     @--SP, 2, PC
        ?!Z     MOVE    PC, bst.walkf
                MOVE    R2, @SP++
                MOVE    R1, @SP++
                XOR     @MPU_A, R3, @R1  ; h ^ key
                MOVE    @MPU_B, FNV_PRIME
                MOVE    R3, @UMUL_LO
                MOVE    @MPU_A, R2      ; depth
                MOVE    @MPU_B, @1[R1]  ; count
                ADD     R3, R3, @UMUL_LO
                ADD     R2, R2, 1
                MOVE[M] R1, @3[R1]      ; right
        ?!Z     MOVE    PC, bst.walkf
                MOVE    PC, @SP++

; ---------------------------------------------------------------------------
; heapsort: the array is addressed as @arr[Rx] with the index in Rx. The
; larger child is chosen with conditional moves, and the signed comparisons
; use the N-after-V trick of ISA.md §9.2.

heapsort
                MOVE    R2, ARR_WORDS   ; n
                MOVE    R8, 511         ; i = n / 2 - 1
hs.build
                MOVE    R1, R8
                ADD     @--SP, 2, PC
                MOVE    PC, hs.sift
                DEC[M]  R8, R8
        ?!C     ADD     PC, PC, hs.build-hs.b1  ; until i was 0

hs.b1
                MOVE    R2, ARR_WORDS-1  ; end
hs.ext          MOVE    R3, @arr
                MOVE    @arr, @arr[R2]
                MOVE    @arr[R2], R3
                MOVE    R1, 0
                ADD     @--SP, 2, PC
                MOVE    PC, hs.sift     ; sift(0, end)
                DEC[M]  R2, R2
        ?!Z     ADD     PC, PC, hs.ext-hs.b2

hs.b2
                MOVE    @MPU_B, FNV_PRIME
                MOVE    R5, FNV_BASIS
                MOVE    R2, arr
                MOVE    R4, @arr        ; the previous element
                MOVE    R6, ARR_WORDS
hs.chk          MOVE    R3, @R2++
                SUB[M]  R0, R3, R4
        ?V      XOR     R14, R14, SIGN_N
        ?N      MOVE    PC, hs.bad      ; smaller than the one before
                MOVE    R4, R3
                XOR     @MPU_A, R5, R3
                MOVE    R5, @UMUL_LO
                DEC[M]  R6, R6
        ?!Z     ADD     PC, PC, hs.chk-hs.b3
hs.b3           MOVE    R1, R5
hs.ret          MOVE    PC, @SP++
hs.bad          MOVE    R1, 0
                MOVE    PC, @SP++

; hs.sift: R1 = i, R2 = n. Uses R1 and R3-R7, and keeps R2. The value
; a[i] is loaded once, in R6: after a swap it is the value at the new i.
; The loop is unrolled by two, with i in R1 and then in R5, so that the
; new i needs no move. l = 2i + 1 is one instruction, with 1[R1] = i + 1.
hs.sift         MOVE    R6, @arr[R1]    ; a[i]
hs.loop         ADD     R3, R1, 1[R1]   ; l
                SUB[M]  R0, R3, R2
        ?!C     MOVE    PC, hs.ret      ; l >= n
                MOVE    R4, @arr[R3]    ; a[m], with m = l
                MOVE    R5, R3
                ADD     R7, R3, 1
                SUB[M]  R0, R7, R2
        ?!C     MOVE    PC, hs.cmp      ; l + 1 >= n
                SUB[M]  R0, R4, @arr[R7]  ; a[l] - a[l + 1]
        ?V      XOR     R14, R14, SIGN_N
        ?N      MOVE    R5, R7          ; a[l + 1] is larger: m = l + 1
        ?N      MOVE    R4, @arr[R7]
hs.cmp          SUB[M]  R0, R6, R4      ; a[i] - a[m]
        ?V      XOR     R14, R14, SIGN_N
        ?!N     MOVE    PC, hs.ret      ; a[m] <= a[i]
                MOVE    @arr[R1], R4
                MOVE    @arr[R5], R6    ; now i = m, in R5
                ADD     R3, R5, 1[R5]   ; l
                SUB[M]  R0, R3, R2
        ?!C     MOVE    PC, hs.ret
                MOVE    R4, @arr[R3]
                MOVE    R1, R3
                ADD     R7, R3, 1
                SUB[M]  R0, R7, R2
        ?!C     MOVE    PC, hs.cmp2
                SUB[M]  R0, R4, @arr[R7]
        ?V      XOR     R14, R14, SIGN_N
        ?N      MOVE    R1, R7
        ?N      MOVE    R4, @arr[R7]
hs.cmp2         SUB[M]  R0, R6, R4
        ?V      XOR     R14, R14, SIGN_N
        ?!N     MOVE    PC, hs.ret
                MOVE    @arr[R5], R4
                MOVE    @arr[R1], R6    ; now i = m, in R1
                MOVE    PC, hs.loop

; ---------------------------------------------------------------------------
; vm: R2 is the program counter and R3 the stack pointer, which points at
; the top of the stack. Each handler ends with the two instructions that
; fetch the next opcode and jump through the table. An operation on the
; top two values is one instruction, since the sources are read, with
; their side effects, before the destination is written (ISA.md §5).

vm              MOVE    R2, vm.prog
                MOVE    R3, vm.stack+16
                MOVE    @vm.cells, 0    ; i
                MOVE    @vm.cells+1, 0  ; acc
                MOVE    @vm.cells+2, VM_LOOPS  ; n
                MOVE    R1, @R2++
                MOVE    PC, @vm.disp[R1]
vm.halt         MOVE    R1, @vm.cells+1
                MOVE    PC, @SP++
vm.push         MOVE    @--R3, @R2++
                MOVE    R1, @R2++
                MOVE    PC, @vm.disp[R1]
vm.load         MOVE    R4, @R2++
                MOVE    @--R3, @vm.cells[R4]
                MOVE    R1, @R2++
                MOVE    PC, @vm.disp[R1]
vm.store
                MOVE    R4, @R2++
                MOVE    @vm.cells[R4], @R3++
                MOVE    R1, @R2++
                MOVE    PC, @vm.disp[R1]
vm.add          ADD     @R3, @R3++, @R3
                MOVE    R1, @R2++
                MOVE    PC, @vm.disp[R1]
vm.mul          MOVE    @MPU_A, @R3++
                MOVE    @MPU_B, @R3
                MOVE    @R3, @UMUL_LO
                MOVE    R1, @R2++
                MOVE    PC, @vm.disp[R1]
vm.xor          XOR     @R3, @R3++, @R3
                MOVE    R1, @R2++
                MOVE    PC, @vm.disp[R1]
vm.dup          MOVE    @--R3, @R3
                MOVE    R1, @R2++
                MOVE    PC, @vm.disp[R1]
vm.jnz          MOVE    R4, @R2++
                MOVE[M] R0, @R3++
        ?!Z     MOVE    R2, vm.prog[R4]
                MOVE    R1, @R2++
                MOVE    PC, @vm.disp[R1]
vm.lt           MOVE    R4, @R3++       ; b
                SUB[M]  R0, @R3, R4     ; a - b
                MOVE    @R3, 0
        ?V      XOR     R14, R14, SIGN_N
        ?N      ONE     @R3
                MOVE    R1, @R2++
                MOVE    PC, @vm.disp[R1]

; The opcodes are those of bench.c: HALT, PUSH, LOAD, STORE, ADD, MUL,
; XOR, DUP, JNZ, LT, with the same program.
vm.disp         .DAT    vm.halt, vm.push, vm.load, vm.store, vm.add
                .DAT    vm.mul, vm.xor, vm.dup, vm.jnz, vm.lt
vm.prog         .DAT    2, 1, 1, 31, 5, 2, 0, 6, 3, 1  ; acc = (acc * 31) ^ i
                .DAT    2, 0, 1, 1, 4, 7, 3, 0  ; i = i + 1, and leave i
                .DAT    2, 2, 9, 8, 0   ; if i < n, go to 0
                .DAT    0

; ---------------------------------------------------------------------------
; strings: the strings are made from the bytes of the buffer, one character
; per word, with the math unit's remainder for the modulo. The insertion
; sort compares two strings a word at a time, the join copies with MOVE[M]
; and stops on the 0 it copied, and the length is the distance covered.

strings         MOVE    R12, buf        ; the 16 bytes of the string
                MOVE    R8, pool        ; where the next string goes
                MOVE    R9, strs
                MOVE    R10, STR_COUNT
str.make
                MOVE    @R9++, R8
                MOVE    R7, R12
                ADD     R12, R12, 4
                MOVE    R4, @R7++       ; bytes 0 to 3
                AND     R5, R4, 255
                MOVE    @MPU_A, R5
                MOVE    @MPU_B, STR_MAXLEN-3
                ADD     R6, @UDIV_R, 4  ; the length
                MOVE    @MPU_B, 26
                SHR     R4, R4, 8       ; byte 1 is next
                MOVE    R11, 3          ; bytes left in R4
str.ch          AND     R5, R4, 255
                MOVE    @MPU_A, R5
                ADD     @R8++, @UDIV_R, 97  ; 'a' + byte % 26
                DEC[M]  R6, R6
        ?Z      MOVE    PC, str.end
                SHR     R4, R4, 8
                DEC[M]  R11, R11
        ?!Z     ADD     PC, PC, str.ch-str.b1
str.b1          MOVE    R4, @R7++
                MOVE    R11, 4
                MOVE    PC, str.ch
str.end         MOVE    @R8++, 0
                DEC[M]  R10, R10
        ?!Z     ADD     PC, PC, str.make-str.b2

str.b2
                MOVE    R9, 1           ; j
str.outer
                MOVE    R10, @strs[R9]  ; the string to place
                MOVE    R11, R9         ; k
                MOVE    PC, str.inner
str.diff
        ?N      MOVE    PC, str.place   ; strs[k - 1] is smaller
                MOVE    @strs[R11], @strs[R12]
                MOVE    R11, R12
str.inner
                MOVE[M] R0, R11
        ?Z      MOVE    PC, str.place
                SUB     R12, R11, 1
                MOVE    R1, @strs[R12]  ; strs[k - 1]
                MOVE    R2, R10
str.cmp         SUB[M]  R4, @R1++, @R2++
        ?!Z     ADD     PC, PC, str.diff-str.eq  ; the strings differ: mostly taken
str.eq          MOVE[M] R0, @-1[R1]     ; the character, 0 at the end
        ?!Z     ADD     PC, PC, str.cmp-str.b3
str.b3          MOVE    PC, str.place   ; equal
str.place
                MOVE    @strs[R11], R10
                ADD     R9, R9, 1
                SUB[M]  R0, R9, STR_COUNT
        ?!Z     ADD     PC, PC, str.outer-str.b4

str.b4
                MOVE    R2, joined
                MOVE    R9, strs
                MOVE    R10, STR_COUNT
str.join
                MOVE    R1, @R9++
str.copy
                MOVE[M] @R2++, @R1++
        ?!Z     ADD     PC, PC, str.copy-str.b5
str.b5          SUB     R2, R2, 1       ; the next string goes over the 0
                DEC[M]  R10, R10
        ?!Z     ADD     PC, PC, str.join-str.b6
str.b6          SUB     R7, R2, joined  ; the total length

                MOVE    R1, joined
                MOVE    R6, 0           ; the matches of "ab"
str.scan
                MOVE[M] R3, @R1++
        ?Z      MOVE    PC, str.hash
                SUB[M]  R0, R3, 97
        ?!Z     ADD     PC, PC, str.scan-str.b7
str.b7          SUB[M]  R0, @R1, 98
        ?Z      ADD     R6, R6, 1
                MOVE    PC, str.scan

str.hash
                MOVE    @MPU_B, FNV_PRIME
                MOVE    R5, FNV_BASIS
                MOVE    R1, joined
                MOVE    R8, R7
str.fnv         XOR     @MPU_A, R5, @R1++
                MOVE    R5, @UMUL_LO
                DEC[M]  R8, R8
        ?!Z     ADD     PC, PC, str.fnv-str.b8
str.b8          MOVE    @MPU_A, R7
                MOVE    @MPU_B, 65599
                ADD     R1, R5, @UMUL_LO  ; h + total * 65599
                ADD     R1, R1, R6      ; + matches
                MOVE    PC, @SP++

; ---------------------------------------------------------------------------
; Data.

header          .ASCII_L 'phase      instructions       cycles  result'
name.rng64
                .ASCII_L 'rng64     '
name.crc32
                .ASCII_L 'crc32     '
name.bst
                .ASCII_L 'bst       '
name.heapsort
                .ASCII_L 'heapsort  '
name.vm         .ASCII_L 'vm        '
name.strings
                .ASCII_L 'strings   '
name.total
                .ASCII_L 'total     '
str.ok          .ASCII_L '  ok'
str.fail
                .ASCII_L '  FAIL'

failures
                .DAT    0
total.ins_lo
                .DAT    0
total.ins_hi
                .DAT    0
total.cyc_lo
                .DAT    0
total.cyc_hi
                .DAT    0
run.name
                .DAT    0
run.expect
                .DAT    0
run.ins_lo
                .DAT    0
run.ins_hi
                .DAT    0
run.cyc_lo
                .DAT    0
run.cyc_hi
                .DAT    0
digits          .BLK    20
digits.end
                .DAT    0

; Everything below is written before it is read.
buf             .RES    BUF_WORDS
arr             .RES    ARR_WORDS
table           .RES    256
root            .RES    1
nodes           .RES    4096            ; ARR_WORDS nodes of four words
pool            .RES    832             ; STR_COUNT strings of up to STR_MAXLEN + 1 words
strs            .RES    STR_COUNT
joined          .RES    833
vm.stack
                .RES    16
vm.cells
                .RES    4
