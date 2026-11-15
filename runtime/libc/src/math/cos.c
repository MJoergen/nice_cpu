// cos and cosf. Below 2^20 * pi/2, and for an infinity or a NaN, cos is
// the FPU's COS (DEVICES.md §11.3), through the float library's
// _nice_cos. From there on, COS gives a NaN, and cos is musl's: the
// reduction of a huge argument, __rem_pio2_large, and the kernels, as in
// musl's cos.c (COPYRIGHT). cosf is cos rounded to float.
#include "libm.h"

double cos(double x)
{
    double y[2];
    uint32_t ix;
    unsigned n;

    GET_HIGH_WORD(ix, x);
    ix &= 0x7fffffff;
    if (ix < NICE_TRIG_LIMIT || ix >= 0x7ff00000)
        return __nice_cos(x);
    n = __rem_pio2(x, y);
    switch (n & 3) {
    case 0:
        return __cos(y[0], y[1]);
    case 1:
        return -__sin(y[0], y[1], 1);
    case 2:
        return -__cos(y[0], y[1]);
    default:
        return __sin(y[0], y[1], 1);
    }
}

float cosf(float x)
{
    return cos(x);
}
