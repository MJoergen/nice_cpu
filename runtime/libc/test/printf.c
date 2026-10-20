// The corners of printf and snprintf that test/stdio.c leaves out: the
// limits of each type, empty strings, a negative width or precision from
// *, %p with a width, + and space with 0, the alternate forms of 0, the
// length modifiers that truncate, conversions that are printed as they
// stand, and snprintf at its buffer's size. main returns what its last
// printf returns, the 13 bytes of "   ab|-1   |\n".
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

int main(void)
{
    printf("[%d] [%i] [%u]\n", INT_MIN, INT_MAX, UINT_MAX);
    printf("[%lld] [%lld] [%llu]\n", LLONG_MIN, LLONG_MAX, ULLONG_MAX);
    // 0xFFFFFFFF is 2 + 30 bits, 37777777777 in octal; 2^63 = 8^21.
    printf("[%x] [%X] [%o] [%#X]\n", 0xDEADBEEFu, 0xDEADBEEFu, 0xFFFFFFFFu, 0xABCu);
    printf("[%llx] [%llo]\n", 1ULL << 63, 1ULL << 63);
    printf("[%s] [%5s] [%-3s|] [%.0s]\n", "", "", "", "abc");
    printf("[%c%c%c] [%-3c|] [%%]\n", 'a', 'b', 'c', 'x');
    // A negative width from * means -, and a negative precision none.
    printf("[%*d] [%-*d] [%.*d] [%.*s]\n", -4, 7, 3, 8, -1, 9, -1, "abc");
    printf("[%p] [%10p] [%-10p|]\n", (void *)0x1234, (void *)0xABC, (void *)0);
    printf("[%+d] [% d] [%+d] [%+.0d] [% 05d]\n", 0, 0, -1, 0, 42);
    printf("[%#o] [%#.0o] [%#x] [%#5x] [%#05x] [%-#6x|]\n", 0, 0, 0, 1, 1, 1);
    // (signed char)128 = -128, (unsigned char)257 = 1, (short)32768 =
    // -32768, (unsigned short)65541 = 5, and (unsigned char)-1 = 0xff.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat"
    printf("[%hhd] [%hhu] [%hd] [%hu] [%hhx]\n", 128, 257, 32768, 65541, -1);
    printf("[%jd] [%zu] [%td] [%ld] [%lu]\n", (intmax_t)-1, (size_t)7, (ptrdiff_t)-3, LONG_MIN,
           ULONG_MAX);
    // The float conversions take their argument and are printed as they
    // stand, as is %y. The last % has \n as its conversion.
    printf("%f|%e|%g|%y|%\n", 1.0, 2.0, 3.0);
#pragma clang diagnostic pop

    // snprintf writes at most size - 1 bytes and a 0, and returns the
    // length of the whole output.
    char buf[8];
    int n = snprintf(buf, sizeof buf, "%d", 1234567);
    printf("%d [%s]\n", n, buf);
    n = snprintf(buf, sizeof buf, "%d", 12345678);
    printf("%d [%s]\n", n, buf);
    buf[0] = 'Z';
    n = snprintf(buf, 1, "abc");
    printf("%d [%s]\n", n, buf);
    buf[0] = 'Z';
    buf[1] = '\0';
    n = snprintf(buf, 0, "abc");
    printf("%d [%s]\n", n, buf);
    n = sprintf(buf, "%s", "");
    printf("%d [%s]\n", n, buf);
    return printf("%5s|%-5d|\n", "ab", -1);
}
