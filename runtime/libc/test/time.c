// clock reads the microsecond counter, which counts the host's time in the
// emulator. Two readings may fall in one microsecond, so the test reads
// until the counter moves, at most 100 times, as with --no-cycle-counter
// its words are memory and never move. Then the readings differ by a
// little, and the difference is right when taken as unsigned. time reads
// the clock of the time of day (DEVICES.md §10), which the emulator sets
// from the host, so it is set, and later than 2023. Set to a time, it
// reads it back, as the read follows the write by microseconds. main
// returns the number of checks that fail, 0. With --no-cycle-counter, as
// hdl/test/programs.py runs it on the core and the emulator alike, the
// clock's words are memory and some checks fail, the same on both.
#include <nice.h>
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

    // The host's time: 2023-11-14 is 1700000000 seconds after the epoch.
    fails += nice_clock_isset() != 1;
    time_t t = 5;
    time_t now = time(&t);
    fails += now < 1700000000 || t != now;
    unsigned usec = 1000000;
    fails += nice_clock(&usec) < 1700000000 || usec > 999999;

    // A time set reads back, the high word of the seconds too.
    nice_clock_set(0x123456789ull, 0);
    fails += time(NULL) != (time_t)0x123456789ll;
    fails += nice_clock(&usec) != 0x123456789ull || usec > 999999;
    nice_poke(NICE_CLOCK_STATUS, 0); // clears "set": no time
    fails += nice_clock_isset() != 0;
    fails += time(NULL) != (time_t)-1;

    printf("%d\n", fails);
    return fails;
}
