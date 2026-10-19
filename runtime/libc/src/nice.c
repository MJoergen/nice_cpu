// The device routines of ISA.md §9.3, the only part of the library that
// touches hardware.
#include <nice.h>

void nice_putc(int c)
{
    nice_poke(NICE_CONSOLE, (unsigned char)c);
}

// A console read returns the byte with NICE_CONSOLE_BYTE set, 0 while no
// byte is there yet, or NICE_CONSOLE_END once the emulator's input has
// ended.
int nice_pollc(void)
{
    unsigned v = nice_peek(NICE_CONSOLE);
    if (v & NICE_CONSOLE_BYTE)
        return (unsigned char)v;
    if (v & NICE_CONSOLE_END)
        return -1;
    return -2;
}

int nice_getc(void)
{
    int c;
    while ((c = nice_pollc()) == -2)
        ;
    return c;
}

void nice_print(const char *s)
{
    while (*s)
        nice_putc(*s++);
}

// The read of the low word takes the snapshot that the read of the high
// word returns (SYSTEM.md §3). nice_peek is never reordered.
unsigned long long nice_cycles(void)
{
    unsigned lo = nice_peek(NICE_CYCLE_LO);
    unsigned hi = nice_peek(NICE_CYCLE_HI);
    return (unsigned long long)hi << 32 | lo;
}

unsigned long long nice_instructions(void)
{
    unsigned lo = nice_peek(NICE_INSTR_LO);
    unsigned hi = nice_peek(NICE_INSTR_HI);
    return (unsigned long long)hi << 32 | lo;
}

void nice_screen_put(int col, int row, int c)
{
    nice_poke(NICE_SCREEN + (unsigned)row * NICE_SCREEN_COLS + (unsigned)col, (unsigned)c);
}

void nice_screen_clear(void)
{
    for (unsigned i = 0; i < NICE_SCREEN_COLS * NICE_SCREEN_ROWS; i++)
        nice_poke(NICE_SCREEN + i, 0x20);
}
