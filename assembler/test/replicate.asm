start_copy	.equ	0x10
pc		.equ	r15
		.org	0
start		move 	r2 start_copy
		move 	r1 start
		move 	r3 end
loop		move  	@r2++ @r1++
		xor[m]	r0 r1 r3
	?!Z	move 	pc loop
end		halt


