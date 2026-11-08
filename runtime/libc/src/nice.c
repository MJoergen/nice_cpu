// The device routines of ABI.md, the only part of the library that
// touches hardware. nice_putc is not here: it is an import from env, the
// routine _nice_putc of lib.nasm (nice.h), so that the output follows
// ___putc_vector.
#include <nice.h>

// A console read returns the byte with NICE_CONSOLE_BYTE set, 0 while no
// byte is there yet, or NICE_CONSOLE_END once the line's input has ended.
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

unsigned long long nice_micros(void)
{
    unsigned lo = nice_peek(NICE_TIME_LO);
    unsigned hi = nice_peek(NICE_TIME_HI);
    return (unsigned long long)hi << 32 | lo;
}

// The read of CLOCK_USEC takes the snapshot of the seconds, so it comes
// first. The writes of the seconds stage them, and the write of CLOCK_USEC
// sets the clock to all three at once.
unsigned long long nice_clock(unsigned *usec)
{
    unsigned us = nice_peek(NICE_CLOCK_USEC);
    unsigned lo = nice_peek(NICE_CLOCK_SEC_LO);
    unsigned hi = nice_peek(NICE_CLOCK_SEC_HI);
    if (usec)
        *usec = us;
    return (unsigned long long)hi << 32 | lo;
}

int nice_clock_isset(void)
{
    return nice_peek(NICE_CLOCK_STATUS) & 1;
}

void nice_clock_set(unsigned long long sec, unsigned usec)
{
    nice_poke(NICE_CLOCK_SEC_LO, (unsigned)sec);
    nice_poke(NICE_CLOCK_SEC_HI, (unsigned)(sec >> 32));
    nice_poke(NICE_CLOCK_USEC, usec);
}

void nice_screen_put(int col, int row, int c)
{
    nice_poke(NICE_SCREEN + (unsigned)row * NICE_SCREEN_COLS + (unsigned)col, (unsigned)c);
}

void nice_screen_clear(void)
{
    for (unsigned i = 0; i < NICE_SCREEN_COLS * NICE_SCREEN_ROWS; i++)
        nice_poke(NICE_SCREEN + i, NICE_SCREEN_BLANK);
}
