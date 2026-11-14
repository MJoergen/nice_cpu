// test/printf.c through the i family, printf without the float
// conversions: the same output for the integer conversions, and a float
// conversion printed as it stands, with the arguments after it in place.
// fiprintf and viprintf print too. main returns what its last iprintf
// returns, the 13 bytes of "   ab|-1   |\n".
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>

// Through viprintf.
static int vi(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = viprintf(fmt, ap);
    va_end(ap);
    return n;
}

int main(void)
{
    iprintf("[%d] [%i] [%u]\n", INT_MIN, INT_MAX, UINT_MAX);
    iprintf("[%lld] [%lld] [%llu]\n", LLONG_MIN, LLONG_MAX, ULLONG_MAX);
    // 0xFFFFFFFF is 2 + 30 bits, 37777777777 in octal; 2^63 = 8^21.
    iprintf("[%x] [%X] [%o] [%#X]\n", 0xDEADBEEFu, 0xDEADBEEFu, 0xFFFFFFFFu, 0xABCu);
    iprintf("[%llx] [%llo]\n", 1ULL << 63, 1ULL << 63);
    iprintf("[%s] [%5s] [%-3s|] [%.0s]\n", "", "", "", "abc");
    iprintf("[%c%c%c] [%-3c|] [%%]\n", 'a', 'b', 'c', 'x');
    // A negative width from * means -, and a negative precision none.
    iprintf("[%*d] [%-*d] [%.*d] [%.*s]\n", -4, 7, 3, 8, -1, 9, -1, "abc");
    iprintf("[%p] [%10p] [%-10p|]\n", (void *)0x1234, (void *)0xABC, (void *)0);
    iprintf("[%+d] [% d] [%+d] [%+.0d] [% 05d]\n", 0, 0, -1, 0, 42);
    iprintf("[%#o] [%#.0o] [%#x] [%#5x] [%#05x] [%-#6x|]\n", 0, 0, 0, 1, 1, 1);
    // (signed char)128 = -128, (unsigned char)257 = 1, (short)32768 =
    // -32768, (unsigned short)65541 = 5, and (unsigned char)-1 = 0xff.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat"
    iprintf("[%hhd] [%hhu] [%hd] [%hu] [%hhx]\n", 128, 257, 32768, 65541, -1);
    iprintf("[%jd] [%zu] [%td] [%ld] [%lu]\n", (intmax_t)-1, (size_t)7, (ptrdiff_t)-3, LONG_MIN,
           ULONG_MAX);
    // %y and %Lf, a long double, are printed as they stand. The last %
    // has \n as its conversion.
    iprintf("%y|%Lf|%\n");
#pragma clang diagnostic pop

    // The float conversions take their double and are printed as they
    // stand, so that the arguments after them stay in place.
    iprintf("[%f] [%-8.3e] [%G] [%#a] [%d] [%s]\n", 1.5, -2.0, 1e300, 0.0, 42, "ok");
    fiprintf(stdout, "[%d] [%.2f] [%x]\n", -7, 2.25, 255u);
    vi("[%u] [%g] [%c]\n", 3u, 0.5, 'z');

    // sniprintf writes at most size - 1 bytes and a 0, and returns the
    // length of the whole output.
    char buf[8];
    int n = sniprintf(buf, sizeof buf, "%d", 1234567);
    iprintf("%d [%s]\n", n, buf);
    n = sniprintf(buf, sizeof buf, "%d", 12345678);
    iprintf("%d [%s]\n", n, buf);
    buf[0] = 'Z';
    n = sniprintf(buf, 1, "abc");
    iprintf("%d [%s]\n", n, buf);
    buf[0] = 'Z';
    buf[1] = '\0';
    n = sniprintf(buf, 0, "abc");
    iprintf("%d [%s]\n", n, buf);
    n = siprintf(buf, "%s", "");
    iprintf("%d [%s]\n", n, buf);
    return iprintf("%5s|%-5d|\n", "ab", -1);
}
