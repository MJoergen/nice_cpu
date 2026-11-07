// The functions and macros of math.h, in double and float, on the cases
// whose results C17 Annex F gives, on exact results, and on a few values
// whose correctly rounded results are known. Each check compares the bits
// of a result, but that any NaN matches NAN. main prints each failure and
// the counts, and returns the number of failures, 0.
//
// The constants, correctly rounded:
//   pi    0x400921FB54442D18  0x40490FDB
//   pi/2  0x3FF921FB54442D18  0x3FC90FDB
//   pi/4  0x3FE921FB54442D18  0x3F490FDB
//   3pi/4 0x4002D97C7F3321D2  0x4016CBE4
//   e     0x4005BF0A8B145769  0x402DF854
//   ln 2  0x3FE62E42FEFA39EF  0x3F317218
//   √2    0x3FF6A09E667F3BCD  0x3FB504F3
// The double nearest pi, p, is below pi by 1.2246467991473532e-16, so
// sin(p) is that, 0x3CA1A62633145C07, to within its cube / 6. The float
// nearest pi is above it by 8.742278e-08, so sinf of it is
// -8.742278e-08, 0xB3BBBD2E. p / 4 is below pi/4 by a quarter of that,
// so tan(p / 4) is 1 - 6.1e-17, which rounds to 1 - 2^-53,
// 0x3FEFFFFFFFFFFFFF.
#include <float.h>
#include <math.h>
#include <stdio.h>

typedef unsigned long long u64;

static int checks, fails;

static u64 B(double d)
{
    union {
        double d;
        u64 i;
    } u = {d};
    return u.i;
}

static unsigned FB(float f)
{
    union {
        float f;
        unsigned i;
    } u = {f};
    return u.i;
}

static double D(u64 i)
{
    union {
        u64 i;
        double d;
    } u = {i};
    return u.d;
}

static float F(unsigned i)
{
    union {
        unsigned i;
        float f;
    } u = {i};
    return u.f;
}

// The checks are not inlined: each would bring its own printf arguments
// to main's frame, more than the stack holds.
#define NANBITS 0x7FF8000000000000ull
#define NANFBITS 0x7FC00000u

__attribute__((noinline)) static void checkd(const char *what, double got, u64 want)
{
    checks++;
    if (B(got) == want || (isnan(got) && want == NANBITS))
        return;
    fails++;
    printf("FAIL %s: %016llx, want %016llx\n", what, B(got), want);
}

__attribute__((noinline)) static void checkf(const char *what, float got, unsigned want)
{
    checks++;
    if (FB(got) == want || (isnan(got) && want == NANFBITS))
        return;
    fails++;
    printf("FAIL %s: %08x, want %08x\n", what, FB(got), want);
}

__attribute__((noinline)) static void checki(const char *what, int got, int want)
{
    checks++;
    if (got == want)
        return;
    fails++;
    printf("FAIL %s: %d, want %d\n", what, got, want);
}

#define CD(expr, want) checkd(#expr, expr, want)
#define CF(expr, want) checkf(#expr, expr, want)
#define CI(expr, want) checki(#expr, expr, want)

// The bits of some numbers.
#define P0 0x0000000000000000ull // +0
#define N0 0x8000000000000000ull // -0
#define P1 0x3FF0000000000000ull // 1
#define N1 0xBFF0000000000000ull // -1
#define PINF 0x7FF0000000000000ull
#define NINF 0xFFF0000000000000ull
#define PIB 0x400921FB54442D18ull
#define PI2 0x3FF921FB54442D18ull
#define PI4 0x3FE921FB54442D18ull
#define PI34 0x4002D97C7F3321D2ull
#define FP0 0x00000000u
#define FN0 0x80000000u
#define FP1 0x3F800000u
#define FN1 0xBF800000u
#define FPINF 0x7F800000u
#define FNINF 0xFF800000u
#define FPI 0x40490FDBu
#define FPI2 0x3FC90FDBu
#define FPI4 0x3F490FDBu
#define FPI34 0x4016CBE4u

// The arguments come through volatile variables, so that clang cannot
// compute the results itself.
static volatile double zero = 0.0, one = 1.0, two = 2.0, inf = INFINITY, nan_ = NAN;
static volatile float zf = 0.0f, onef = 1.0f, twof = 2.0f, inff = INFINITY, nanf_ = NAN;

static void trig(void)
{
    double p = D(PIB);
    float pf = F(FPI);
    CD(sin(-zero), N0);
    CD(sin(inf), NANBITS);
    CD(sin(nan_), NANBITS);
    CD(sin(p), 0x3CA1A62633145C07ull);
    CD(cos(-zero), P1);
    CD(cos(-inf), NANBITS);
    CD(cos(p), N1);
    CD(tan(-zero), N0);
    CD(tan(inf), NANBITS);
    CD(tan(p / 4), 0x3FEFFFFFFFFFFFFFull);
    CF(sinf(-zf), FN0);
    CF(sinf(inff), NANFBITS);
    CF(sinf(pf), 0xB3BBBD2Eu);
    CF(cosf(-zf), FP1);
    CF(cosf(pf), FN1);
    CF(tanf(-zf), FN0);
    CF(tanf(inff), NANFBITS);

    CD(asin(-zero), N0);
    CD(asin(one), PI2);
    CD(asin(-one), PI2 | N0);
    CD(asin(two), NANBITS);
    CD(acos(one), P0);
    CD(acos(-one), PIB);
    CD(acos(zero), PI2);
    CD(acos(two), NANBITS);
    CD(atan(-zero), N0);
    CD(atan(one), PI4);
    CD(atan(inf), PI2);
    CD(atan(-inf), PI2 | N0);
    CF(asinf(onef), FPI2);
    CF(asinf(twof), NANFBITS);
    // musl's acosf(-1), acosf(0), and atanf of an infinity return pio2_hi,
    // the float below pi/2, or twice it, 0x3FC90FDA and 0x40490FDA, 0.63
    // ulp below the true value: within the bound, but not the nearest.
    CF(acosf(-onef), 0x40490FDAu);
    CF(acosf(zf), 0x3FC90FDAu);
    CF(acosf(onef), FP0);
    CF(atanf(onef), FPI4);
    CF(atanf(-inff), 0xBFC90FDAu);

    // C17 F.10.1.4, in its order.
    CD(atan2(zero, -zero), PIB);
    CD(atan2(-zero, -zero), PIB | N0);
    CD(atan2(zero, zero), P0);
    CD(atan2(-zero, zero), N0);
    CD(atan2(zero, -one), PIB);
    CD(atan2(-zero, -one), PIB | N0);
    CD(atan2(zero, one), P0);
    CD(atan2(-zero, one), N0);
    CD(atan2(-one, zero), PI2 | N0);
    CD(atan2(one, -zero), PI2);
    CD(atan2(one, -inf), PIB);
    CD(atan2(-one, -inf), PIB | N0);
    CD(atan2(one, inf), P0);
    CD(atan2(-one, inf), N0);
    CD(atan2(inf, one), PI2);
    CD(atan2(-inf, one), PI2 | N0);
    CD(atan2(inf, -inf), PI34);
    CD(atan2(-inf, -inf), PI34 | N0);
    CD(atan2(inf, inf), PI4);
    CD(atan2(-inf, inf), PI4 | N0);
    CD(atan2(one, one), PI4);
    CD(atan2(nan_, one), NANBITS);
    CF(atan2f(-zf, -zf), FPI | FN0);
    CF(atan2f(zf, zf), FP0);
    CF(atan2f(-onef, zf), FPI2 | FN0);
    CF(atan2f(inff, -inff), FPI34);
    CF(atan2f(-inff, inff), FPI4 | FN0);
    CF(atan2f(onef, onef), FPI4);
}

static void explog(void)
{
    // C17 F.10.3.1 and F.10.3.7 and those of log10 and log2.
    CD(exp(-zero), P1);
    CD(exp(-inf), P0);
    CD(exp(inf), PINF);
    CD(exp(1000 * one), PINF);
    CD(exp(-1000 * one), P0);
    CD(exp(one), 0x4005BF0A8B145769ull);
    CD(log(one), P0);
    CD(log(-zero), NINF);
    CD(log(zero), NINF);
    CD(log(-one), NANBITS);
    CD(log(inf), PINF);
    CD(log(two), 0x3FE62E42FEFA39EFull);
    CD(log10(one), P0);
    CD(log10(zero), NINF);
    CD(log10(1000 * one), 0x4008000000000000ull); // 3
    CD(log10(-one), NANBITS);
    CD(log2(one), P0);
    CD(log2(8 * one), 0x4008000000000000ull);     // 3
    CD(log2(one / 1024), 0xC024000000000000ull);  // -10
    CD(log2(-zero), NINF);
    CD(log2(-inf), NANBITS);
    CF(expf(-zf), FP1);
    CF(expf(-inff), FP0);
    CF(expf(100 * onef), FPINF);
    CF(expf(onef), 0x402DF854u);
    CF(logf(onef), FP0);
    CF(logf(zf), FNINF);
    CF(logf(-onef), NANFBITS);
    CF(logf(twof), 0x3F317218u);
    CF(log10f(1000 * onef), 0x40400000u); // 3
    CF(log10f(-zf), FNINF);
    CF(log2f(8 * onef), 0x40400000u);     // 3
    CF(log2f(zf), FNINF);
}

static void powers(void)
{
    // C17 F.10.4.4, in its order.
    CD(pow(zero, -3 * one), PINF);
    CD(pow(-zero, -3 * one), NINF);
    CD(pow(-zero, -2 * one), PINF);
    CD(pow(zero, -0.5 * one), PINF);
    CD(pow(-zero, -inf), PINF);
    CD(pow(-zero, 3 * one), N0);
    CD(pow(zero, 3 * one), P0);
    CD(pow(-zero, 2 * one), P0);
    CD(pow(-zero, 0.5 * one), P0);
    CD(pow(-one, inf), P1);
    CD(pow(-one, -inf), P1);
    CD(pow(one, nan_), P1);
    CD(pow(nan_, -zero), P1);
    CD(pow(-2 * one, 0.5 * one), NANBITS);
    CD(pow(0.5 * one, -inf), PINF);
    CD(pow(2 * one, -inf), P0);
    CD(pow(0.5 * one, inf), P0);
    CD(pow(2 * one, inf), PINF);
    CD(pow(-inf, -3 * one), N0);
    CD(pow(-inf, -2 * one), P0);
    CD(pow(-inf, 3 * one), NINF);
    CD(pow(-inf, 2 * one), PINF);
    CD(pow(inf, -one), P0);
    CD(pow(inf, one), PINF);
    // Exact results, and overflow.
    CD(pow(2 * one, 10 * one), 0x4090000000000000ull);  // 1024
    CD(pow(-2 * one, 3 * one), 0xC020000000000000ull);  // -8
    CD(pow(2 * one, -one), 0x3FE0000000000000ull);      // 0.5
    CD(pow(4 * one, 0.5 * one), 0x4000000000000000ull); // 2
    CD(pow(2 * one, 0.5 * one), 0x3FF6A09E667F3BCDull); // √2
    CD(pow(2 * one, 1024 * one), PINF);
    CD(pow(nan_, one), NANBITS);
    CF(powf(-zf, -3 * onef), FNINF);
    CF(powf(onef, nanf_), FP1);
    CF(powf(nanf_, zf), FP1);
    CF(powf(-twof, 0.5f * onef), NANFBITS);
    CF(powf(-inff, 3 * onef), FNINF);
    CF(powf(twof, 10 * onef), 0x44800000u);       // 1024
    CF(powf(twof, 0.5f * onef), 0x3FB504F3u);     // √2
    CF(powf(twof, 128 * onef), FPINF);
}

static void parts(void)
{
    int e = 99;
    double ip = 99;
    float ipf = 99;
    CD(sqrt(4 * one), 0x4000000000000000ull);
    CD(sqrt(two), 0x3FF6A09E667F3BCDull);
    CD(sqrt(-zero), N0);
    CD(sqrt(-one), NANBITS);
    CD(sqrt(inf), PINF);
    CF(sqrtf(twof), 0x3FB504F3u);
    CF(sqrtf(-onef), NANFBITS);

    CD(fmod(5.5 * one, two), 0x3FF8000000000000ull);   // 1.5
    CD(fmod(-5.5 * one, two), 0xBFF8000000000000ull);  // -1.5
    CD(fmod(5.5 * one, -two), 0x3FF8000000000000ull);  // 1.5
    CD(fmod(-zero, one), N0);
    CD(fmod(one, zero), NANBITS);
    CD(fmod(inf, one), NANBITS);
    CD(fmod(one, inf), P1);
    CF(fmodf(-5.5f * onef, twof), 0xBFC00000u);       // -1.5
    CF(fmodf(onef, zf), NANFBITS);

    CD(frexp(8 * one, &e), 0x3FE0000000000000ull);    // 0.5
    CI(e, 4);
    CD(frexp(-3 * one, &e), 0xBFE8000000000000ull);   // -0.75
    CI(e, 2);
    CD(frexp(-zero, &e), N0);
    CI(e, 0);
    CD(frexp(D(1), &e), 0x3FE0000000000000ull);       // 2^-1074 = 0.5 * 2^-1073
    CI(e, -1073);
    CF(frexpf(F(1), &e), 0x3F000000u);                // 2^-149 = 0.5 * 2^-148
    CI(e, -148);
    CD(ldexp(one, 1023), 0x7FE0000000000000ull);
    CD(ldexp(one, 1024), PINF);
    CD(ldexp(one, -1074), 0x0000000000000001ull);
    // 2^-1075 is half the least subnormal, a tie, which rounds to the
    // even 0, and 3 * 2^-1075, a tie between 1 and 2 of them, to 2.
    CD(ldexp(one, -1075), P0);
    CD(ldexp(3 * one, -1075), 0x0000000000000002ull);
    CD(ldexp(-zero, 5), N0);
    CD(scalbn(D(1), 1074), P1);
    CF(ldexpf(onef, -149), 0x00000001u);
    CF(ldexpf(onef, 128), FPINF);
    CF(scalbnf(3 * onef, -150), 0x00000002u);

    CD(modf(3.75 * one, &ip), 0x3FE8000000000000ull); // 0.75
    CD(ip, 0x4008000000000000ull);                     // 3
    CD(modf(-3.75 * one, &ip), 0xBFE8000000000000ull);
    CD(ip, 0xC008000000000000ull);
    CD(modf(-inf, &ip), N0);
    CD(ip, NINF);
    CD(modf(nan_, &ip), NANBITS);
    CF(modff(-3.75f * onef, &ipf), 0xBF400000u);       // -0.75
    CF(ipf, 0xC0400000u);                              // -3
}

static void rounding(void)
{
    double h = 0.5 * one;
    CD(round(h), P1);
    CD(round(-h), N1);
    CD(round(2.5 * one), 0x4008000000000000ull);       // 3
    CD(round(-zero), N0);
    // The double below 0.5 rounds to 0, though it plus 0.5 rounds to 1.
    CD(round(D(0x3FDFFFFFFFFFFFFFull)), P0);
    CD(rint(2.5 * one), 0x4000000000000000ull);        // 2, the even one
    CD(rint(3.5 * one), 0x4010000000000000ull);        // 4
    CD(rint(-h), N0);
    CD(nearbyint(-2.5 * one), 0xC000000000000000ull);  // -2
    CD(floor(-h), N1);
    CD(floor(-zero), N0);
    CD(ceil(-h), N0);
    CD(trunc(-1.5 * one), N1);
    CD(fabs(-zero), P0);
    CD(copysign(one, -zero), N1);
    CF(roundf(-0.5f * onef), FN1);
    CF(roundf(F(0x3EFFFFFFu)), FP0);
    CF(rintf(2.5f * onef), 0x40000000u);
    CF(nearbyintf(-0.5f * onef), FN0);
    CF(floorf(-0.5f * onef), FN1);
    CF(ceilf(-0.5f * onef), FN0);
    CF(truncf(-1.5f * onef), FN1);
    CF(fabsf(-zf), FP0);
    CF(copysignf(onef, -zf), FN1);

    CD(fmin(nan_, one), P1);
    CD(fmin(one, nan_), P1);
    CD(fmax(nan_, nan_), NANBITS);
    CD(fmin(-zero, zero), N0);
    CD(fmax(-zero, zero), P0);
    CD(fmin(one, two), P1);
    CD(fmax(one, two), 0x4000000000000000ull);
    CF(fminf(nanf_, onef), FP1);
    CF(fmaxf(zf, -zf), FP0);
    CF(fmaxf(onef, twof), 0x40000000u);
}

static void classify(void)
{
    CI(isnan(nan_), 1);
    CI(isnan(inf), 0);
    CI(isnan(nanf_), 1);
    CI(isinf(-inf), 1);
    CI(isinf(DBL_MAX), 0);
    CI(isinf(-inff), 1);
    CI(isfinite(DBL_MAX), 1);
    CI(isfinite(inf), 0);
    CI(isfinite(nanf_), 0);
    CI(isnormal(DBL_MIN), 1);
    CI(isnormal(D(1)), 0);
    CI(isnormal(zero), 0);
    CI(isnormal(FLT_MIN), 1);
    CI(signbit(-zero), 1);
    CI(signbit(zero), 0);
    CI(signbit(-zf), 1);
    CI(fpclassify(nan_), FP_NAN);
    CI(fpclassify(-inf), FP_INFINITE);
    CI(fpclassify(-zero), FP_ZERO);
    CI(fpclassify(D(1)), FP_SUBNORMAL);
    CI(fpclassify(one), FP_NORMAL);
    CI(fpclassify(F(1)), FP_SUBNORMAL);
    CI(fpclassify(nanf_), FP_NAN);
    CD(HUGE_VAL, PINF);
    CF(HUGE_VALF, FPINF);
    CI(math_errhandling, 0);
}

// The functions that math.h maps to built-ins, called through pointers.
static double (*const dfn[])(double) = {sqrt, fabs, floor, ceil, trunc, rint, nearbyint};
static float (*const ffn[])(float) = {sqrtf, fabsf, floorf, ceilf, truncf, rintf, nearbyintf};

static void pointers(void)
{
    static const u64 want[] = {0x4004000000000000ull, 0x4004000000000000ull,
                               0xC008000000000000ull, 0xC000000000000000ull,
                               0xC000000000000000ull, 0xC000000000000000ull,
                               0xC000000000000000ull};
    static const unsigned wantf[] = {0x40200000u, 0x40200000u, 0xC0400000u, 0xC0000000u,
                                     0xC0000000u, 0xC0000000u, 0xC0000000u};
    // sqrt(6.25) = 2.5, then |-2.5|, and -2.5 rounded down, up, toward 0,
    // and to even.
    for (int i = 0; i < 7; i++) {
        double x = i == 0 ? 6.25 * one : -2.5 * one;
        float xf = i == 0 ? 6.25f * onef : -2.5f * onef;
        checkd("pointer", dfn[i](x), want[i]);
        checkf("pointer f", ffn[i](xf), wantf[i]);
    }
    double (*cs)(double, double) = copysign;
    CD(cs(two, -one), 0xC000000000000000ull);
}

int main(void)
{
    trig();
    explog();
    powers();
    parts();
    rounding();
    classify();
    pointers();
    printf("math: %d checks, %d failed\n", checks, fails);
    return fails;
}
