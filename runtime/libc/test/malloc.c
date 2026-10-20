// The corners of the allocator that test/stdlib.c leaves out: free(NULL),
// malloc(0), alignment, the merging of a freed block with both its
// neighbours, splitting, a rest too small to split, realloc in place,
// smaller, to 0, from NULL, and by copying, calloc's overflow check and
// zeroing, and the heap's exhaustion and recovery. main returns 0.
//
// A block is the size asked for plus an 8-byte header, rounded up to 8,
// and a free block is split only if at least 16 bytes would be left.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void)
{
    free(NULL);
    char *a = malloc(0), *b = malloc(0);    // 8-byte blocks: just the header
    printf("%d %d %d\n", a != NULL, b != NULL, (int)(b - a));

    // Blocks of 16, 16, 16, 24, 24, and 112 bytes, each 8-aligned.
    static const size_t sizes[6] = {1, 3, 8, 9, 15, 100};
    char *p[6];
    int bad = 0;
    for (int i = 0; i < 6; i++) {
        p[i] = malloc(sizes[i]);
        bad += (uintptr_t)p[i] % 8 != 0;
    }
    printf("%d %d %d %d %d %d\n", bad, (int)(p[1] - p[0]), (int)(p[2] - p[1]),
           (int)(p[3] - p[2]), (int)(p[4] - p[3]), (int)(p[5] - p[4]));

    // Freeing p[2] last merges it with p[1] before and p[3] after: one
    // block of 16 + 16 + 24 = 56 bytes, which a 48-byte request fills.
    free(p[1]);
    free(p[3]);
    free(p[2]);
    char *q = malloc(48);
    printf("%d\n", q == p[1]);
    // Freed again, it is split: 16 bytes, 16 bytes, and 24 left, which a
    // 16-byte request fills exactly.
    free(q);
    char *r = malloc(8), *s = malloc(8), *t = malloc(16);
    printf("%d %d %d\n", r == p[1], s == p[2], t == p[3]);
    // A 1-byte request needs 16 bytes. p[4]'s 24-byte block would leave 8,
    // too few to split, so the whole block is used, and realloc to 16
    // bytes, its whole size less the header, stays in place.
    free(p[4]);
    char *u = malloc(1);
    printf("%d %d\n", u == p[4], realloc(u, 16) == u);

    // realloc to a smaller size, or to 0, keeps the block. To a larger one
    // it copies the contents to a new block.
    char *g = malloc(10);
    strcpy(g, "keep");
    printf("%d %d\n", realloc(g, 4) == g, realloc(g, 0) == g);
    char *h = realloc(g, 100);
    printf("[%s] %d %d\n", h, h != g, realloc(NULL, 5) != NULL);

    // calloc: count * size above SIZE_MAX gives NULL, and the memory is
    // zeroed, even when it was used before.
    printf("%d %d\n", calloc(0x10000, 0x10000) == NULL, calloc(0x40000000, 4) == NULL);
    char *z = malloc(32);
    memset(z, 0xFF, 32);
    free(z);
    int *w = calloc(8, 4);
    int sum = 0;
    for (int i = 0; i < 8; i++)
        sum += w[i];
    printf("%d %d\n", (char *)w == z, sum);

    // The memory is one page, and nicewasm lets it grow no further. Blocks
    // of 1008 bytes come from the end of the heap, one after the other,
    // until malloc fails. Freed, they merge into one block, which then
    // holds a request for all of them at once, less their headers.
    void *list[100];
    int n = 0;
    while (n < 100 && (list[n] = malloc(1000)) != NULL)
        n++;
    for (int i = 0; i < n; i++)
        free(list[i]);
    char *big = malloc((size_t)n * 1000);
    printf("%d %d %d\n", n > 10 && n < 65, big == list[0], malloc((size_t)n * 1000) == NULL);
    return 0;
}
