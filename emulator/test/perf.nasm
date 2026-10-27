; The performance counters (SYSTEM.md §3), run with --nmi 3:0x41. The
; instruction counter counts every instruction, a skipped one and INT
; included, but not the NMI entry. A read of it returns the number of
; instructions before the reading one. The cycle counter counts the steps in
; the emulator and the clock cycles on the FPGA core, so this program puts
; only its flags in registers: the trace is then the same on both.
;
;   step instr
;    0    0    MOVE R1, @INSTR_HI    no snapshot yet: R1 = 0
;    1    1    MOVE R2, @INSTR_LO    R2 = 1
;    2    2    MOVE R3, @INSTR_HI    the snapshot's high word: R3 = 0
;    3         NMI, through 0x41
;    4    3    MOVE R7, @INSTR_LO    R7 = 3
;    5    4    RTI
;    6    5    ?Z MOVE R4, 1         skipped (Z = 0 after reset)
;    7    6    MOVE @INSTR_LO, 0x55  ignored
;    8    7    MOVE R4, @INSTR_LO    R4 = 7
;    9    8    MOVE[M] R0, @CYCLE_LO not 0, not negative: the flags stay clear
;   10    9    MOVE[M] R0, @CYCLE_HI 0: Z = 1, R14 = 0x09000000
;   11   10    MOVE[M] R0, @CYCLE_LO not 0: Z = 0, R14 = 0x01000000
;   12   11    INT 0x40, through 0x40
;   13   12    MOVE R5, @INSTR_LO    R5 = 12 = 0xC
;   14   13    RTI
;   15   14    MOVE R6, @INSTR_LO    R6 = 14 = 0xE
;   16   15    MOVE R8, @INSTR_HI    R8 = 0
;   17   16    HALT
;
; 18 steps and 17 instructions. PC = 0x19 after the HALT at 0x18. The dump
; reads the counters without taking snapshots: the steps, 18 = 0x12, the
; cycle snapshot's high word 0, the instructions, 17 = 0x11, the
; instruction snapshot's high word 0, and the microsecond counter, 18 =
; 0x12, and its snapshot's high word 0 (test/time.nasm). The writes left
; no trace in memory.
CYCLE_LO        .EQU    0xFFFFFF40
CYCLE_HI        .EQU    0xFFFFFF41
INSTR_LO        .EQU    0xFFFFFF42
INSTR_HI        .EQU    0xFFFFFF43
                MOVE    R1, @INSTR_HI   ; words 0,1
                MOVE    R2, @INSTR_LO   ; words 2,3
                MOVE    R3, @INSTR_HI   ; words 4,5
        ?Z      MOVE    R4, 1           ; words 6,7
                MOVE    @INSTR_LO, 0x55  ; words 8-10
                MOVE    R4, @INSTR_LO   ; words 11,12
                MOVE[M] R0, @CYCLE_LO   ; words 13,14
                MOVE[M] R0, @CYCLE_HI   ; words 15,16
                MOVE[M] R0, @CYCLE_LO   ; words 17,18
                INT     0x40            ; word 19
                MOVE    R6, @INSTR_LO   ; words 20,21
                MOVE    R8, @INSTR_HI   ; words 22,23
                HALT                    ; word 24
on_nmi          MOVE    R7, @INSTR_LO   ; words 25,26
                RTI                     ; word 27
on_int          MOVE    R5, @INSTR_LO   ; words 28,29
                RTI                     ; word 30
                .ORG    0x40
                .DAT    on_int
                .DAT    on_nmi
