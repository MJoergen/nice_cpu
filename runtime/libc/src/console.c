// putchar, puts, and getchar, on the console routines of nice.c.
#include <nice.h>
#include <stdio.h>
#include "internal.h"

int __stdin_back = EOF;

int putchar(int c)
{
    nice_putc(c);
    return (unsigned char)c;
}

int puts(const char *s)
{
    nice_print(s);
    nice_putc('\n');
    return 0;
}

// Waits for the next input byte. nice_getc returns -1, which is EOF, once
// the emulator's input has ended.
int getchar(void)
{
    if (__stdin_back != EOF) {
        int c = __stdin_back;
        __stdin_back = EOF;
        return c;
    }
    return nice_getc();
}
