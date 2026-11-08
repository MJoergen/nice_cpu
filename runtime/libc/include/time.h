#ifndef _TIME_H
#define _TIME_H

#include <stddef.h>

// clock counts microseconds of running time, from the counter of
// SYSTEM.md §3, and time reads the clock of the time of day of §10.
typedef unsigned long clock_t;
typedef long long time_t;

#define CLOCKS_PER_SEC ((clock_t)1000000)

// The microseconds since reset, modulo 2^32, about 71 minutes. It is
// unsigned, so the difference of two readings is right across a wrap.
clock_t clock(void);

// The seconds since the Unix epoch, or -1 if the clock of the time of day
// holds no time ("set" is 0, SYSTEM.md §10). Stores the same in *t if t is
// not null.
time_t time(time_t *t);

#endif
