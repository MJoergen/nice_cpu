// The corners of strtol, strtoul, atoi, atol, and abs that test/stdlib.c
// leaves out: white space and signs, the limits of long and unsigned
// long, bases 2, 8, 16, and 36, prefixes without digits, and where *end
// points when nothing is read. main returns 0.
#include <stdio.h>
#include <stdlib.h>

static void show(const char *s, int base)
{
    char *end;
    long v = strtol(s, &end, base);
    printf("%ld %d\n", v, (int)(end - s));
}

int main(void)
{
    printf("%ld %ld %ld\n", strtol(" \t\n+42", NULL, 10), strtol("-0", NULL, 10),
           strtol("\v\f\r-17x", NULL, 10));
    printf("%ld %ld %ld %ld\n", strtol("-2147483648", NULL, 10), strtol("2147483648", NULL, 10),
           strtol("-2147483649", NULL, 10), strtol("2147483647", NULL, 10));
    printf("%lu %lu %lu %lu\n", strtoul("4294967295", NULL, 10), strtoul("4294967296", NULL, 10),
           strtoul("-4294967296", NULL, 0), strtoul("-4294967294", NULL, 10));
    printf("%ld %ld %ld %ld %ld\n", strtol("101", NULL, 2), strtol("777", NULL, 8),
           strtol("zZ", NULL, 36), strtol("0X1aB", NULL, 16), strtol("-0x10", NULL, 0));
    show("0x", 16);             // the 0 is the number; x stays
    show("0xg", 0);
    show("08", 0);              // octal: 0, and 8 stays
    show("12", 2);
    show("  -", 10);            // no digits: end = s
    show("+ 1", 10);
    printf("%d %d %d %d %ld\n", atoi("  +7"), atoi("-0x10"), atoi("2147483647"), atoi(""),
           atol("-123456789"));
    printf("%d %ld %lld %lld\n", abs(-2147483647), labs(0L), llabs(-9223372036854775807LL),
           llabs(5));
    return 0;
}
