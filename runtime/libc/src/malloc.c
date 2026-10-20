// A first-fit allocator. The heap starts at __heap_base, which wasm-ld
// puts after the data and the stack, and grows with memory.grow. Each
// block has an 8-byte header. Free blocks are kept in a list sorted by
// address, and neighbours are merged when a block is freed.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct block {
    size_t size;                // of the whole block, a multiple of 8
    struct block *next;         // the next free block; unused when allocated
};

#define HEADER sizeof(struct block)
#define PAGE 65536u

extern unsigned char __heap_base;

static struct block *free_list;
static uintptr_t brk_, heap_end;

// size bytes of new heap, or NULL if memory.grow fails.
static struct block *more(size_t size)
{
    if (!brk_) {
        brk_ = ((uintptr_t)&__heap_base + 7) & ~(uintptr_t)7;
        heap_end = __builtin_wasm_memory_size(0) * PAGE;
    }
    if (size > heap_end - brk_) {
        // The page count would wrap: more than all of memory
        if (size - (heap_end - brk_) > SIZE_MAX - (PAGE - 1))
            return NULL;
        size_t pages = (size - (heap_end - brk_) + PAGE - 1) / PAGE;
        if (__builtin_wasm_memory_grow(0, pages) == SIZE_MAX)
            return NULL;
        heap_end += pages * PAGE;
    }
    struct block *b = (struct block *)brk_;
    brk_ += size;
    b->size = size;
    return b;
}

void *malloc(size_t n)
{
    if (n > SIZE_MAX - HEADER - 7)
        return NULL;
    size_t size = (n + HEADER + 7) & ~(size_t)7;

    struct block **pp = &free_list;
    for (struct block *b = *pp; b; pp = &b->next, b = *pp) {
        if (b->size < size)
            continue;
        if (b->size - size >= 2 * HEADER) {
            struct block *rest = (struct block *)((char *)b + size);
            rest->size = b->size - size;
            rest->next = b->next;
            *pp = rest;
            b->size = size;
        } else {
            *pp = b->next;
        }
        return b + 1;
    }
    struct block *b = more(size);
    return b ? b + 1 : NULL;
}

void free(void *p)
{
    if (!p)
        return;
    struct block *b = (struct block *)p - 1;
    struct block *prev = NULL, *next = free_list;
    while (next && next < b) {
        prev = next;
        next = next->next;
    }
    if (next && (char *)b + b->size == (char *)next) {
        b->size += next->size;
        b->next = next->next;
    } else {
        b->next = next;
    }
    if (prev && (char *)prev + prev->size == (char *)b) {
        prev->size += b->size;
        prev->next = b->next;
    } else if (prev) {
        prev->next = b;
    } else {
        free_list = b;
    }
}

void *calloc(size_t count, size_t size)
{
    if (size && count > SIZE_MAX / size)
        return NULL;
    void *p = malloc(count * size);
    if (p)
        memset(p, 0, count * size);
    return p;
}

void *realloc(void *p, size_t n)
{
    if (!p)
        return malloc(n);
    size_t have = ((struct block *)p - 1)->size - HEADER;
    if (n <= have)
        return p;
    void *q = malloc(n);
    if (q) {
        memcpy(q, p, have);
        free(p);
    }
    return q;
}
