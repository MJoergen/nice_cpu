// Access to NICE memory and I/O devices from wasm code (WASM.md).
#ifndef _NICE_H
#define _NICE_H

// The device routines of ABI.md, with the same names and meanings as
// in the runtime library, but for nice_print, which takes the bytes of a
// C string, not one character per word. Programs use these, not the addresses below.

// Writes bits 7..0 of c to the console. Not defined in C: the translator
// turns this import into the assembly routine _nice_putc of lib.nasm
// (WASM.md), which goes through ___putc_vector, so that a program under a
// monitor prints on the monitor's output (ABI.md).
__attribute__((import_module("env"), import_name("nice_putc")))
void nice_putc(int c);

// Waits for the next input byte from the console and returns it, 0 to
// 255, or -1 once the line's input has ended. A keyboard's bytes may still
// come after that (SYSTEM.md §1).
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

// floor(sqrt(x)), with the math unit's ISQRT64 (SYSTEM.md §2), or in
// software on a system without it. Not defined in C: the translator turns
// this import into the routine _nice_isqrt64 of muldiv_mpu.nasm or
// muldiv_soft.nasm.
__attribute__((import_module("env"), import_name("nice_isqrt64")))
unsigned nice_isqrt64(unsigned long long x);

// The microseconds since reset, from the counter of SYSTEM.md §3 that is
// exact on every board. The same rule about interrupt routines applies.
// There is no assembly routine for it: it is C only.
unsigned long long nice_micros(void);

// The clock of the time of day (SYSTEM.md §10), C only as well.
// nice_clock returns the seconds since the Unix epoch, and stores the
// microseconds within the second in *usec if usec is not null. The rule
// about interrupt routines applies to its snapshot. nice_clock_isset
// returns 1 if the clock holds a time, set by a program or the system, and
// 0 if not. nice_clock_set sets it to sec seconds and usec microseconds,
// 999999 at most.
unsigned long long nice_clock(unsigned *usec);
int nice_clock_isset(void);
void nice_clock_set(unsigned long long sec, unsigned usec);

// The emulator's 80x25 character screen. nice_screen_put writes c, the
// character in bits 7..0 and its color above, to a column, 0 to 79, of a
// row, 0 to 24. nice_screen_clear writes NICE_SCREEN_BLANK, a blank in
// white on black, to every word.
void nice_screen_put(int col, int row, int c);
void nice_screen_clear(void);

#define NICE_SCREEN_COLS 80
#define NICE_SCREEN_ROWS 25
// The blank that nice_screen_clear writes: a space in white on black, the
// colors a board's monitor writes in, so that the cursor of SYSTEM.md §1.4,
// which swaps the colors of its cell, shows on it. A blank of color 0 is
// black on black, and so is the cursor on it.
#define NICE_SCREEN_BLANK 0x000FFF20u

// The devices' addresses and bits (SYSTEM.md §1, §3, §10), for nice.c. The
// console is read here; it is written through nice_putc.
#define NICE_CONSOLE 0xFFFFFF00u
#define NICE_CONSOLE_BYTE 0x100u
#define NICE_CONSOLE_END 0x200u
#define NICE_CYCLE_LO 0xFFFFFF40u
#define NICE_CYCLE_HI 0xFFFFFF41u
#define NICE_INSTR_LO 0xFFFFFF42u
#define NICE_INSTR_HI 0xFFFFFF43u
#define NICE_TIME_LO 0xFFFFFF44u
#define NICE_TIME_HI 0xFFFFFF45u
#define NICE_CLOCK_USEC 0xFFFFFF46u
#define NICE_CLOCK_SEC_LO 0xFFFFFF47u
#define NICE_CLOCK_SEC_HI 0xFFFFFF48u
#define NICE_CLOCK_STATUS 0xFFFFFF49u
#define NICE_SCREEN 0xFFFF0000u

// Reads the NICE word at a word address.
__attribute__((import_module("nice"), import_name("peek")))
unsigned nice_peek(unsigned addr);

// Writes val to the NICE word at a word address.
__attribute__((import_module("nice"), import_name("poke")))
void nice_poke(unsigned addr, unsigned val);

#endif
