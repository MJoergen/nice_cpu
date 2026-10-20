// The corners of sscanf that test/scanf.c leaves out: %n with no input
// and around white space, %c up to the end of the input, the return value
// at the end of the input before and after the first conversion, %*d
// with %n, the unsigned conversions, widths on %s %c %d and %[, the
// limits of hh and ll, %p, and %% after a number. main returns 0.
#include <stdio.h>

int main(void)
{
    int a = -1, b = -1, c = -1, k = -1, n;
    n = sscanf("", "%n", &k);
    printf("%d %d\n", n, k);
    n = sscanf("  42", "%n%d%n", &a, &b, &c);
    printf("%d %d %d %d\n", n, a, b, c);

    char c1 = '.', c2 = '.', c3 = '.', c4 = '.';
    n = sscanf("abc", "%c%c%c%c", &c1, &c2, &c3, &c4);
    printf("%d %c%c%c%c\n", n, c1, c2, c3, c4);

    char s1[8] = {0}, s2[8] = {0}, s3[8] = {0};
    printf("%d %d %d %d %d\n", sscanf("", "x"), sscanf("y", "x"), sscanf(" ", " "),
           sscanf("", "%[a]", s1), sscanf("b", "%[a]", s1));

    n = sscanf("12 34", "%d%*d%n", &a, &k);
    printf("%d %d %d\n", n, a, k);
    unsigned x1, x2, u, o;
    n = sscanf("0x1F 1F -17 777", "%x %X %u %o", &x1, &x2, &u, &o);
    printf("%d: %u %u %u %u\n", n, x1, x2, u, o);

    n = sscanf("abcdef", "%3s%2c%s", s1, s2, s3);
    printf("%d [%s] [%s] [%s]\n", n, s1, s2, s3);
    n = sscanf("a,b", "%[^,],%s", s1, s3);
    printf("%d [%s] [%s]\n", n, s1, s3);
    n = sscanf("abcz", "%2[a-z]%s", s1, s3);
    printf("%d [%s] [%s]\n", n, s1, s3);
    n = sscanf("123456", "%2d%2d%2d", &a, &b, &c);
    printf("%d: %d %d %d\n", n, a, b, c);

    signed char hh;
    long long ll;
    unsigned long long ull;
    n = sscanf("200 -9223372036854775808 18446744073709551615", "%hhd %lld %llu", &hh, &ll, &ull);
    printf("%d: %d %lld %llu\n", n, hh, ll, ull);
    void *p;
    n = sscanf("0x1234", "%p", &p);
    printf("%d %p\n", n, p);
    n = sscanf("5%", "%d%%", &a);
    printf("%d %d\n", n, a);
    n = sscanf("a b", "%*c %c", &c1);
    printf("%d %c\n", n, c1);
    return 0;
}
