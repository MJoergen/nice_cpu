/* The steps of a call of each math function on the emulator, which
   runtime/README.md quotes (make mathsteps). For each function a loop of
   N calls, which reads each argument from a volatile array of the
   function's own type and stores the result in a volatile variable, runs
   between two reads of nice_instructions. The steps of two such reads with
   nothing between them are taken off, and the rest is divided by N and
   rounded. The arguments are spread evenly over the range each function is
   most used in. fmin and fmax look at the signs first, so they are
   measured with two arguments of one sign, and of different signs. */
#include <math.h>
#include <nice.h>
#include <stdio.h>

#define N 32

static volatile double a[N], b[N], rd;
static volatile float af[N], bf[N], rf;
static unsigned long long empty;

/* The arguments: a from lo to hi, and b from lo2 to hi2. */
static void fill(double lo, double hi, double lo2, double hi2) {
    for (int i = 0; i < N; i++) {
        a[i] = lo + (hi - lo) * i / (N - 1);
        b[i] = lo2 + (hi2 - lo2) * i / (N - 1);
        af[i] = (float)a[i];
        bf[i] = (float)b[i];
    }
}

static unsigned per_call(unsigned long long steps) {
    return (unsigned)((steps - empty + N / 2) / N);
}

#define ONE(name, fd, ff, lo, hi)                                    \
    do {                                                             \
        unsigned long long t, d, f;                                  \
        fill(lo, hi, 0, 0);                                          \
        t = nice_instructions();                                     \
        for (int i = 0; i < N; i++) rd = fd(a[i]);                   \
        d = nice_instructions() - t;                                 \
        t = nice_instructions();                                     \
        for (int i = 0; i < N; i++) rf = ff(af[i]);                  \
        f = nice_instructions() - t;                                 \
        printf("%-24s %3u %3u\n", name, per_call(d), per_call(f));   \
    } while (0)

#define TWO(name, fd, ff, lo, hi, lo2, hi2)                          \
    do {                                                             \
        unsigned long long t, d, f;                                  \
        fill(lo, hi, lo2, hi2);                                      \
        t = nice_instructions();                                     \
        for (int i = 0; i < N; i++) rd = fd(a[i], b[i]);             \
        d = nice_instructions() - t;                                 \
        t = nice_instructions();                                     \
        for (int i = 0; i < N; i++) rf = ff(af[i], bf[i]);           \
        f = nice_instructions() - t;                                 \
        printf("%-24s %3u %3u\n", name, per_call(d), per_call(f));   \
    } while (0)

int main(void) {
    unsigned long long t = nice_instructions();
    empty = nice_instructions() - t;
    printf("%-24s double float\n", "steps of a call");
    ONE("sin", sin, sinf, -10, 10);
    ONE("cos", cos, cosf, -10, 10);
    ONE("tan", tan, tanf, -10, 10);
    ONE("asin", asin, asinf, -1, 1);
    ONE("acos", acos, acosf, -1, 1);
    ONE("atan", atan, atanf, -10, 10);
    ONE("exp", exp, expf, -10, 10);
    ONE("log", log, logf, 0.1, 100);
    ONE("log10", log10, log10f, 0.1, 100);
    ONE("log2", log2, log2f, 0.1, 100);
    ONE("exp2", exp2, exp2f, -10, 10);
    TWO("atan2", atan2, atan2f, -10, 10, 10, -10);
    TWO("fmod", fmod, fmodf, -100, 100, 1, 10);
    TWO("pow", pow, powf, 0.1, 10, -5, 5);
    TWO("hypot", hypot, hypotf, -10, 10, 10, -10);
    ONE("sqrt", sqrt, sqrtf, 0, 100);
    ONE("floor", floor, floorf, -100, 100);
    ONE("round", round, roundf, -100, 100);
    TWO("fmin, one sign", fmin, fminf, 1, 10, 10, 1);
    TWO("fmin, different signs", fmin, fminf, 1, 10, -10, -1);
    TWO("fmax, one sign", fmax, fmaxf, 1, 10, 10, 1);
    TWO("fmax, different signs", fmax, fmaxf, 1, 10, -10, -1);
    ONE("fabs", fabs, fabsf, -10, 10);
    return 0;
}
