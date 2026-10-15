// stdlib.h: integers, number parsing, and the allocator. main returns 0.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void)
{
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
