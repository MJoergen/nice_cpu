#include <assert.h>
#include <ctype.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

int abs(int x) { return x < 0 ? -x : x; }
long labs(long x) { return x < 0 ? -x : x; }
long long llabs(long long x) { return x < 0 ? -x : x; }

static unsigned rand_state = 1;

void srand(unsigned seed) { rand_state = seed; }

int rand(void)
{
    rand_state = rand_state * 1103515245u + 12345u;
    return (rand_state >> 16) & RAND_MAX;
}

_Noreturn void abort(void)
{
    __builtin_trap();           // wasm unreachable: a trap (WASM.md)
}

_Noreturn void __assert_fail(const char *expr, const char *file, int line, const char *func)
{
    fprintf(stderr, "%s:%d: %s: Assertion `%s' failed.\n", file, line, func, expr);
    abort();
}

// The value of a digit or letter in bases up to 36, or 36 if it is neither.
static unsigned digit(int c)
{
    if (isdigit(c))
        return (unsigned)(c - '0');
    if (isalpha(c))
        return (unsigned)(tolower(c) - 'a' + 10);
    return 36;
}

// Reads an unsigned number, as strtoul does, and sets *neg if it had a
// minus sign. The result saturates at ULONG_MAX, and *over says that it
// did. If no digits are read, *end is s.
static unsigned long parse(const char *s, char **end, int base, int *neg, int *over)
{
    const char *p = s;
    while (isspace(*p))
        p++;
    *neg = 0;
    if (*p == '-' || *p == '+')
        *neg = *p++ == '-';
    if ((base == 0 || base == 16) && p[0] == '0' && (p[1] == 'x' || p[1] == 'X') &&
        digit(p[2]) < 16) {
        p += 2;
        base = 16;
    } else if (base == 0) {
        base = *p == '0' ? 8 : 10;
    }

    unsigned long v = 0;
    int any = 0;
    *over = 0;
    for (unsigned d; (d = digit(*p)) < (unsigned)base; p++) {
        any = 1;
        if (v > (ULONG_MAX - d) / (unsigned)base)
            *over = 1;
        else
            v = v * (unsigned)base + d;
    }
    if (end)
        *end = (char *)(any ? p : s);
    return *over ? ULONG_MAX : v;
}

unsigned long strtoul(const char *s, char **end, int base)
{
    int neg, over;
    unsigned long v = parse(s, end, base, &neg, &over);
    return neg && !over ? 0UL - v : v;
}

long strtol(const char *s, char **end, int base)
{
    int neg, over;
    unsigned long v = parse(s, end, base, &neg, &over);
    if (neg)
        return v > (unsigned long)LONG_MAX + 1 ? LONG_MIN : (long)(0UL - v);
    return v > LONG_MAX ? LONG_MAX : (long)v;
}

long atol(const char *s) { return strtol(s, NULL, 10); }
int atoi(const char *s) { return (int)strtol(s, NULL, 10); }
