; The sample player's words, FIFO, and rate (DEVICES.md §12.7), with
; --step-time: at the rate r, set at the microsecond s, a sample is played
; each time the sum of r for each microsecond since s, plus what the sum
; held at s, reaches a multiple of 1000000. Run with
;   --step-time -d 0x200:13
; The steps, one microsecond each, and what they read:
;     0   [0x200] = PCM_STATUS = 0x10000000: the depth, 4096, and empty
;     1-2 two samples
;     3   [0x201] = 0x10000002
;     4   [0x202] = PCM_DATA reads 0
;     5   [0x203] = 0xFFFFFF0D reads 0
;     6   PCM_RATE <- 1, which sets 1000: samples at 1006, 2006, 3006, ...
;     7   [0x204] = PCM_RATE = 1000
;     8   TIME_SKIP <- 1500, steps 9-1508 wait; 1006 plays the first
;  1509   [0x205] = 0x10000001
;  1510   TIME_SKIP <- 1000, to 2510; 2006 plays the second
;  2511   [0x206] = 0x10000000: empty, and no underrun yet
;  2512   TIME_SKIP <- 1000, to 3512; 3006 finds the FIFO empty
;  3513   [0x207] = 0x10008000: the underrun flag
;  3514   a write of PCM_STATUS clears it
;  3515   [0x208] = 0x10000000
;  3516   PCM_RATE <- 0: the sum keeps 3510 * 1000 - 3000000 = 510000
;  3517   R7 <- 4097
;  3518-15808  4097 times a write, DEC, and JMP: 4096 samples fill the
;         FIFO, and the last write, of a full FIFO while stopped, is
;         dropped without a wait
; 15809   [0x209] = 0x10001000
; 15810   PCM_RATE <- 48000: the sum is 510000 + 48000 * (m - 15810)
; 15811   a write to the full FIFO waits for the sample at 15821, when the
;         sum reaches 1038000, 10 microseconds
; 15822   [0x20A] = 0x10001000: full again
; 15823   [0x20B] = CYCLE_LO = 15823: 12312 instructions before it, the
;         3500 steps of the skips, and the 10 microseconds of the wait
; 15824   [0x20C] = INSTR_LO = 12314
; HALT, the 12316th instruction, after 15816 steps: the 12316 and the
; 3500 of the skips. The wait of the write is not a step of the run.
; Also run with --no-sound (pcm_mem in the Makefile), where the words are
; memory: [0x200] = [0x201] = 0, [0x202] = 0xFFFF8000, the last sample
; written, [0x203] = 0, [0x204] = 1, [0x205]-[0x20A] = 0, [0x20B] =
; CYCLE_LO = 15813, without the wait, and [0x20C] = 12314.
PCM_DATA        .EQU    0xFFFFFF0A
PCM_RATE        .EQU    0xFFFFFF0B
PCM_STATUS      .EQU    0xFFFFFF0C
CYCLE_LO        .EQU    0xFFFFFF40
INSTR_LO        .EQU    0xFFFFFF42
TIME_SKIP       .EQU    0xFFFFFF5F
                MOVE    @0x200, @PCM_STATUS
                MOVE    @PCM_DATA, 0x00010002
                MOVE    @PCM_DATA, 0xFFFF8000
                MOVE    @0x201, @PCM_STATUS
                MOVE    @0x202, @PCM_DATA
                MOVE    @0x203, @0xFFFFFF0D
                MOVE    @PCM_RATE, 1
                MOVE    @0x204, @PCM_RATE
                MOVE    @TIME_SKIP, 1500
                MOVE    @0x205, @PCM_STATUS
                MOVE    @TIME_SKIP, 1000
                MOVE    @0x206, @PCM_STATUS
                MOVE    @TIME_SKIP, 1000
                MOVE    @0x207, @PCM_STATUS
                MOVE    @PCM_STATUS, 0
                MOVE    @0x208, @PCM_STATUS
                MOVE    @PCM_RATE, 0
                MOVE    R7, 4097
:               MOVE    @PCM_DATA, R7
                DEC[M]  R7, R7
        ?!Z     JMP     :-
                MOVE    @0x209, @PCM_STATUS
                MOVE    @PCM_RATE, 48000
                MOVE    @PCM_DATA, 0x12345678
                MOVE    @0x20A, @PCM_STATUS
                MOVE    @0x20B, @CYCLE_LO
                MOVE    @0x20C, @INSTR_LO
                HALT
