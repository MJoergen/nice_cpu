// The i family of scanf: the integer and string cases of test/scanf.c and
// test/sscanf.c through iscanf, fiscanf, viscanf, siscanf, and vsiscanf,
// with the same output, and then the float conversions, which end the
// scan. It prints with iprintf, so the program names no label of the
// float library. The console input is test/iscanf.input, a copy of
// test/scanf.input:
//
//   Hello
//     42 -17 0x1f 077 abc
//   12345,word with spaces;rest
//   x=7 y=oops
//
// main returns 0.
#include <stdarg.h>
#include <stdio.h>

static int via_viscanf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = viscanf(fmt, ap);
    va_end(ap);
    return n;
}

static int via_vsiscanf(const char *s, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vsiscanf(s, fmt, ap);
    va_end(ap);
    return n;
}

// test/scanf.c.
static void console(void)
{
    char line[16];
    int c, k = 0;
    while ((c = getchar()) != '\n')
        line[k++] = (char)c;
    line[k] = '\0';
    iprintf("[%s] %d\n", line, k);

    int a, b;
    unsigned x, o;
    char w[8];
    int n = iscanf("%d %d %x %o %7s", &a, &b, &x, &o, w);
    iprintf("%d: %d %d %u %u [%s]\n", n, a, b, x, o, w);

    char s[32], ch;
    n = fiscanf(stdin, "%3d%d,%[^;]%c", &a, &b, s, &ch);
    iprintf("%d: %d %d [%s] %c\n", n, a, b, s, ch);

    int pos;
    n = via_viscanf("%*s%n", &pos);
    iprintf("%d %d\n", n, pos);

    n = iscanf(" x=%d y=%d", &a, &b);
    iprintf("%d %d\n", n, a);
    k = 0;
    while (getchar() != EOF)
        k++;
    n = iscanf("%d", &a);
    iprintf("%d %d\n", k, n);

    signed char hh;
    short h;
    long long ll;
    n = siscanf("-5 70000 123456789012 ff", "%hhd %hd %lld %x", &hh, &h, &ll, &x);
    iprintf("%d: %d %d %lld %u\n", n, hh, h, ll, x);
    iprintf("%d %d %d\n", siscanf("abc", "%d", &a), siscanf("", "%d", &a), siscanf("  ", "%d", &a));
    n = siscanf("%42", "%%%d", &a);
    iprintf("%d %d\n", n, a);
    n = siscanf("12abcd", "%d%3c", &a, w);
    iprintf("%d %d %.3s\n", n, a, w);
    int i;
    n = siscanf("-0x10 010 10", "%i %i %i", &a, &b, &i);
    iprintf("%d: %d %d %d\n", n, a, b, i);
    char s2[8];
    n = via_vsiscanf("abc-def]x", "%[a-c-]%[]def]", s, s2);
    iprintf("%d [%s] [%s]\n", n, s, s2);
}

// test/sscanf.c.
static void strings(void)
{
    int a = -1, b = -1, c = -1, k = -1, n;
    n = siscanf("", "%n", &k);
    iprintf("%d %d\n", n, k);
    n = siscanf("  42", "%n%d%n", &a, &b, &c);
    iprintf("%d %d %d %d\n", n, a, b, c);

    char c1 = '.', c2 = '.', c3 = '.', c4 = '.';
    n = siscanf("abc", "%c%c%c%c", &c1, &c2, &c3, &c4);
    iprintf("%d %c%c%c%c\n", n, c1, c2, c3, c4);

    char s1[8] = {0}, s2[8] = {0}, s3[8] = {0};
    iprintf("%d %d %d %d %d\n", siscanf("", "x"), siscanf("y", "x"), siscanf(" ", " "),
            siscanf("", "%[a]", s1), siscanf("b", "%[a]", s1));

    n = siscanf("12 34", "%d%*d%n", &a, &k);
    iprintf("%d %d %d\n", n, a, k);
    unsigned x1, x2, u, o;
    n = siscanf("0x1F 1F -17 777", "%x %X %u %o", &x1, &x2, &u, &o);
    iprintf("%d: %u %u %u %u\n", n, x1, x2, u, o);

    n = siscanf("abcdef", "%3s%2c%s", s1, s2, s3);
    iprintf("%d [%s] [%s] [%s]\n", n, s1, s2, s3);
    n = siscanf("a,b", "%[^,],%s", s1, s3);
    iprintf("%d [%s] [%s]\n", n, s1, s3);
    n = siscanf("abcz", "%2[a-z]%s", s1, s3);
    iprintf("%d [%s] [%s]\n", n, s1, s3);
    n = siscanf("123456", "%2d%2d%2d", &a, &b, &c);
    iprintf("%d: %d %d %d\n", n, a, b, c);

    signed char hh;
    long long ll;
    unsigned long long ull;
    n = siscanf("200 -9223372036854775808 18446744073709551615", "%hhd %lld %llu", &hh, &ll, &ull);
    iprintf("%d: %d %lld %llu\n", n, hh, ll, ull);
    void *p;
    n = siscanf("0x1234", "%p", &p);
    iprintf("%d %p\n", n, p);
    n = siscanf("5%", "%d%%", &a);
    iprintf("%d %d\n", n, a);
    n = siscanf("a b", "%*c %c", &c1);
    iprintf("%d %c\n", n, c1);
}

// A float conversion is a matching failure: the scan ends there, and the
// call returns the conversions before it, also with *. The %d after it
// stores nothing, and the destinations keep their values.
static void floats(void)
{
    int a = -1, b = -1, n;
    float f;
    n = siscanf("1 2.5 3", "%d %f %d", &a, &f, &b);
    iprintf("%d %d %d\n", n, a, b);
    a = -1;
    n = siscanf("4 2.5 6", "%d %*f %d", &a, &b);
    iprintf("%d %d %d\n", n, a, b);
    n = siscanf("2.5", "%lf", (double *)0);
    iprintf("%d\n", n);
    n = siscanf("", "%f", &f);
    iprintf("%d\n", n);
}

int main(void)
{
    console();
    strings();
    floats();
    return 0;
}
