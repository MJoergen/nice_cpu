// printf and its relatives. They support the flags - + space # 0 (+ and
// space for the signed conversions, as C defines them), a width and a
// precision (either may be *), the length modifiers hh h l ll z t j, and
// the conversions d i u o x X c s p %. The float conversions, such as %f,
// take their argument but are copied to the output as they stand, and so
// is any other conversion.
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// Where the output goes: the console if buf is NULL, else buf, which has
// room for cap bytes. len counts every byte, also those that did not fit.
struct out {
    char *buf;
    size_t cap;
    size_t len;
};

static void emit(struct out *o, char c)
{
    if (!o->buf)
        putchar(c);
    else if (o->len + 1 < o->cap)
        o->buf[o->len] = c;
    o->len++;
}

static void emit_n(struct out *o, char c, int n)
{
    while (n-- > 0)
        emit(o, c);
}

// PTR is %p: 0x comes before the digits, also for a null pointer.
enum { LEFT = 1, PLUS = 2, SPACE = 4, ALT = 8, ZERO = 16, PTR = 32 };

// Writes the digits of v in base 2..16, last digit first, and returns
// their number. Values that fit in 32 bits use the 32-bit division, which
// is much faster on NICE than the 64-bit one.
static int digits(char *tmp, unsigned long long v, unsigned base, int upper)
{
    const char *d = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    int n = 0;
    if (v >> 32) {
        while (v >> 32) {
            tmp[n++] = d[v % base];
            v /= base;
        }
    }
    unsigned w = (unsigned)v;
    while (w) {
        tmp[n++] = d[w % base];
        w /= base;
    }
    return n;
}

static void number(struct out *o, unsigned long long v, int neg, unsigned base, int upper,
                   int flags, int width, int prec)
{
    char tmp[24];
    int n = digits(tmp, v, base, upper);
    char prefix[2];
    int np = 0;

    if (neg)
        prefix[np++] = '-';
    else if (flags & PLUS)
        prefix[np++] = '+';
    else if (flags & SPACE)
        prefix[np++] = ' ';
    if (base == 16 && ((flags & PTR) || ((flags & ALT) && v))) {
        prefix[np++] = '0';
        prefix[np++] = upper ? 'X' : 'x';
    }

    if (prec < 0)
        prec = 1;
    else
        flags &= ~ZERO;
    if ((flags & ALT) && base == 8 && prec <= n)
        prec = n + 1;           // the leading 0 of the alternate form
    int zeros = prec > n ? prec - n : 0;
    int pad = width - np - zeros - n;

    if (flags & ZERO) {
        zeros += pad > 0 ? pad : 0;
        pad = 0;
    }
    if (!(flags & LEFT))
        emit_n(o, ' ', pad);
    for (int i = 0; i < np; i++)
        emit(o, prefix[i]);
    emit_n(o, '0', zeros);
    while (n > 0)
        emit(o, tmp[--n]);
    if (flags & LEFT)
        emit_n(o, ' ', pad);
}

static void format(struct out *o, const char *fmt, va_list ap)
{
    while (*fmt) {
        if (*fmt != '%') {
            emit(o, *fmt++);
            continue;
        }
        const char *start = fmt++;

        int flags = 0;
        for (;; fmt++) {
            if (*fmt == '-') flags |= LEFT;
            else if (*fmt == '+') flags |= PLUS;
            else if (*fmt == ' ') flags |= SPACE;
            else if (*fmt == '#') flags |= ALT;
            else if (*fmt == '0') flags |= ZERO;
            else break;
        }

        int width = 0;
        if (*fmt == '*') {
            width = va_arg(ap, int);
            if (width < 0) {
                flags |= LEFT;
                width = -width;
            }
            fmt++;
        } else {
            while (*fmt >= '0' && *fmt <= '9')
                width = width * 10 + (*fmt++ - '0');
        }
        if (flags & LEFT)
            flags &= ~ZERO;

        int prec = -1;
        if (*fmt == '.') {
            fmt++;
            prec = 0;
            if (*fmt == '*') {
                prec = va_arg(ap, int);
                fmt++;
            } else {
                while (*fmt >= '0' && *fmt <= '9')
                    prec = prec * 10 + (*fmt++ - '0');
            }
        }

        // 0: int, 1: long (also 32 bits), 2: long long, -1: short, -2: char.
        int size = 0;
        if (*fmt == 'h') {
            size = -1;
            if (*++fmt == 'h') {
                size = -2;
                fmt++;
            }
        } else if (*fmt == 'l') {
            size = 1;
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

        char c = *fmt;
        if (c)
            fmt++;
        switch (c) {
        case 'd':
        case 'i': {
            long long v = size == 2 ? va_arg(ap, long long) : va_arg(ap, int);
            if (size == -1)
                v = (short)v;
            else if (size == -2)
                v = (signed char)v;
            int neg = v < 0;
            number(o, neg ? 0ULL - (unsigned long long)v : (unsigned long long)v, neg, 10, 0,
                   flags, width, prec);
            break;
        }
        case 'u':
        case 'o':
        case 'x':
        case 'X': {
            unsigned long long v = size == 2 ? va_arg(ap, unsigned long long)
                                             : va_arg(ap, unsigned);
            if (size == -1)
                v = (unsigned short)v;
            else if (size == -2)
                v = (unsigned char)v;
            unsigned base = c == 'u' ? 10 : c == 'o' ? 8 : 16;
            // + and space are for the signed conversions only.
            number(o, v, 0, base, c == 'X', flags & ~(PLUS | SPACE), width, prec);
            break;
        }
        case 'p':
            number(o, (uintptr_t)va_arg(ap, void *), 0, 16, 0, (flags & ~(PLUS | SPACE)) | PTR,
                   width, prec);
            break;
        case 'c':
            if (!(flags & LEFT))
                emit_n(o, ' ', width - 1);
            emit(o, (char)va_arg(ap, int));
            if (flags & LEFT)
                emit_n(o, ' ', width - 1);
            break;
        case 's': {
            const char *s = va_arg(ap, const char *);
            if (!s)
                s = "(null)";
            int n = prec < 0 ? (int)strlen(s) : (int)strnlen(s, (size_t)prec);
            if (!(flags & LEFT))
                emit_n(o, ' ', width - n);
            for (int i = 0; i < n; i++)
                emit(o, s[i]);
            if (flags & LEFT)
                emit_n(o, ' ', width - n);
            break;
        }
        case '%':
            emit(o, '%');
            break;
        case 'a': case 'A': case 'e': case 'E': case 'f': case 'F': case 'g': case 'G':
            (void)va_arg(ap, double);
            // fall through
        default:
            while (start < fmt)
                emit(o, *start++);
            break;
        }
    }
}

static int finish(struct out *o)
{
    if (o->buf && o->cap)
        o->buf[o->len < o->cap ? o->len : o->cap - 1] = '\0';
    return (int)o->len;
}

int vsnprintf(char *buf, size_t size, const char *fmt, va_list ap)
{
    struct out o = {buf, size, 0};
    format(&o, fmt, ap);
    return finish(&o);
}

int vsprintf(char *buf, const char *fmt, va_list ap)
{
    return vsnprintf(buf, SIZE_MAX, fmt, ap);
}

int vprintf(const char *fmt, va_list ap)
{
    struct out o = {NULL, 0, 0};
    format(&o, fmt, ap);
    return (int)o.len;
}

int printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vprintf(fmt, ap);
    va_end(ap);
    return n;
}

int sprintf(char *buf, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vsprintf(buf, fmt, ap);
    va_end(ap);
    return n;
}

int snprintf(char *buf, size_t size, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, size, fmt, ap);
    va_end(ap);
    return n;
}
