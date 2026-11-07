// The functions that math.h maps to clang's built-ins, for code that takes
// their address or calls them by name, as (sqrt)(x) does. Each is a wasm
// instruction, so a call of the float library or a bit operation. The
// float library rounds to nearest only and raises no exceptions, so
// nearbyint is rint.
#include <math.h>

double (ceil)(double x)
{
    return __builtin_ceil(x);
}

float (ceilf)(float x)
{
    return __builtin_ceilf(x);
}

double (copysign)(double x, double y)
{
    return __builtin_copysign(x, y);
}

float (copysignf)(float x, float y)
{
    return __builtin_copysignf(x, y);
}

double (fabs)(double x)
{
    return __builtin_fabs(x);
}

float (fabsf)(float x)
{
    return __builtin_fabsf(x);
}

double (floor)(double x)
{
    return __builtin_floor(x);
}

float (floorf)(float x)
{
    return __builtin_floorf(x);
}

double (nearbyint)(double x)
{
    return __builtin_rint(x);
}

float (nearbyintf)(float x)
{
    return __builtin_rintf(x);
}

double (rint)(double x)
{
    return __builtin_rint(x);
}

float (rintf)(float x)
{
    return __builtin_rintf(x);
}

double (sqrt)(double x)
{
    return __builtin_sqrt(x);
}

float (sqrtf)(float x)
{
    return __builtin_sqrtf(x);
}

double (trunc)(double x)
{
    return __builtin_trunc(x);
}

float (truncf)(float x)
{
    return __builtin_truncf(x);
}
