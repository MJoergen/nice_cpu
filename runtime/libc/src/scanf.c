// scanf and sscanf. The format may hold white space, which skips any white
// space in the input, ordinary characters, which must match, and
// conversions. A conversion may have * to read without storing, a width,
// and the length modifiers hh h l ll z t j. The conversions are d i u o x X
// p c s [ n and %. A set in [ may hold ranges such as a-z, and ^ first
// negates it.
#include <ctype.h>
#include <limits.h>
#include <stdio.h>
#include "internal.h"

// Where the input comes from: the string s, or the console if s is NULL.
// count is the number of bytes taken, for %n.
struct in {
    const char *s;
    int count;
};

// No byte: the width ran out before the next byte was read.
#define NONE (-2)

static int get(struct in *in)
{
    int c;
    if (in->s)
        c = *in->s ? (unsigned char)*in->s++ : EOF;
    else
        c = getchar();
    if (c != EOF)
        in->count++;
    return c;
}

static void unget(struct in *in, int c)
{
    if (c < 0)
        return;
    in->count--;
    if (in->s)
        in->s--;
    else
        __stdin_back = c;
}

// The value of a digit or letter in bases up to 36, or 36 if c is neither.
static unsigned digit(int c)
{
    if (c >= '0' && c <= '9')
        return (unsigned)(c - '0');
    if (c >= 'a' && c <= 'z')
        return (unsigned)(c - 'a' + 10);
    if (c >= 'A' && c <= 'Z')
        return (unsigned)(c - 'A' + 10);
    return 36;
}

// Reads an integer of at most width bytes, as strtoul does with the base.
// Returns 0 if there were no digits.
static int number(struct in *in, int width, unsigned base, unsigned long long *v)
{
    int w = width ? width : INT_MAX;
    int neg = 0, any = 0;
    int c = get(in);
#define NEXT() (c = --w ? get(in) : NONE)
    if (c == '-' || c == '+') {
        neg = c == '-';
        NEXT();
    }
    if ((base == 0 || base == 16) && c == '0') {
        any = 1;
        NEXT();
        if (c == 'x' || c == 'X') {
            base = 16;
            NEXT();
        } else if (base == 0) {
            base = 8;
        }
    }
    if (base == 0)
        base = 10;
    unsigned long long x = 0;
    for (unsigned d; (d = digit(c)) < base; NEXT()) {
        x = x * base + d;
        any = 1;
    }
#undef NEXT
    unget(in, c);
    *v = neg ? 0 - x : x;
    return any;
}

// Whether c is in the set of a [ conversion, from set to just before end.
static int in_set(int c, const char *set, const char *end)
{
    int neg = *set == '^';
    if (neg)
        set++;
    for (const char *p = set; p < end; p++) {
        if (p[1] == '-' && p + 2 < end) {
            if (c >= (unsigned char)p[0] && c <= (unsigned char)p[2])
                return !neg;
            p += 2;
        } else if (c == (unsigned char)*p) {
            return !neg;
        }
    }
    return neg;
}

static int scan(struct in *in, const char *fmt, va_list ap)
{
    int n = 0;                  // the number of values stored
    int c = 0;                  // the byte that ended the scan

    while (*fmt) {
        if (isspace((unsigned char)*fmt)) {
            while (isspace((unsigned char)*fmt))
                fmt++;
            while (isspace(c = get(in)))
                ;
            unget(in, c);
            continue;
        }
        if (*fmt != '%' || fmt[1] == '%') {
            if (*fmt == '%') {
                fmt++;
                while (isspace(c = get(in)))
                    ;
            } else {
                c = get(in);
            }
            if (c != (unsigned char)*fmt) {
                unget(in, c);
                goto done;
            }
            fmt++;
            continue;
        }
        fmt++;

        int store = 1;
        if (*fmt == '*') {
            store = 0;
            fmt++;
        }
        int width = 0;
        while (*fmt >= '0' && *fmt <= '9')
            width = width * 10 + (*fmt++ - '0');
        // 0: int and long (both 32 bits), 2: long long, -1: short, -2: char.
        int size = 0;
        if (*fmt == 'h') {
            size = -1;
            if (*++fmt == 'h') {
                size = -2;
                fmt++;
            }
        } else if (*fmt == 'l') {
            if (*++fmt == 'l') {
                size = 2;
                fmt++;
            }
        } else if (*fmt == 'j') {
            size = 2;
            fmt++;
        } else if (*fmt == 'z' || *fmt == 't') {
            fmt++;
        }

        char conv = *fmt;
        if (!conv)
            break;
        fmt++;
        if (conv != 'c' && conv != '[' && conv != 'n') {
            while (isspace(c = get(in)))
                ;
            unget(in, c);
            if (c == EOF)
                goto done;
        }

        switch (conv) {
        case 'n':
            if (store)
                *va_arg(ap, int *) = in->count;
            break;
        case 'c': {
            char *p = store ? va_arg(ap, char *) : NULL;
            for (int i = 0; i < (width ? width : 1); i++) {
                if ((c = get(in)) == EOF)
                    goto done;
                if (p)
                    p[i] = (char)c;
            }
            n += store;
            break;
        }
        case 's':
        case '[': {
            const char *set = fmt, *end = fmt;
            if (conv == '[') {
                // A ] right after [ or [^ is part of the set.
                if (*end == '^')
                    end++;
                if (*end == ']')
                    end++;
                while (*end && *end != ']')
                    end++;
                fmt = *end ? end + 1 : end;
            }
            char *p = store ? va_arg(ap, char *) : NULL;
            int k = 0;
            while (!width || k < width) {
                c = get(in);
                if (c == EOF || (conv == 's' ? isspace(c) : !in_set(c, set, end))) {
                    unget(in, c);
                    break;
                }
                if (p)
                    p[k] = (char)c;
                k++;
            }
            if (!k)
                goto done;
            if (p)
                p[k] = '\0';
            n += store;
            break;
        }
        case 'd':
        case 'i':
        case 'u':
        case 'o':
        case 'x':
        case 'X':
        case 'p': {
            unsigned base = conv == 'i' ? 0 : conv == 'o' ? 8 : conv == 'd' || conv == 'u' ? 10 : 16;
            unsigned long long v;
            if (!number(in, width, base, &v)) {
                c = 0;
                goto done;
            }
            if (store) {
                void *p = va_arg(ap, void *);
                if (size == -2)
                    *(char *)p = (char)v;
                else if (size == -1)
                    *(short *)p = (short)v;
                else if (size == 2)
                    *(long long *)p = (long long)v;
                else
                    *(int *)p = (int)v;
                n++;
            }
            break;
        }
        default:
            c = 0;
            goto done;
        }
    }
    return n;

done:
    // An input failure before the first conversion gives EOF.
    return c == EOF && n == 0 ? EOF : n;
}

int vsscanf(const char *s, const char *fmt, va_list ap)
{
    struct in in = {s, 0};
    return scan(&in, fmt, ap);
}

int vscanf(const char *fmt, va_list ap)
{
    struct in in = {NULL, 0};
    return scan(&in, fmt, ap);
}

int sscanf(const char *s, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vsscanf(s, fmt, ap);
    va_end(ap);
    return n;
}

int scanf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vscanf(fmt, ap);
    va_end(ap);
    return n;
}
