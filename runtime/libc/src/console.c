// The only part of the library that touches hardware: the console at
// 0xFFFFFF00 (ISA.md §8.3).
#include <nice.h>
#include <stdio.h>
#include "internal.h"

int __stdin_back = EOF;

int putchar(int c)
{
    nice_poke(NICE_CONSOLE, (unsigned char)c);
    return (unsigned char)c;
}

int puts(const char *s)
{
    while (*s)
        putchar(*s++);
    putchar('\n');
    return 0;
}

// Waits for the next input byte. A read of the console returns the byte
// with NICE_CONSOLE_BYTE set, 0 while no byte is there yet, or
// NICE_CONSOLE_END once the emulator's input has ended.
int getchar(void)
{
    if (__stdin_back != EOF) {
        int c = __stdin_back;
        __stdin_back = EOF;
        return c;
    }
    for (;;) {
        unsigned v = nice_peek(NICE_CONSOLE);
        if (v & NICE_CONSOLE_BYTE)
            return (unsigned char)v;
        if (v & NICE_CONSOLE_END)
            return EOF;
    }
}
