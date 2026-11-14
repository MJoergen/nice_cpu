; fpudec.nasm of the emulator's probes, after an FMOD of 1e308 by 3,
; for the sweeps of test/irq_sweep.py, with an NMI (vector 8) or an IRQ
; (vector 9) before its steps. FMOD takes some 1000 cycles, one for each
; bit of the difference of the exponents, and DIGITS 15 some 2000, so
; most requests come while the core waits for the FPU, which it must
; finish before it takes them (DEVICES.md §11.5). PRINT writes the
; remainder first, then the numbers of fpudec.nasm. VBASE stays 0.
; Last comes an FMOD of the largest value by 2^-1022, some 2100 cycles,
; and a read of STATUS that waits for it, so that a request delayed by
; up to 1500 cycles (FPU_SWEEP_DELAYS in the Makefile) is taken before
; the HALT.
CONSOLE         .EQU    0xFFFFFF00
MPU_A           .EQU    0xFFFFFF20
MPU_B           .EQU    0xFFFFFF21
MPU_UDIV_Q      .EQU    0xFFFFFF28
MPU_UDIV_R      .EQU    0xFFFFFF29
FPU_X_LO        .EQU    0xFFFFFF88
FPU_X_HI        .EQU    0xFFFFFF89
FPU_X_W         .EQU    0xFFFFFF8B
FPU_CMD         .EQU    0xFFFFFF8C
FPU_STATUS      .EQU    0xFFFFFF8D
                JMP     start
                .ORG    8
                .DAT    nmi, irq
start           MOVE    R13, 0x1000
                MOVE    R14, 0x40000000  ; E = 1
                MOVE    @FPU_X_LO, 0x85EBC8A0  ; 1e308
                MOVE    @FPU_X_HI, 0x7FE1CCF3
                MOVE    @FPU_X_LO, 0    ; 3
                MOVE    @FPU_X_HI, 0x40080000
                MOVE    @FPU_CMD, 0x1D  ; FMOD
                CALL    PRINT
                MOVE    R10, VALUES
                MOVE    R11, 6
:               MOVE    @FPU_X_LO, @R10++
                MOVE    @FPU_X_HI, @R10++
                CALL    PRINT
                DEC[M]  R11, R11
        ?!Z     JMP     :-
                MOVE    @FPU_X_LO, 0x60000000
                MOVE    @FPU_X_HI, 0x60221407
                MOVE    @FPU_CMD, 0x3B  ; FROMBCD
                MOVE    @FPU_X_W, 8
                MOVE    @FPU_CMD, 0x39  ; SCALE10
                CALL    PRINT
                MOVE    @FPU_X_LO, 0xFFFFFFFF  ; MAX
                MOVE    @FPU_X_HI, 0x7FEFFFFF
                MOVE    @FPU_X_LO, 0    ; 2^-1022
                MOVE    @FPU_X_HI, 0x00100000
                MOVE    @FPU_CMD, 0x1D  ; FMOD
                MOVE    R6, @FPU_STATUS  ; waits for FMOD
                HALT

PRINT           AND[M]  R0, @FPU_STATUS, 0x10000  ; X is negative
        ?!Z     MOVE    @CONSOLE, 0x2D  ; '-'
                MOVE    @FPU_CMD, 0x0F3A  ; DIGITS 15
                MOVE    R2, @FPU_X_W    ; e
                MOVE    @FPU_CMD, 0x03  ; DROP
                MOVE    R3, @FPU_X_HI   ; the digits in R3:R4
                MOVE    R4, @FPU_X_LO
                MOVE    @FPU_CMD, 0x03  ; DROP
                SHR     R1, R3, 28
                ADD     @CONSOLE, R1, 0x30
                MOVE    @CONSOLE, 0x2E  ; '.'
                MOVE    R5, 14
:               SHL     R3, R3, 4       ; R3:R4 left by a digit
                SHR     R1, R4, 28
                OR      R3, R3, R1
                SHL     R4, R4, 4
                SHR     R1, R3, 28
                ADD     @CONSOLE, R1, 0x30
                DEC[M]  R5, R5
        ?!Z     JMP     :-
                MOVE    @CONSOLE, 0x45  ; 'E'
                MOVE    R1, 0x2B        ; '+'
                MOVE[M] R0, R2
        ?N      MOVE    R1, 0x2D        ; '-'
        ?N      SUB     R2, R0, R2
                MOVE    @CONSOLE, R1
                MOVE    @MPU_A, R2
                MOVE    @MPU_B, 100
                ADD     @CONSOLE, @MPU_UDIV_Q, 0x30
                MOVE    @MPU_A, @MPU_UDIV_R
                MOVE    @MPU_B, 10
                ADD     @CONSOLE, @MPU_UDIV_Q, 0x30
                ADD     @CONSOLE, @MPU_UDIV_R, 0x30
                MOVE    @CONSOLE, 0x0A
                RET

; The routines count their requests and change the flags, which RTI
; restores. They do not use the FPU (DEVICES.md §11.5).
nmi             ADD[M]  @nmis, @nmis, 1
                RTI
irq             SUB[M]  @irqs, @irqs, 1
                RTI
nmis            .DAT    0
irqs            .DAT    0

; Each value as its low word, then its high word.
VALUES          .DAT    0x54442D18, 0x400921FB  ; π
                .DAT    0x9999999A, 0xBFB99999  ; -0.1
                .DAT    0x00000001, 0x00000000  ; 2^-1074
                .DAT    0xFFFFFFFF, 0x7FEFFFFF  ; MAX
                .DAT    0x00000000, 0x80000000  ; -0
                .DAT    0x00000000, 0x00100000  ; 2^-1022
