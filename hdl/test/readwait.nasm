; The cycles in which PREPARE holds a data read back only for rule 1 or
; rule 2 of MICROARCH.md §5.3, which tb_core prints when the pipelined
; core halts (src/pipe_prepare.vhd). This program makes one of each that
; goes on, one case that waits for neither, and one read on the wrong
; path, which waits 2 cycles and is dropped. So the line must give 1, 1;
; and 0, 2. Only the reads of the four cases read memory.
PC      .EQU    R15
        MOVE    R4, data
        MOVE    R1, 1
; 1. A conditional read after a write of SR: its condition is known only
; once the SUB has left WRITE, a cycle later.
        SUB[M]  R0, R1, 1       ; Z = 1
        ?Z MOVE R3, @R4
; 2. A read after a skipped jump: the read goes in the cycle the jump
; retires, so it does not wait.
        ?!Z MOVE PC, data
        MOVE    R3, @R4
; 3. A read after a shift by the register that the instruction before
; writes, which takes WRITE a second cycle (MICROARCH.md §7.3): the
; read waits for that cycle.
        MOVE    R6, 3
        SHL     R5, R5, R6
        MOVE    R3, @R4
; 4. A read after a jump to an address read from memory. PREPARE loads
; the jump's read in cycle t and passes the jump on to WRITE in t + 1,
; while the read is on the bus. The ACK comes in t + 2, and WRITE takes
; the target from DBUS's FIFO in t + 3 (MICROARCH.md §5.3) and flushes.
; The younger read waits in t + 1 and t + 2, and is then dropped.
        MOVE    R8, target
        MOVE    PC, @R8
        MOVE    R3, @R4
        HALT
back    HALT
data    .DAT    7
target  .DAT    back
