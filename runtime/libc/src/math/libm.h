// The internal header of the math routines, in place of musl's
// src/internal/libm.h, from which it is adapted (COPYRIGHT). It keeps
// only what the files of this directory use. Of those, sin.c, cos.c,
// tan.c, and builtin.c are this library's own, and the others musl's,
// unchanged (README.md, Math functions).
//
// It differs from musl's in two more ways:
// - wasm32's long double is a binary128, which the float library does not
//   support, so there is no ldshape, and LDBL_MAX_EXP is taken as 1024:
//   __rem_pio2_large then keeps only the digits of 2/pi that double
//   needs, and no long double code is compiled.
// - features.h, which defines hidden, is a stand-in for musl's.
#ifndef _LIBM_H
#define _LIBM_H

#include <stdint.h>
#include <float.h>
#include <math.h>
#include <features.h>

#undef LDBL_MAX_EXP
#define LDBL_MAX_EXP 1024

#define predict_true(x) __builtin_expect(!!(x), 1)
#define predict_false(x) __builtin_expect(x, 0)

#define asuint64(f) ((union{double _f; uint64_t _i;}){f})._i
#define asdouble(i) ((union{uint64_t _i; double _f;}){i})._f

#define GET_HIGH_WORD(hi,d)                       \
do {                                              \
  (hi) = asuint64(d) >> 32;                       \
} while (0)

#define INSERT_WORDS(d,hi,lo)                     \
do {                                              \
  (d) = asdouble(((uint64_t)(hi)<<32) | (uint32_t)(lo)); \
} while (0)

#define SET_LOW_WORD(d,lo)                        \
  INSERT_WORDS(d, asuint64(d)>>32, lo)

hidden int    __rem_pio2_large(double*,double*,int,int,int);

hidden int    __rem_pio2(double,double*);
hidden double __sin(double,double,int);
hidden double __cos(double,double);
hidden double __tan(double,double,int);

// The FPU's SIN, COS, and TAN, the float library's _nice_sin, _nice_cos,
// and _nice_tan, which give a NaN from the high word NICE_TRIG_LIMIT on,
// just below 2^20 * pi/2 (DEVICES.md §11.3).
#define NICE_TRIG_LIMIT 0x413921fb
__attribute__((import_module("env"), import_name("nice_sin"))) double __nice_sin(double);
__attribute__((import_module("env"), import_name("nice_cos"))) double __nice_cos(double);
__attribute__((import_module("env"), import_name("nice_tan"))) double __nice_tan(double);

#endif
