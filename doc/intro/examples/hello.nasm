; Print a string on the console with a subroutine.
SP              .EQU    R13
CONSOLE         .EQU    0xFFFFFF00

                MOVE    SP, 0x1000      ; set up the stack
                MOVE    R1, TEXT        ; the argument: the string's address
                CALL    PUTS            ; call the subroutine
                MOVE    @CONSOLE, 10    ; a newline
                HALT

; PUTS prints the string at R1. The string ends with a 0 word.
PUTS            MOVE[M] R2, @R1++       ; next character, and set Z if it is 0
        ?Z      RET                     ; at the end: return
                MOVE    @CONSOLE, R2    ; print the character
                JMP     PUTS            ; and loop

TEXT            .ASCII_L 'Hello, NICE!'
