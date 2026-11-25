; The performance counters (DEVICES.md §3), run with --step-time, so that
; the microsecond counter in the dump counts steps. The instruction
; counter counts every instruction, a skipped one included. A read of it
; returns the number of instructions before the reading one. SPARE, the
; first word after the counters, counts nothing and reads 0. The cycle
; counter counts the steps in the emulator and the clock cycles on the
; FPGA core, so this program puts only its flags in registers: the trace
; is then the same on both.
;
;   step instr
;    0    0    MOVE R1, @INSTR_HI    no snapshot yet: R1 = 0
;    1    1    MOVE R2, @INSTR_LO    R2 = 1
;    2    2    MOVE R3, @INSTR_HI    the snapshot's high word: R3 = 0
;    3    3    MOVE R7, @INSTR_LO    R7 = 3
;    4    4    ?Z MOVE R4, 1         skipped (Z = 0 after reset)
;    5    5    MOVE @INSTR_LO, 0x55  ignored
;    6    6    MOVE R4, @INSTR_LO    R4 = 6
;    7    7    MOVE[M] R0, @CYCLE_LO not 0, not negative: the flags stay clear
;    8    8    MOVE[M] R0, @CYCLE_HI 0: Z = 1, R14 = 0x09000000
;    9    9    MOVE[M] R0, @CYCLE_LO not 0: Z = 0, R14 = 0x01000000
;   10   10    MOVE R5, @SPARE       R5 = 0
;   11   11    MOVE R6, @INSTR_LO    R6 = 11 = 0xB
;   12   12    MOVE R8, @INSTR_HI    R8 = 0
;   13   13    HALT
;
; 14 steps and 14 instructions. PC = 0x1C after the HALT at 0x1B. The dump
; reads the counters without taking snapshots: the steps, 14 = 0xE, the
; cycle snapshot's high word 0, the instructions, 14 = 0xE, the
; instruction snapshot's high word 0, and the microsecond counter, 14 =
; 0xE, and its snapshot's high word 0 (test/time.nasm). The writes left
; no trace in memory.
CYCLE_LO        .EQU    0xFFFFFF40
CYCLE_HI        .EQU    0xFFFFFF41
INSTR_LO        .EQU    0xFFFFFF42
INSTR_HI        .EQU    0xFFFFFF43
SPARE           .EQU    0xFFFFFF52
                MOVE    R1, @INSTR_HI   ; words 0,1
                MOVE    R2, @INSTR_LO   ; words 2,3
                MOVE    R3, @INSTR_HI   ; words 4,5
                MOVE    R7, @INSTR_LO   ; words 6,7
        ?Z      MOVE    R4, 1           ; words 8,9
                MOVE    @INSTR_LO, 0x55  ; words 10-12
                MOVE    R4, @INSTR_LO   ; words 13,14
                TST     @CYCLE_LO       ; words 15,16
                TST     @CYCLE_HI       ; words 17,18
                TST     @CYCLE_LO       ; words 19,20
                MOVE    R5, @SPARE      ; words 21,22
                MOVE    R6, @INSTR_LO   ; words 23,24
                MOVE    R8, @INSTR_HI   ; words 25,26
                HALT                    ; word 27
