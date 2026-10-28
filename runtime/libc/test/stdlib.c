// stdlib.h: integers, number parsing, and the allocator. main returns 0.
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Prints the next three values of rand, one call per statement: C does not
// say in which order the arguments of a call are evaluated.
static void three(void)
{
    int a = rand();
    int b = rand();
    int c = rand();
    printf("%d %d %d\n", a, b, c);
}

int main(void)
{
    printf("%d %d %d\n", errno, ERANGE, EDOM);   // errno is 0 at start
    printf("%d %ld %lld\n", abs(-5), labs(-6L), llabs(-7LL));
    printf("%d %d\n", atoi("  -123abc"), atoi("x"));
    char *end;
    long v = strtol("0x1F rest", &end, 0);
    printf("%ld [%s]\n", v, end);
    printf("%ld %ld\n", strtol("0777", NULL, 0), strtol("z", NULL, 36));
    printf("%ld %ld\n", strtol("99999999999", NULL, 10), strtol("-99999999999", NULL, 10));
    printf("%lu\n", strtoul("-1", NULL, 10));
    v = strtol("abc", &end, 10);
    printf("%ld %d\n", v, *end == 'a');

    // An overflow sets errno to ERANGE, and a call without one leaves it
    // alone.
    errno = 0;
    v = strtol("2147483647", NULL, 10);
    printf("%ld %d\n", v, errno);
    v = strtol("-2147483648", NULL, 10);
    printf("%ld %d\n", v, errno);
    v = strtol("2147483648", NULL, 10);
    printf("%ld %d\n", v, errno);
    v = strtol("7", NULL, 10);
    printf("%ld %d\n", v, errno);
    errno = 0;
    v = strtol("-2147483649", NULL, 10);
    printf("%ld %d\n", v, errno);
    errno = 0;
    unsigned long u = strtoul("4294967295", NULL, 10);
    printf("%lu %d\n", u, errno);
    u = strtoul("-4294967295", NULL, 10);
    printf("%lu %d\n", u, errno);
    u = strtoul("4294967296", NULL, 10);
    printf("%lu %d\n", u, errno);
    errno = 0;
    u = strtoul("-4294967296", NULL, 0);
    printf("%lu %d\n", u, errno);
    errno = 0;
    u = strtoul("0x100000000", NULL, 0);
    printf("%lu %d\n", u, errno);

    // A base other than 0 and 2 to 36 reads nothing and sets EINVAL.
    static const int bad[] = {-1, 1, 37};
    for (int i = 0; i < 3; i++) {
        const char *s = " 12";
        errno = 0;
        v = strtol(s, &end, bad[i]);
        printf("%ld %d %d\n", v, end == s, errno);
    }
    errno = 0;
    u = strtoul("12", NULL, 99);
    printf("%lu %d %d\n", u, errno, EINVAL);

    // The generator starts as after srand(1), and srand restarts it.
    three();
    srand(42);
    three();
    srand(1);
    printf("%d %d\n", rand(), RAND_MAX);

    // Blocks are the size asked for plus an 8-byte header, rounded up to 8.
    char *p = malloc(10), *q = malloc(10), *r = malloc(100);
    printf("%d %d %d\n", (int)(q - p), (int)(r - q), (int)((unsigned long)p % 8));
    strcpy(p, "first");
    free(q);
    char *s = malloc(16);       // fits exactly in q's block
    printf("%d\n", s == q);
    free(s);
    free(p);                    // merged with s's block, 48 bytes
    char *t = malloc(40);
    printf("%d [%s]\n", t == p, t);
    int *z = calloc(4, sizeof(int));
    printf("%d\n", z[0] + z[1] + z[2] + z[3]);
    strcpy(t, "grow");
    t = realloc(t, 200);
    printf("[%s]\n", t);
    // The memory is one page, and nicewasm lets it grow no further.
    printf("%d\n", malloc(100000) == NULL);
    return 0;
}
