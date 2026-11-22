; TIME_SKIP (DEVICES.md §3): with --step-time, a write of N skips N wait
; steps after the step of the write, which count cycles, microseconds,
; and the clock, but no instructions. A write of 0 skips nothing. Run
; with
;   --step-time -d 0x200:6 -d 0x210:2
; The steps are:
;    0    [0x200] = CYCLE_LO = 0
;    1    TIME_SKIP <- 100
;    2-101 100 wait steps
;  102    [0x201] = CYCLE_LO = 102
;  103    [0x202] = INSTR_LO = 3: steps 0, 1, and 102
;  104    [0x210] = TIME_LO = 104, one microsecond per step
;  105    [0x211] = CLOCK_USEC = 105, the clock counts the skip too
;  106    TIME_SKIP <- 0, no skip
;  107    [0x203] = CYCLE_LO = 107
;  108    TIME_SKIP <- 30
;  109-138 30 wait steps
;  139    [0x204] = CYCLE_LO = 139
;  140    [0x205] = INSTR_LO = 10: steps 0-1, 102-108, and 139
;  141    HALT, at word 33
; 142 steps, PC = 0x22.
; Also run with --max-steps 4 and no --step-time (skip_off in the
; Makefile), where the write is ignored: [0x201] = CYCLE_LO = 2, and
; [0x202] = INSTR_LO = 3; with --step-time --max-steps 50 (skip_limit),
; where the step limit cuts the first skip short after 50 steps, PC at
; the word after the write; and with --step-time --no-cycle-counter
; (skip_mem), where TIME_SKIP stays a device: 142 steps, as above.
CYCLE_LO        .EQU    0xFFFFFF40
INSTR_LO        .EQU    0xFFFFFF42
TIME_LO         .EQU    0xFFFFFF44
CLOCK_USEC      .EQU    0xFFFFFF46
TIME_SKIP       .EQU    0xFFFFFF5F
                MOVE    @0x200, @CYCLE_LO
                MOVE    @TIME_SKIP, 100
                MOVE    @0x201, @CYCLE_LO
                MOVE    @0x202, @INSTR_LO
                MOVE    @0x210, @TIME_LO
                MOVE    @0x211, @CLOCK_USEC
                MOVE    @TIME_SKIP, 0
                MOVE    @0x203, @CYCLE_LO
                MOVE    @TIME_SKIP, 30
                MOVE    @0x204, @CYCLE_LO
                MOVE    @0x205, @INSTR_LO
                HALT
