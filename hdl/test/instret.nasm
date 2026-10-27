; Reads of the instruction counter (SYSTEM.md §3) in the places where a
; pipelined core may count an instruction too early or too late: right
; after a store to RAM, which tb_core's data bus decoder (src/wb_dmux.vhd)
; makes the read wait for, right after a read of RAM, as the source of a
; store, and twice in one instruction. A read returns the number of
; instructions before the reading one, so each value is the step of its
; instruction.
;
;   step                                   result
;    0   MOVE @MEM, 1                       a store to RAM
;    1   MOVE R1, @INSTR_LO                 R1 = 1
;    2   MOVE R2, @MEM                      R2 = 1, a read of RAM
;    3   MOVE R3, @INSTR_LO                 R3 = 3
;    4   MOVE @MEM, @INSTR_LO               [MEM] = 4
;    5   MOVE @MEM, 2
;    6   ADD R4, @INSTR_LO, @INSTR_LO       R4 = 12: both reads give 6
;    7   MOVE @MEM, 3
;    8   MOVE @MEM2, @INSTR_LO              [MEM2] = 8
;    9   MOVE R5, @INSTR_LO                 R5 = 9
;   10   MOVE R6, @MEM2                     R6 = 8
;   11   ADD R7, @INSTR_LO, R0              R7 = 11
;   12   HALT
;
; The trace shows every value, and must equal the emulator's.
INSTR_LO        .EQU    0xFFFFFF42
MEM             .EQU    0x100
MEM2            .EQU    0x101
                MOVE    @MEM, 1
                MOVE    R1, @INSTR_LO
                MOVE    R2, @MEM
                MOVE    R3, @INSTR_LO
                MOVE    @MEM, @INSTR_LO
                MOVE    @MEM, 2
                ADD     R4, @INSTR_LO, @INSTR_LO
                MOVE    @MEM, 3
                MOVE    @MEM2, @INSTR_LO
                MOVE    R5, @INSTR_LO
                MOVE    R6, @MEM2
                ADD     R7, @INSTR_LO, R0
                HALT
