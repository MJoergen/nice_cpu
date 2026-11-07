// The internal header of the math routines, in place of musl's
// src/internal/libm.h, from which it is adapted (COPYRIGHT). The other
// files of this directory are musl's, unchanged (README.md, C library).
//
// It differs from musl's in three ways:
// - NICE has no floating-point exceptions, as the float library raises
//   none, so FORCE_EVAL and fp_force_eval, which compute a value only to
//   raise one, compute nothing.
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

// Support non-nearest rounding mode, as musl does. The float library
// rounds to nearest only, but this keeps the code the same as musl's.
#define WANT_ROUNDING 1
// Support signaling NaNs.
#define WANT_SNAN 0

#define issignalingf_inline(x) 0
#define issignaling_inline(x) 0

#define TOINT_INTRINSICS 0

#define predict_true(x) __builtin_expect(!!(x), 1)
#define predict_false(x) __builtin_expect(x, 0)

// Evaluate an expression as the given type. wasm has no excess precision
// (FLT_EVAL_METHOD is 0), so this is only an assignment.
static inline float eval_as_float(float x)
{
	float y = x;
	return y;
}

static inline double eval_as_double(double x)
{
	double y = x;
	return y;
}

// fp_barrier returns its input, but limits code transformations as if it
// had a side effect and returned an arbitrary value.
static inline float fp_barrierf(float x)
{
	volatile float y = x;
	return y;
}

static inline double fp_barrier(double x)
{
	volatile double y = x;
	return y;
}

// musl computes these only for the exceptions they raise.
static inline void fp_force_evalf(float x)
{
	(void)x;
}

static inline void fp_force_eval(double x)
{
	(void)x;
}

#define FORCE_EVAL(x) ((void)(x))

#define asuint(f) ((union{float _f; uint32_t _i;}){f})._i
#define asfloat(i) ((union{uint32_t _i; float _f;}){i})._f
#define asuint64(f) ((union{double _f; uint64_t _i;}){f})._i
#define asdouble(i) ((union{uint64_t _i; double _f;}){i})._f

#define EXTRACT_WORDS(hi,lo,d)                    \
do {                                              \
  uint64_t __u = asuint64(d);                     \
  (hi) = __u >> 32;                               \
  (lo) = (uint32_t)__u;                           \
} while (0)

#define GET_HIGH_WORD(hi,d)                       \
do {                                              \
  (hi) = asuint64(d) >> 32;                       \
} while (0)

#define GET_LOW_WORD(lo,d)                        \
do {                                              \
  (lo) = (uint32_t)asuint64(d);                   \
} while (0)

#define INSERT_WORDS(d,hi,lo)                     \
do {                                              \
  (d) = asdouble(((uint64_t)(hi)<<32) | (uint32_t)(lo)); \
} while (0)

#define SET_HIGH_WORD(d,hi)                       \
  INSERT_WORDS(d, hi, (uint32_t)asuint64(d))

#define SET_LOW_WORD(d,lo)                        \
  INSERT_WORDS(d, asuint64(d)>>32, lo)

#define GET_FLOAT_WORD(w,d)                       \
do {                                              \
  (w) = asuint(d);                                \
} while (0)

#define SET_FLOAT_WORD(d,w)                       \
do {                                              \
  (d) = asfloat(w);                               \
} while (0)

hidden int    __rem_pio2_large(double*,double*,int,int,int);

hidden int    __rem_pio2(double,double*);
hidden double __sin(double,double,int);
hidden double __cos(double,double);
hidden double __tan(double,double,int);

hidden int    __rem_pio2f(float,double*);
hidden float  __sindf(double);
hidden float  __cosdf(double);
hidden float  __tandf(double,int);

// The special results: each computes its value with float operations, as
// musl's do, for the exceptions they would raise elsewhere.
hidden float __math_xflowf(uint32_t, float);
hidden float __math_uflowf(uint32_t);
hidden float __math_oflowf(uint32_t);
hidden float __math_divzerof(uint32_t);
hidden float __math_invalidf(float);
hidden double __math_xflow(uint32_t, double);
hidden double __math_uflow(uint32_t);
hidden double __math_oflow(uint32_t);
hidden double __math_divzero(uint32_t);
hidden double __math_invalid(double);

#endif
