// The heap of a memory whose reserved part ends before the heap starts
// (WASM.md, Linear memory). malloc takes such a heap as empty and returns
// NULL. Otherwise it would take the bytes up to the end of the address
// space as free, and write its first block past the reserved part, which
// traps (code 2).
//
// The test runs twice. With the whole page, main returns 0: the memory
// ends above __heap_base, and malloc, calloc, and realloc each give a
// block. As noheap_cut it is translated with --memory-bytes 4 below
// __heap_base (the Makefile says how), and main returns 15, a bit for
// each: the memory ends below __heap_base, and the three return NULL.
//
// The program has no static data of its own and prints nothing, so its
// only static data is malloc's three words, which the reserved part must
// hold.
#include <nice.h>
#include <stdint.h>
#include <stdlib.h>

extern unsigned char __heap_base;

int main(void)
{
    int below = nice_heap_end() < (uintptr_t)&__heap_base;
    int no_malloc = malloc(16) == NULL;
    int no_calloc = calloc(4, 4) == NULL;
    int no_realloc = realloc(NULL, 8) == NULL;
    return below << 3 | no_malloc << 2 | no_calloc << 1 | no_realloc;
}
