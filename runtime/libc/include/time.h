#ifndef _TIME_H
#define _TIME_H

#include <stddef.h>

// There is a clock but no calendar: no device tells the date. clock counts
// microseconds of running time, from the counter of SYSTEM.md §3.
typedef unsigned long clock_t;
typedef long long time_t;

#define CLOCKS_PER_SEC ((clock_t)1000000)

// The microseconds since reset, modulo 2^32, about 71 minutes. It is
// unsigned, so the difference of two readings is right across a wrap.
clock_t clock(void);

// The calendar time is not available: returns -1, and stores it in *t if
// t is not null.
time_t time(time_t *t);

#endif
