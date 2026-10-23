// clock and time, on the microsecond counter of nice.c.
#include <nice.h>
#include <time.h>

clock_t clock(void)
{
    return (clock_t)nice_micros();
}

time_t time(time_t *t)
{
    if (t)
        *t = -1;
    return -1;
}
