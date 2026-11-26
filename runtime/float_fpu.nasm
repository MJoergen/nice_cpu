; The float library of the NICE runtime library (README.md, Floating
; point), with the floating-point unit of DEVICES §11. It goes after
; lib.nasm and the muldiv file. Each routine pushes its operands, writes a
; command, and reads the result, so it leaves the FPU's stack as it found
; it. A routine of a float operation uses at most two of its values
; (DEVICES §11.5). An entry sets the command in R5 and jumps
; to a shared part.
;
; The FPU computes in binary64. An f32 operand is pushed through X_S,
; which is exact, and the result read through X_S, which rounds it to
; binary32. For +, -, *, /, and the square root, the command's S bit
; rounds the exact result once, to binary32, on the stack: the result is
; then wasm's. Every NaN that the FPU computes is the canonical NaN,
; 0x7FF80000_00000000, and 0x7FC00000 through X_S.

__fpu.x_lo      .EQU    0xFFFFFF88
__fpu.x_hi      .EQU    0xFFFFFF89
__fpu.x_s       .EQU    0xFFFFFF8A
__fpu.x_w       .EQU    0xFFFFFF8B
__fpu.cmd       .EQU    0xFFFFFF8C
__fpu.rel       .EQU    0xFFFFFF8E

; f64 arithmetic: R1:R2 = R1:R2 op R3:R4.
___adddf3
                MOVE    R5, 0x10        ; ADD
                JMP     __fpu.op2_64
___subdf3
                MOVE    R5, 0x11        ; SUB
                JMP     __fpu.op2_64
___muldf3
                MOVE    R5, 0x12        ; MUL
                JMP     __fpu.op2_64
___divdf3
                MOVE    R5, 0x13        ; DIV
                JMP     __fpu.op2_64
; As wasm's min and max: a NaN gives a NaN, and -0 is below +0.
___mindf
                MOVE    R5, 0x17        ; MIN
                JMP     __fpu.op2_64
___maxdf
                MOVE    R5, 0x18        ; MAX
__fpu.op2_64
                MOVE    @__fpu.x_lo, R1
                MOVE    @__fpu.x_hi, R2
                MOVE    R1, R3
                MOVE    R2, R4
; f64 of one operand: R1:R2 = op R1:R2.
__fpu.op1_64
                MOVE    @__fpu.x_lo, R1
                MOVE    @__fpu.x_hi, R2
__fpu.cmd64
                MOVE    @__fpu.cmd, R5
__fpu.pop64
                MOVE    R1, @__fpu.x_lo
                MOVE    R2, @__fpu.x_hi
__fpu.drop
                MOVE    @__fpu.cmd, 0x03  ; DROP
                RET

___sqrtdf
                MOVE    R5, 0x14        ; SQRT
                JMP     __fpu.op1_64
___floordf
                MOVE    R5, 0x20        ; FLOOR
                JMP     __fpu.op1_64
___ceildf
                MOVE    R5, 0x21        ; CEIL
                JMP     __fpu.op1_64
___truncdf
                MOVE    R5, 0x22        ; TRUNC
                JMP     __fpu.op1_64
___nearestdf
                MOVE    R5, 0x23        ; NEAREST, ties to even
                JMP     __fpu.op1_64

; f32 arithmetic: R1 = R1 op R2.
___addsf3
                MOVE    R5, 0x10010     ; ADD, S
                JMP     __fpu.op2_32
___subsf3
                MOVE    R5, 0x10011     ; SUB, S
                JMP     __fpu.op2_32
___mulsf3
                MOVE    R5, 0x10012     ; MUL, S
                JMP     __fpu.op2_32
___divsf3
                MOVE    R5, 0x10013     ; DIV, S
                JMP     __fpu.op2_32
___minsf
                MOVE    R5, 0x17        ; MIN, of binary32 values exact
                JMP     __fpu.op2_32
___maxsf
                MOVE    R5, 0x18        ; MAX
__fpu.op2_32
                MOVE    @__fpu.x_s, R1
                MOVE    R1, R2
; f32 of one operand: R1 = op R1.
__fpu.op1_32
                MOVE    @__fpu.x_s, R1
__fpu.cmd32
                MOVE    @__fpu.cmd, R5
__fpu.pop32
                MOVE    R1, @__fpu.x_s
                JMP     __fpu.drop

___sqrtsf
                MOVE    R5, 0x10014     ; SQRT, S
                JMP     __fpu.op1_32
; The integral value of a binary32 value is one too, so these are exact.
___floorsf
                MOVE    R5, 0x20        ; FLOOR
                JMP     __fpu.op1_32
___ceilsf
                MOVE    R5, 0x21        ; CEIL
                JMP     __fpu.op1_32
___truncsf
                MOVE    R5, 0x22        ; TRUNC
                JMP     __fpu.op1_32
___nearestsf
                MOVE    R5, 0x23        ; NEAREST
                JMP     __fpu.op1_32

; Comparisons, as libgcc's: R1 = -1, 0, or 1 as a is below, equal to, or
; above b, and for a NaN the value that makes the test fail: 1, but for
; gt and ge, -1. ne gives 1 too, which makes its test, != 0, succeed.
; REL compares Y = a with X = b, and reads 2 for a NaN.
___gtdf2
___gedf2
                MOVE    R5, 0xFFFFFFFF
                JMP     __fpu.cmp64
___eqdf2
___nedf2
___ltdf2
___ledf2
                MOVE    R5, 1
__fpu.cmp64
                MOVE    @__fpu.x_lo, R1
                MOVE    @__fpu.x_hi, R2
                MOVE    @__fpu.x_lo, R3
                MOVE    @__fpu.x_hi, R4
__fpu.cmp
                MOVE    R1, @__fpu.rel
                MOVE    @__fpu.cmd, 0x0203  ; DROP 2
                SUB[M]  R0, R1, 2
        ?Z      MOVE    R1, R5          ; a NaN
                RET
___gtsf2
___gesf2
                MOVE    R5, 0xFFFFFFFF
                JMP     __fpu.cmp32
___eqsf2
___nesf2
___ltsf2
___lesf2
                MOVE    R5, 1
__fpu.cmp32
                MOVE    @__fpu.x_s, R1
                MOVE    @__fpu.x_s, R2
                JMP     __fpu.cmp

; Integers to floats. A signed word is pushed through X_W, and an unsigned
; one through X_LO and UTOF, both exact.
___floatsidf
                MOVE    @__fpu.x_w, R1
                JMP     __fpu.pop64
___floatunsidf
                MOVE    @__fpu.x_lo, R1
                MOVE    R5, 0x29        ; UTOF
                JMP     __fpu.cmd64
___floatdidf
                MOVE    R5, 0x28        ; ITOF
                JMP     __fpu.op1_64
___floatundidf
                MOVE    R5, 0x29        ; UTOF
                JMP     __fpu.op1_64
___floatsisf
                MOVE    @__fpu.x_w, R1
                JMP     __fpu.pop32
___floatunsisf
                MOVE    @__fpu.x_lo, R1
                MOVE    R5, 0x29        ; UTOF
                JMP     __fpu.cmd32
; A long long to f32 through binary64 would round twice. Below 2^53 the
; binary64 value is exact. From 2^53 on, the magnitude is shifted right by
; 11, with the bits shifted out ORed into bit 0, which keeps the rounding
; to binary32 that of the integer. SCALE2 by 11 restores the magnitude,
; exactly, and the read of X_S rounds once. A negative integer is
; converted as its magnitude, and NEG at the end gives the sign, as the
; rounding to nearest is symmetric.
___floatdisf
                MOVE    R4, 0           ; NOP at the end
                MOVE[M] R0, R2
        ?!N     JMP     __fpu.utof32
                MOVE    R4, 0x15        ; NEG at the end
                SUB     R2, R0, R2      ; R1:R2 = -R1:R2
                SUB[M]  R1, R0, R1
        ?!Z     SUB     R2, R2, 1
                JMP     __fpu.utof32
___floatundisf
                MOVE    R4, 0           ; NOP at the end
__fpu.utof32
                MOVE    R5, 0           ; the scale
                SHR[M]  R0, R2, 21      ; below 2^53
        ?Z      JMP     :+
                MOVE    R5, 11
                SHL     R6, R2, 21
                SHR     R2, R2, 11
                AND[M]  R0, R1, 0x7FF   ; the bits shifted out
                SHR     R1, R1, 11
                OR      R1, R1, R6
        ?!Z     OR      R1, R1, 1       ; sticky
:               MOVE    @__fpu.x_lo, R1
                MOVE    @__fpu.x_hi, R2
                MOVE    @__fpu.cmd, 0x29  ; UTOF
                MOVE    @__fpu.x_w, R5
                MOVE    @__fpu.cmd, 0x38  ; SCALE2
                MOVE    @__fpu.cmd, R4
                JMP     __fpu.pop32

; Floats to integers, toward 0. Out of range they saturate, and a NaN
; gives 0, as wasm's trunc_sat does. X_W reads a signed word so, and FTOI
; and FTOU give the 64-bit integers so. They set the invalid flag, which
; no routine reads.
___fixdfsi
                MOVE    @__fpu.x_lo, R1
                MOVE    @__fpu.x_hi, R2
__fpu.popw
                MOVE    R1, @__fpu.x_w
                JMP     __fpu.drop
___fixsfsi
                MOVE    @__fpu.x_s, R1
                JMP     __fpu.popw
___fixdfdi
                MOVE    R5, 0x2A        ; FTOI
                JMP     __fpu.op1_64
___fixunsdfdi
                MOVE    R5, 0x2B        ; FTOU
                JMP     __fpu.op1_64
___fixsfdi
                MOVE    @__fpu.x_s, R1
                MOVE    R5, 0x2A        ; FTOI
                JMP     __fpu.cmd64
___fixunssfdi
                MOVE    @__fpu.x_s, R1
                MOVE    R5, 0x2B        ; FTOU
                JMP     __fpu.cmd64
; An unsigned word: FTOU, and 0xFFFFFFFF if the high word is not 0.
___fixunssfsi
                MOVE    @__fpu.x_s, R1
                JMP     __fpu.ftou32
___fixunsdfsi
                MOVE    @__fpu.x_lo, R1
                MOVE    @__fpu.x_hi, R2
__fpu.ftou32
                MOVE    @__fpu.cmd, 0x2B  ; FTOU
                MOVE    R1, @__fpu.x_lo
                MOVE[M] R0, @__fpu.x_hi
        ?!Z     MOVE    R1, 0xFFFFFFFF
                JMP     __fpu.drop

; f32 to f64, exact, and f64 to f32, rounded to nearest.
___extendsfdf2
                MOVE    @__fpu.x_s, R1
                JMP     __fpu.pop64
___truncdfsf2
                MOVE    @__fpu.x_lo, R1
                MOVE    @__fpu.x_hi, R2
                JMP     __fpu.pop32

; The functions of the C library's math.h (README.md, Math functions), on
; the FPU's functions of DEVICES §11.3. math.h declares each as an import
; from env, at the label _name (WASM.md). A function pushes its operands,
; and leaves the stack as it found it, but needs k values above them
; (DEVICES §11.5): POW uses 15 values, so a caller keeps at most one
; value on the stack across these. The float versions compute in
; binary64, and the read of X_S rounds the result to binary32 once.
_sin
                MOVE    R5, 0x40        ; SIN
                JMP     __fpu.op1_64
_cos
                MOVE    R5, 0x41        ; COS
                JMP     __fpu.op1_64
_tan
                MOVE    R5, 0x42        ; TAN
                JMP     __fpu.op1_64
_asin
                MOVE    R5, 0x43        ; ASIN
                JMP     __fpu.op1_64
_acos
                MOVE    R5, 0x44        ; ACOS
                JMP     __fpu.op1_64
_atan
                MOVE    R5, 0x45        ; ATAN
                JMP     __fpu.op1_64
_log
                MOVE    R5, 0x48        ; LN
                JMP     __fpu.op1_64
_log2
                MOVE    R5, 0x49        ; LOG2
                JMP     __fpu.op1_64
_log10
                MOVE    R5, 0x4A        ; LOG10
                JMP     __fpu.op1_64
_exp
                MOVE    R5, 0x4C        ; EXP
                JMP     __fpu.op1_64
_exp2
                MOVE    R5, 0x4D        ; POW2
                JMP     __fpu.op1_64
_round
                MOVE    R5, 0x24        ; ROUND
                JMP     __fpu.op1_64
; atan2(y, x), pow(x, y), fmod(x, y), and hypot(x, y): the first operand
; is Y, and the second X.
_atan2
                MOVE    R5, 0x46        ; ATAN2
                JMP     __fpu.op2_64
_fmod
                MOVE    R5, 0x1D        ; FMOD
                JMP     __fpu.op2_64
; C gives 1 for pow(x, +-0) and pow(1, y), with a NaN as the other
; operand too, where POW gives a NaN.
_pow
                SHL     R5, R4, 1       ; y without its sign
                OR[M]   R0, R5, R3
        ?Z      JMP     __fpu.one64
                SUB[M]  R0, R2, 0x3FF00000
        ?Z      MOVE[M] R0, R1
        ?Z      JMP     __fpu.one64
                MOVE    R5, 0x4E        ; POW
                JMP     __fpu.op2_64
__fpu.one64
                MOVE    R1, 0
                MOVE    R2, 0x3FF00000
                RET
; C gives +inf for hypot of an infinity, with a NaN as the other operand
; too, where HYPOT gives a NaN.
_hypot
                SHL     R5, R2, 1       ; x without its sign
                SUB[M]  R0, R5, 0xFFE00000
        ?Z      MOVE[M] R0, R1
        ?Z      JMP     __fpu.inf64
                SHL     R5, R4, 1       ; y without its sign
                SUB[M]  R0, R5, 0xFFE00000
        ?Z      MOVE[M] R0, R3
        ?Z      JMP     __fpu.inf64
                MOVE    R5, 0x4F        ; HYPOT
                JMP     __fpu.op2_64
__fpu.inf64
                MOVE    R1, 0
                MOVE    R2, 0x7FF00000
                RET
; ldexp(x, n) and scalbn(x, n): x in R1:R2, and n in R3.
_ldexp
_scalbn
                MOVE    @__fpu.x_lo, R1
                MOVE    @__fpu.x_hi, R2
                MOVE    @__fpu.x_w, R3
                MOVE    R5, 0x38        ; SCALE2
                JMP     __fpu.cmd64

; The float versions.
_sinf
                MOVE    R5, 0x40        ; SIN
                JMP     __fpu.op1_32
_cosf
                MOVE    R5, 0x41        ; COS
                JMP     __fpu.op1_32
_tanf
                MOVE    R5, 0x42        ; TAN
                JMP     __fpu.op1_32
_asinf
                MOVE    R5, 0x43        ; ASIN
                JMP     __fpu.op1_32
_acosf
                MOVE    R5, 0x44        ; ACOS
                JMP     __fpu.op1_32
_atanf
                MOVE    R5, 0x45        ; ATAN
                JMP     __fpu.op1_32
_logf
                MOVE    R5, 0x48        ; LN
                JMP     __fpu.op1_32
_log2f
                MOVE    R5, 0x49        ; LOG2
                JMP     __fpu.op1_32
_log10f
                MOVE    R5, 0x4A        ; LOG10
                JMP     __fpu.op1_32
_expf
                MOVE    R5, 0x4C        ; EXP
                JMP     __fpu.op1_32
_exp2f
                MOVE    R5, 0x4D        ; POW2
                JMP     __fpu.op1_32
_roundf
                MOVE    R5, 0x24        ; ROUND
                JMP     __fpu.op1_32
_atan2f
                MOVE    R5, 0x46        ; ATAN2
                JMP     __fpu.op2_32
_fmodf
                MOVE    R5, 0x1D        ; FMOD
                JMP     __fpu.op2_32
_powf
                SHL[M]  R0, R2, 1       ; y without its sign
        ?Z      JMP     __fpu.one32
                SUB[M]  R0, R1, 0x3F800000
        ?Z      JMP     __fpu.one32
                MOVE    R5, 0x4E        ; POW
                JMP     __fpu.op2_32
__fpu.one32
                MOVE    R1, 0x3F800000
                RET
_hypotf
                SHL     R5, R1, 1
                SUB[M]  R0, R5, 0xFF000000
        ?Z      JMP     __fpu.inf32
                SHL     R5, R2, 1
                SUB[M]  R0, R5, 0xFF000000
        ?Z      JMP     __fpu.inf32
                MOVE    R5, 0x4F        ; HYPOT
                JMP     __fpu.op2_32
__fpu.inf32
                MOVE    R1, 0x7F800000
                RET
_ldexpf
_scalbnf
                MOVE    @__fpu.x_s, R1
                MOVE    @__fpu.x_w, R2
                MOVE    R5, 0x38        ; SCALE2
                JMP     __fpu.cmd32
