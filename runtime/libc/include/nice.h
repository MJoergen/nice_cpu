// Access to NICE memory and I/O devices from wasm code (WASM.md).
#ifndef _NICE_H
#define _NICE_H

// The device routines of ABI.md, with the same names and meanings as
// in the runtime library. Programs use these, not the addresses below.

// Writes bits 7..0 of c to the console.
void nice_putc(int c);

// Waits for the next input byte from the console and returns it, 0 to
// 255, or -1 once the input has ended.
int nice_getc(void);

// Like nice_getc, but returns -2 at once if no byte is waiting.
int nice_pollc(void);

// Writes the bytes of s up to its first 0 to the console, with no newline.
void nice_print(const char *s);

// The performance counters (SYSTEM.md §3): the clock cycles and the
// instructions since reset. An interrupt routine must not read them
// while the code it interrupted is reading one.
unsigned long long nice_cycles(void);
unsigned long long nice_instructions(void);

// The emulator's 80x25 character screen. nice_screen_put writes c, the
// character in bits 7..0 and its color above, to a column, 0 to 79, of a
// row, 0 to 24. nice_screen_clear writes a blank, 0x20, to every word.
void nice_screen_put(int col, int row, int c);
void nice_screen_clear(void);

#define NICE_SCREEN_COLS 80
#define NICE_SCREEN_ROWS 25

// The devices' addresses and bits (SYSTEM.md §1, §3), for nice.c.
#define NICE_CONSOLE 0xFFFFFF00u
#define NICE_CONSOLE_BYTE 0x100u
#define NICE_CONSOLE_END 0x200u
#define NICE_CYCLE_LO 0xFFFFFF40u
#define NICE_CYCLE_HI 0xFFFFFF41u
#define NICE_INSTR_LO 0xFFFFFF42u
#define NICE_INSTR_HI 0xFFFFFF43u
#define NICE_SCREEN 0xFFFF0000u

// Reads the NICE word at a word address.
__attribute__((import_module("nice"), import_name("peek")))
unsigned nice_peek(unsigned addr);

// Writes val to the NICE word at a word address.
__attribute__((import_module("nice"), import_name("poke")))
void nice_poke(unsigned addr, unsigned val);

#endif
