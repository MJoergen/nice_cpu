// The math functions of C, in double and float. Most are routines of the
// float library, on the functions of the FPU (DEVICES.md §11.3), and are
// declared here as imports from env, at the labels _name (WASM.md). sin,
// cos, and tan are C, on the FPU's functions, and musl's code for a huge
// argument. frexp, modf, fmin, and fmax are musl's (src/math/COPYRIGHT),
// and so are the classification macros, adapted. There are no long double
// functions: wasm32's long double is a binary128, which the float library
// does not support.
//
// No function sets errno, and the C library reads no flag of the FPU, so
// math_errhandling is 0: a domain error gives a NaN, and a pole or an
// overflow an infinity, with no other report (runtime/README.md, Math
// functions).
#ifndef _MATH_H
#define _MATH_H

// wasm evaluates float and double in their own precision.
typedef float float_t;
typedef double double_t;

#define NAN __builtin_nanf("")
#define INFINITY __builtin_inff()
#define HUGE_VALF INFINITY
#define HUGE_VAL ((double)INFINITY)

#define MATH_ERRNO 1
#define MATH_ERREXCEPT 2
#define math_errhandling 0

#define FP_NAN 0
#define FP_INFINITE 1
#define FP_ZERO 2
#define FP_SUBNORMAL 3
#define FP_NORMAL 4

// The classification macros test the bits, which takes no call of the
// float library. Each takes a float or a double.
static __inline unsigned __FLOAT_BITS(float __f)
{
    union {
        float __f;
        unsigned __i;
    } __u;
    __u.__f = __f;
    return __u.__i;
}

static __inline unsigned long long __DOUBLE_BITS(double __f)
{
    union {
        double __f;
        unsigned long long __i;
    } __u;
    __u.__f = __f;
    return __u.__i;
}

static __inline int __fpclassifyf(float __x)
{
    unsigned __e = __FLOAT_BITS(__x) >> 23 & 0xff;
    if (__e == 0)
        return __FLOAT_BITS(__x) << 1 ? FP_SUBNORMAL : FP_ZERO;
    if (__e == 0xff)
        return __FLOAT_BITS(__x) << 9 ? FP_NAN : FP_INFINITE;
    return FP_NORMAL;
}

static __inline int __fpclassify(double __x)
{
    unsigned __e = __DOUBLE_BITS(__x) >> 52 & 0x7ff;
    if (__e == 0)
        return __DOUBLE_BITS(__x) << 1 ? FP_SUBNORMAL : FP_ZERO;
    if (__e == 0x7ff)
        return __DOUBLE_BITS(__x) << 12 ? FP_NAN : FP_INFINITE;
    return FP_NORMAL;
}

#define fpclassify(x) (sizeof(x) == sizeof(float) ? __fpclassifyf(x) : __fpclassify(x))

#define isinf(x) ( \
    sizeof(x) == sizeof(float) ? (__FLOAT_BITS(x) & 0x7fffffff) == 0x7f800000 : \
    (__DOUBLE_BITS(x) & -1ULL >> 1) == 0x7ffULL << 52)

#define isnan(x) ( \
    sizeof(x) == sizeof(float) ? (__FLOAT_BITS(x) & 0x7fffffff) > 0x7f800000 : \
    (__DOUBLE_BITS(x) & -1ULL >> 1) > 0x7ffULL << 52)

#define isnormal(x) ( \
    sizeof(x) == sizeof(float) ? ((__FLOAT_BITS(x) + 0x00800000) & 0x7fffffff) >= 0x01000000 : \
    ((__DOUBLE_BITS(x) + (1ULL << 52)) & -1ULL >> 1) >= 1ULL << 53)

#define isfinite(x) ( \
    sizeof(x) == sizeof(float) ? (__FLOAT_BITS(x) & 0x7fffffff) < 0x7f800000 : \
    (__DOUBLE_BITS(x) & -1ULL >> 1) < 0x7ffULL << 52)

#define signbit(x) ( \
    sizeof(x) == sizeof(float) ? (int)(__FLOAT_BITS(x) >> 31) : \
    (int)(__DOUBLE_BITS(x) >> 63))

// The routines of the float library.
#define __NICE_FPU(name) __attribute__((import_module("env"), import_name(#name)))
__NICE_FPU(acos) double acos(double);
__NICE_FPU(acosf) float acosf(float);
__NICE_FPU(asin) double asin(double);
__NICE_FPU(asinf) float asinf(float);
__NICE_FPU(atan) double atan(double);
__NICE_FPU(atanf) float atanf(float);
__NICE_FPU(atan2) double atan2(double, double);
__NICE_FPU(atan2f) float atan2f(float, float);
__NICE_FPU(exp) double exp(double);
__NICE_FPU(expf) float expf(float);
__NICE_FPU(exp2) double exp2(double);
__NICE_FPU(exp2f) float exp2f(float);
__NICE_FPU(fmod) double fmod(double, double);
__NICE_FPU(fmodf) float fmodf(float, float);
__NICE_FPU(hypot) double hypot(double, double);
__NICE_FPU(hypotf) float hypotf(float, float);
__NICE_FPU(ldexp) double ldexp(double, int);
__NICE_FPU(ldexpf) float ldexpf(float, int);
__NICE_FPU(log) double log(double);
__NICE_FPU(logf) float logf(float);
__NICE_FPU(log10) double log10(double);
__NICE_FPU(log10f) float log10f(float);
__NICE_FPU(log2) double log2(double);
__NICE_FPU(log2f) float log2f(float);
__NICE_FPU(pow) double pow(double, double);
__NICE_FPU(powf) float powf(float, float);
__NICE_FPU(round) double round(double);
__NICE_FPU(roundf) float roundf(float);
__NICE_FPU(scalbn) double scalbn(double, int);
__NICE_FPU(scalbnf) float scalbnf(float, int);
#undef __NICE_FPU

// The functions in C.
double ceil(double);
float ceilf(float);
double copysign(double, double);
float copysignf(float, float);
double cos(double);
float cosf(float);
double fabs(double);
float fabsf(float);
double floor(double);
float floorf(float);
double fmax(double, double);
float fmaxf(float, float);
double fmin(double, double);
float fminf(float, float);
double frexp(double, int *);
float frexpf(float, int *);
double modf(double, double *);
float modff(float, float *);
double nearbyint(double);
float nearbyintf(float);
double rint(double);
float rintf(float);
double sin(double);
float sinf(float);
double sqrt(double);
float sqrtf(float);
double tan(double);
float tanf(float);
double trunc(double);
float truncf(float);

// These are single wasm instructions, which nicewasm translates into the
// float library's routines, or into bit operations for fabs and copysign.
// Code compiled with -ffreestanding, as the library's must be, would
// otherwise call the functions above, which do the same.
#define ceil(x) __builtin_ceil(x)
#define ceilf(x) __builtin_ceilf(x)
#define copysign(x, y) __builtin_copysign(x, y)
#define copysignf(x, y) __builtin_copysignf(x, y)
#define fabs(x) __builtin_fabs(x)
#define fabsf(x) __builtin_fabsf(x)
#define floor(x) __builtin_floor(x)
#define floorf(x) __builtin_floorf(x)
#define nearbyint(x) __builtin_rint(x)
#define nearbyintf(x) __builtin_rintf(x)
#define rint(x) __builtin_rint(x)
#define rintf(x) __builtin_rintf(x)
#define sqrt(x) __builtin_sqrt(x)
#define sqrtf(x) __builtin_sqrtf(x)
#define trunc(x) __builtin_trunc(x)
#define truncf(x) __builtin_truncf(x)

// POSIX's constants, which C programs often expect.
#define M_E 2.7182818284590452354         // e
#define M_LOG2E 1.4426950408889634074     // log2(e)
#define M_LOG10E 0.43429448190325182765   // log10(e)
#define M_LN2 0.69314718055994530942      // ln(2)
#define M_LN10 2.30258509299404568402     // ln(10)
#define M_PI 3.14159265358979323846       // pi
#define M_PI_2 1.57079632679489661923     // pi/2
#define M_PI_4 0.78539816339744830962     // pi/4
#define M_1_PI 0.31830988618379067154     // 1/pi
#define M_2_PI 0.63661977236758134308     // 2/pi
#define M_2_SQRTPI 1.12837916709551257390 // 2/sqrt(pi)
#define M_SQRT2 1.41421356237309504880    // sqrt(2)
#define M_SQRT1_2 0.70710678118654752440  // 1/sqrt(2)

#endif
