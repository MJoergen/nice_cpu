// clock, on the microsecond counter of nice.c, and time, on its clock of
// the time of day.
#include <nice.h>
#include <time.h>

clock_t clock(void)
{
    return (clock_t)nice_micros();
}

time_t time(time_t *t)
{
    time_t now = nice_clock_isset() ? (time_t)nice_clock(0) : (time_t)-1;
    if (t)
        *t = now;
    return now;
}
