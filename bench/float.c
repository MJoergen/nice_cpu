// A benchmark of floating-point code that reaches NICE through wasm
// (WASM.md), and so of the float library (runtime/float.zig), which does
// the arithmetic in software.
//
// Five phases, each a small kernel with a known result. Each phase is timed
// with the performance counters of DEVICES.md §3, and main prints one line
// per phase, as bench.c does: the instructions, the cycles, the result,
// and whether it is the expected one. A result is the bits of a float, or
// a hash of them, which compare exactly. The expected values come from
// floatexpected.py, which computes each phase in Python from the same
// sizes, rounding each f32 operation to f32. The native build, "make
// native-float", runs the same C on the host as a second check.
//
// The phases, and the routines of the float library each one uses most:
//
//   convert    xorshift32 values go to f32 and f64 and back, and fill the
//              arrays of the next phases. Conversions between integers
//              and floats, and between f32 and f64.
//   dot32      An f32 dot product of the f32 array with itself reversed.
//              f32 multiply and add.
//   dot64      The same in f64. f64 multiply and add.
//   mandel     The iterations of the Mandelbrot set on a small f32 grid.
//              f32 multiply, add, subtract, and compare.
//   norm       Normalizes f32 vectors of three components. f32 square
//              root and divide.
//
// The sizes are the defines below. After changing one, run
// "python3 floatexpected.py" and put its values in the EXPECT defines.

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifdef __wasm__
#include <nice.h>
#else
// The native build has no counters. It checks the results only.
static unsigned long long nice_cycles(void) { return 0; }
static unsigned long long nice_instructions(void) { return 0; }
#endif

#define CONV_COUNT 128  // the values of convert, and the length of the arrays
#define MANDEL_W 12     // the grid of mandel, MANDEL_W by MANDEL_H points
#define MANDEL_H 8
#define MANDEL_ITER 16  // the most iterations at a point
#define NORM_COUNT 40   // the vectors of norm, from the first 3 * NORM_COUNT elements

// From floatexpected.py, for the sizes above.
#define EXPECT_CONVERT 0x97943DF8u
#define EXPECT_DOT32 0xC0C723F7u
#define EXPECT_DOT64 0xBA3319EAu
#define EXPECT_MANDEL 0x4C25FAF9u
#define EXPECT_NORM 0x7703CD00u

#define NOINLINE __attribute__((noinline))

#define FNV_BASIS 0x811C9DC5u
#define FNV_PRIME 16777619u

static float xs32[CONV_COUNT];
static double xs64[CONV_COUNT];

static uint32_t fnv(uint32_t h, uint32_t x)
{
    return (h ^ x) * FNV_PRIME;
}

static uint32_t bits32(float f)
{
    uint32_t u;
    memcpy(&u, &f, sizeof u);
    return u;
}

// The two words of an f64, xored.
static uint32_t bits64(double d)
{
    uint64_t u;
    memcpy(&u, &d, sizeof u);
    return (uint32_t)u ^ (uint32_t)(u >> 32);
}

// convert: xorshift32 makes CONV_COUNT values x, read as signed. The seed
// is volatile so that clang cannot compute the phases at compile time.
// For each x, the phase hashes (int32_t)(f * 0.75f) and (int32_t)(d / 3.0),
// with f = (float)x and d = (double)x, then the bits of (float)(d / 3.0)
// and of (double)f. It keeps f / 2^31 in xs32 and d / 2^31 in xs64, which
// lie in [-1, 1].

static volatile uint32_t seed = 0x9E3779B9u;

NOINLINE static uint32_t phase_convert(void)
{
    uint32_t s = seed;
    uint32_t h = FNV_BASIS;
    for (int i = 0; i < CONV_COUNT; i++) {
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        int32_t x = (int32_t)s;
        float f = (float)x;
        double d = (double)x;
        double third = d / 3.0;
        h = fnv(h, (uint32_t)(int32_t)(f * 0.75f));
        h = fnv(h, (uint32_t)(int32_t)third);
        h = fnv(h, bits32((float)third));
        h = fnv(h, bits64((double)f));
        xs32[i] = f * 0x1p-31f;
        xs64[i] = d * 0x1p-31;
    }
    return h;
}

// dot32 and dot64: the sum of xs[i] * xs[CONV_COUNT - 1 - i], added in
// order from i = 0. The result is the bits of the sum.

NOINLINE static uint32_t phase_dot32(void)
{
    float sum = 0.0f;
    for (int i = 0; i < CONV_COUNT; i++)
        sum += xs32[i] * xs32[CONV_COUNT - 1 - i];
    return bits32(sum);
}

NOINLINE static uint32_t phase_dot64(void)
{
    double sum = 0.0;
    for (int i = 0; i < CONV_COUNT; i++)
        sum += xs64[i] * xs64[CONV_COUNT - 1 - i];
    return bits64(sum);
}

// mandel: the point (cr, ci) of column ix and row iy is
// cr = -2 + (2.5 * ix) / MANDEL_W and ci = -1.25 + (2.5 * iy) / MANDEL_H,
// in f32. z starts at 0 and takes at most MANDEL_ITER steps of
// z = z * z + c, stopping before the step at which |z|^2 > 4. The result
// is the number of steps taken at all the points, hashed point by point.

NOINLINE static uint32_t phase_mandel(void)
{
    uint32_t h = FNV_BASIS;
    for (int iy = 0; iy < MANDEL_H; iy++) {
        float ci = -1.25f + (2.5f * (float)iy) / (float)MANDEL_H;
        for (int ix = 0; ix < MANDEL_W; ix++) {
            float cr = -2.0f + (2.5f * (float)ix) / (float)MANDEL_W;
            float zr = 0.0f, zi = 0.0f;
            int n = 0;
            while (n < MANDEL_ITER) {
                float zr2 = zr * zr;
                float zi2 = zi * zi;
                if (zr2 + zi2 > 4.0f)
                    break;
                zi = 2.0f * zr * zi + ci;
                zr = zr2 - zi2 + cr;
                n++;
            }
            h = fnv(h, (uint32_t)n);
        }
    }
    return h;
}

// norm: vector j is (x, y, z) = xs32[3j], xs32[3j + 1], xs32[3j + 2].
// Its length is r = sqrtf(x * x + y * y + z * z), with the sum taken from
// the left, and each component is divided by r. The result hashes the bits
// of the three components of each normalized vector.

NOINLINE static uint32_t phase_norm(void)
{
    uint32_t h = FNV_BASIS;
    for (int j = 0; j < NORM_COUNT; j++) {
        float x = xs32[3 * j], y = xs32[3 * j + 1], z = xs32[3 * j + 2];
        float r = __builtin_sqrtf(x * x + y * y + z * z);
        h = fnv(h, bits32(x / r));
        h = fnv(h, bits32(y / r));
        h = fnv(h, bits32(z / r));
    }
    return h;
}

// Timing, as in bench.c. The instruction counts leave out the reads of the
// counters, and the cycle counts include them.

static unsigned long long start_cycles, start_instructions;
static unsigned long long total_cycles, total_instructions;
static int failures;

static void begin(void)
{
    start_cycles = nice_cycles();
    start_instructions = nice_instructions();
}

static void end(const char *name, uint32_t result, uint32_t expected)
{
    unsigned long long instructions = nice_instructions() - start_instructions;
    unsigned long long cycles = nice_cycles() - start_cycles;
    total_instructions += instructions;
    total_cycles += cycles;
    if (result != expected)
        failures++;
    printf("%-9s %12llu %12llu  %08x  %s\n", name, instructions, cycles, result,
           result == expected ? "ok" : "FAIL");
}

#define RUN(name, phase, expected)        \
    do {                                  \
        begin();                          \
        uint32_t result = phase();        \
        end(name, result, expected);      \
    } while (0)

// Returns the number of phases whose result is wrong.
int main(void)
{
    printf("phase      instructions       cycles  result\n");
    RUN("convert", phase_convert, EXPECT_CONVERT);
    RUN("dot32", phase_dot32, EXPECT_DOT32);
    RUN("dot64", phase_dot64, EXPECT_DOT64);
    RUN("mandel", phase_mandel, EXPECT_MANDEL);
    RUN("norm", phase_norm, EXPECT_NORM);
    printf("%-9s %12llu %12llu\n", "total", total_instructions, total_cycles);
    return failures;
}
