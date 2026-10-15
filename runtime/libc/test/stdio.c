// putchar, puts, and the printf family. main returns what its last printf
// returns, the 7 bytes of "0x1234\n".
#include <stdio.h>

int main(void)
{
    putchar('A');
    putchar('\n');
    puts("Hello, NICE!");
    printf("%d %i %u\n", 42, -42, 3000000000u);
    printf("%x %X %o %#x %#o %#x\n", 255, 255, 8, 255, 8, 0);
    printf("[%5d] [%-5d] [%05d] [%+d] [% d]\n", 42, 42, -42, 42, 42);
    printf("[%.3d] [%8.3d] [%.0d] [%08.3d]\n", 7, -7, 0, 5);
    printf("[%s] [%.3s] [%6s] [%-6s] [%c] [%3c] [%s]\n", "abc", "abcdef", "abc", "abc", 'z',
           'y', (char *)0);
    printf("%lld %llu %llx\n", -1234567890123LL, 18446744073709551615ULL,
           0x123456789abcdefULL);
    printf("%hhd %hu %ld %zu\n", 300, 70000, -5L, sizeof(long long));
    printf("[%*d] [%-*d] [%.*s]\n", 4, 1, 4, 2, 2, "xyz");
    printf("100%% %f %d\n", 1.5, 9);

    char buf[16];
    int n = snprintf(buf, sizeof buf, "%s-%d", "overflowing text", 12345);
    printf("%d [%s]\n", n, buf);
    n = sprintf(buf, "%05x", 0xbeef);
    printf("%d [%s]\n", n, buf);
    // + and space are for signed conversions, so they are ignored here, as
    // glibc ignores them; C leaves the combination undefined, hence the
    // pragma. %p of a null pointer is 0x0.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat"
    printf("%+u % x %p\n", 5u, 255u, (void *)0);
#pragma clang diagnostic pop
    return printf("%p\n", (void *)0x1234);
}
