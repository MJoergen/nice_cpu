// The device routines of nice.h, with "ab" as the console input. main
// returns the number of checks of the counters and the screen that fail, 0.
#include <nice.h>
#include <stdio.h>

int main(void)
{
    nice_print("Hi");
    nice_putc(0x10A); // only bits 7..0 count: a newline

    // 'a', 'b', then the end of the input: 97 98 -1 -1.
    int a = nice_getc();
    int b = nice_pollc();
    int c = nice_pollc();
    int d = nice_getc();
    printf("%d %d %d %d\n", a, b, c, d);

    // Each reading counts the instructions of the one before it, so the
    // counters grow. The emulator counts one cycle per instruction here,
    // as there are no interrupts, and the counts are far below 2^32.
    int fails = 0;
    unsigned long long i1 = nice_instructions();
    unsigned long long c1 = nice_cycles();
    unsigned long long i2 = nice_instructions();
    unsigned long long c2 = nice_cycles();
    fails += !(i1 > 0 && i2 > i1 && c2 > c1);
    fails += !(c1 > i1 && c2 > i2);
    fails += (i2 >> 32) != 0 || (c2 >> 32) != 0;

    // The screen is ordinary memory on the emulator, so it reads back.
    nice_screen_clear();
    nice_screen_put(0, 0, 'O');
    nice_screen_put(2, 1, 0xC80FF021);
    nice_screen_put(79, 24, 'Z');
    fails += nice_peek(NICE_SCREEN) != 'O';
    fails += nice_peek(NICE_SCREEN + 1) != 0x20;
    fails += nice_peek(NICE_SCREEN + 82) != 0xC80FF021;
    fails += nice_peek(NICE_SCREEN + 1998) != 0x20;
    fails += nice_peek(NICE_SCREEN + 1999) != 'Z';
    nice_print("done\n");
    return fails;
}
