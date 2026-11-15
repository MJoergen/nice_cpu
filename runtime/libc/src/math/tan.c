// tan and tanf. Below 2^20 * pi/2, and for an infinity or a NaN, tan is
// the FPU's TAN (DEVICES.md §11.3), through the float library's
// _nice_tan. From there on, TAN gives a NaN, and tan is musl's: the
// reduction of a huge argument, __rem_pio2_large, and the kernels, as in
// musl's tan.c (COPYRIGHT). tanf is tan rounded to float.
#include "libm.h"

double tan(double x)
{
    double y[2];
    uint32_t ix;
    unsigned n;

    GET_HIGH_WORD(ix, x);
    ix &= 0x7fffffff;
    if (ix < NICE_TRIG_LIMIT || ix >= 0x7ff00000)
        return __nice_tan(x);
    n = __rem_pio2(x, y);
    return __tan(y[0], y[1], n & 1);
}

float tanf(float x)
{
    return tan(x);
}
