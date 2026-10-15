SP	.EQU	R13
PC	.EQU	R15
GS      .EQU    0x400
GW	.EQU	80
GH	.EQU	25
C_BOO   .EQU    0xC80FF000

	MOVE	SP	STB
	
	ADD	@--SP	10	PC	; addr + 4 vars on stack
        MOVE	@--SP	TEXT		; string addr
        MOVE    @--SP	C_BOO		; color: blue on orange
	MOVE	@--SP	5		; y coord
	MOVE	@--SP	10		; x coord
	MOVE	PC	PRINT		; jump to sub

	HALT

PRINT	MOVE	R3	GS		; get addr of graph mem
	MOVE	R2	@SP++		; get x
MULT	ADD	R1	R1	GW	; multiply by width
	DEC[M]	R2	R2
    ?!Z	MOVE	PC	MULT
	MOVE	R2	@SP++		; get y
	ADD	R1	R1	R2	; add to result

	ADD	R3	R3	R1	; add to graph mem address

	MOVE	R4	@SP++		; get color
	MOVE	R1	@SP++		; get string address
CHAR	ADD	R2	R4	@R1++	; add char to color
	MOVE	@R3++	R2		; move chars to graph mem
	MOVE[M]	R5	@R1		; check for null
    ?!Z	MOVE	PC	CHAR		; stop on null

	MOVE	PC	@SP++		; jump back

TEXT	.ASCII_L ' Yet another NICE hacker '

STE     .BLK 10
STB     .BLK 1




