; A word written to memory while the core is paused (MICROARCH.md §6.1).
; tb_core runs it one step at a time, and while the core is paused after
; two steps, writes 0x00010100, "MOVE R4, R2", over the word at patch, which
; the pipelined core has fetched by then (hdl/Makefile, pausepatch). The
; core must fetch it again from R15 when it goes on, so the trace,
; test/pausepatch.expected, has R4 = 2, where the emulator, which sees no
; write, has R4 = 1.
        MOVE    R1, 1
        MOVE    R2, 2
        MOVE    R3, R1          ; paused before this step, at R15 = patch - 1
patch   MOVE    R4, R1          ; becomes MOVE R4, R2
        HALT
