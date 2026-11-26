; The sound's words and FIFO (DEVICES.md §12.1, §12.3), with --step-time:
; a sample is computed when the microseconds m reach ceil(n * 64000000 /
; 3579545) for the n-th sample, at m = 18, 36, 54, 72, ..., and each
; takes the oldest write from the FIFO. Run with
;   --step-time -d 0x200:9
; The steps, one microsecond each, and what they read:
;    0    [0x200] = OPM_STATUS = 0x21510000: no write waits
;    1-2  two writes
;    3    [0x201] = 0x21510280: two wait, and bit 7
;    4    TIME_SKIP <- 16, steps 5-20 wait; the sample at 18 takes one
;   21    [0x202] = 0x21510180
;   22    [0x203] = OPM_WRITE reads 0
;   23    [0x204] = 0xFFFFFF0F reads 0
;   24    a write of OPM_STATUS is ignored
;   25    [0x205] = 0x21510180, as the next sample is at 36
;   26    R7 <- 100
;   27-   100 times a write, DEC, and JMP, a write in 3 steps where a
;         sample takes one in 17.9: the FIFO fills, and each write to a
;         full FIFO waits for the next sample. 102 writes, 38 samples by
;         the end, so 64 wait: 0x21514080. The waits take 356
;         microseconds, which the cycle counter counts too.
;  [0x206] = 0x21514080
;  [0x207] = CYCLE_LO = 684: 312 instructions before it, the 16 steps
;         of the skip, and the 356 microseconds of the waits
;  [0x208] = INSTR_LO = 313
;  HALT, the 315th instruction, after 331 steps: the 315 and the 16 of
;  the skip. The waits of the writes are not steps of the run.
; Also run with --no-sound (sound_mem in the Makefile), where the words
; are memory: [0x200] = 0, [0x201] = 0, [0x202] = 0, [0x203] = 0x1802,
; the last write before it, [0x204] = 0, [0x205] = [0x206] = 0x1234,
; [0x207] = CYCLE_LO = 328, and [0x208] = 313.
OPM_WRITE       .EQU    0xFFFFFF08
OPM_STATUS      .EQU    0xFFFFFF09
CYCLE_LO        .EQU    0xFFFFFF40
INSTR_LO        .EQU    0xFFFFFF42
TIME_SKIP       .EQU    0xFFFFFF5F
                MOVE    @0x200, @OPM_STATUS
                MOVE    @OPM_WRITE, 0x0F80
                MOVE    @OPM_WRITE, 0x1802
                MOVE    @0x201, @OPM_STATUS
                MOVE    @TIME_SKIP, 16
                MOVE    @0x202, @OPM_STATUS
                MOVE    @0x203, @OPM_WRITE
                MOVE    @0x204, @0xFFFFFF0F
                MOVE    @OPM_STATUS, 0x1234
                MOVE    @0x205, @OPM_STATUS
                MOVE    R7, 100
:               MOVE    @OPM_WRITE, 0x2000
                DEC[M]  R7, R7
        ?!Z     JMP     :-
                MOVE    @0x206, @OPM_STATUS
                MOVE    @0x207, @CYCLE_LO
                MOVE    @0x208, @INSTR_LO
                HALT
