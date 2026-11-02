// clock reads the microsecond counter, which counts the host's time in the
// emulator. Two readings may fall in one microsecond, so the test reads
// until the counter moves, at most 100 times, as with --no-cycle-counter
// its words are memory and never move. Then the readings differ by a
// little, and the difference is right when taken as unsigned. time has no
// calendar to read and returns -1. main returns the number of checks that
// fail, 0.
#include <stdio.h>
#include <time.h>

int main(void)
{
    int fails = 0;
    clock_t c1 = clock();
    clock_t c2 = clock();
    for (int i = 0; i < 100 && c2 == c1; i++)
        c2 = clock();
    clock_t d = c2 - c1;
    fails += !(d > 0 && d < 100000);
    fails += CLOCKS_PER_SEC != 1000000;

    // Across a wrap, the unsigned difference is still the elapsed time.
    clock_t before = 0xFFFFFFF0u;
    clock_t after = before + 32;
    fails += (after - before) != 32;

    time_t t = 5;
    fails += time(&t) != (time_t)-1 || t != (time_t)-1;
    fails += time(NULL) != (time_t)-1;

    printf("%d\n", fails);
    return fails;
}
