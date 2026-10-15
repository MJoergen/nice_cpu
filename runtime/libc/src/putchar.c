// The only part of the library that touches hardware.
#include <nice.h>
#include <stdio.h>

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
