#ifndef _STDLIB_H
#define _STDLIB_H

#include <stddef.h>

void *malloc(size_t size);
void *calloc(size_t count, size_t size);
void *realloc(void *p, size_t size);
void free(void *p);

int abs(int x);
long labs(long x);
long long llabs(long long x);

int atoi(const char *s);
long atol(const char *s);
long strtol(const char *s, char **end, int base);
unsigned long strtoul(const char *s, char **end, int base);

#define RAND_MAX 32767

int rand(void);
void srand(unsigned seed);

_Noreturn void abort(void);
// Not defined in C: the translator turns this import into the assembly
// routine _exit (WASM.md).
__attribute__((import_module("env"), import_name("exit")))
_Noreturn void exit(int status);

#endif
