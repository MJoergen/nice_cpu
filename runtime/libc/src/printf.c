// printf and its relatives. They support the flags - + space # 0 (+ and
// space for the signed and float conversions, as C defines them), a width
// and a precision (either may be *), the length modifiers hh h l ll z t j,
// and the conversions d i u o x X c s p %, and e E f F g G a A for a
// double. Any other conversion, such as one with L for a long double, is
// copied to the output as it stands.
#include <float.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// Where the output goes: the stream f if it is not NULL, else buf, which
// has room for cap bytes and may be NULL if cap is 0. len counts every
// byte, also those that did not fit.
struct out {
    char *buf;
    size_t cap;
    size_t len;
    FILE *f;
};

static void emit(struct out *o, char c)
{
    if (o->f)
        fputc(c, o->f);
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

// The float conversions, from musl's fmt_fp (src/math/COPYRIGHT), which
// works in long double and takes the float apart with float arithmetic.
// This one takes a double apart from its bits, m times 2 to the e2 with m
// an integer, and rounds with integers, so that printf needs no float
// library. The digits are kept in base 10^9, a word each, in big: the
// integer part ends at r, and the fraction follows. Rounding is to
// nearest, ties to even, as in musl's default rounding mode. fmt_fp and the
// helpers only it calls are compiled for size, as with -Os, and fmt_fp is
// not inlined: that saves 3900 words, as -O2 unrolls its loops, and costs
// 3% of the steps of a float conversion.

static const char xdigits[16] = "0123456789ABCDEF";

__attribute__((minsize)) static void emit_s(struct out *o, const char *s, long n)
{
    while (n-- > 0)
        emit(o, *s++);
}

// Pads to the width w with c, from l bytes, unless fl has - or 0.
__attribute__((minsize)) static void fill(struct out *o, char c, int w, int l, int fl)
{
    if (!(fl & (LEFT | ZERO)) && l < w)
        emit_n(o, c, w - l);
}

// Writes x in decimal, ending just before s, and returns its start.
__attribute__((minsize)) static char *fmt_u(uint32_t x, char *s)
{
    for (; x; x /= 10)
        *--s = (char)('0' + x % 10);
    return s;
}

#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))

// 2 words for m, and one for each shift of 9 bits right, up to 2^-1074.
#define BIG (2 + (DBL_MANT_DIG - DBL_MIN_EXP + 8) / 9 + 2)

__attribute__((minsize, noinline)) static void fmt_fp(struct out *o, double y, int w, int p, int fl, int t)
{
    uint64_t bits;
    memcpy(&bits, &y, sizeof bits);
    uint64_t m = bits & ((1ULL << 52) - 1);
    int ex = (int)(bits >> 52) & 0x7ff;
    const char *prefix = "-0X+0X 0X-0x+0x 0x";
    int pl = 1;
    if (bits >> 63)
        ;
    else if (fl & PLUS)
        prefix += 3;
    else if (fl & SPACE)
        prefix += 6;
    else
        prefix++, pl = 0;

    if (ex == 0x7ff) {
        const char *s = m ? (t & 32 ? "nan" : "NAN") : (t & 32 ? "inf" : "INF");
        fill(o, ' ', w, 3 + pl, fl & ~ZERO);
        emit_s(o, prefix, pl);
        emit_s(o, s, 3);
        fill(o, ' ', w, 3 + pl, fl ^ LEFT);
        return;
    }

    int e2;
    if (ex) {
        m |= 1ULL << 52;
        e2 = ex - 1075;
    } else {
        e2 = m ? -1074 : 0;
    }

    char ebuf0[12], *ebuf = ebuf0 + sizeof ebuf0, *estr;
    int l;

    if ((t | 32) == 'a') {
        // One hex digit, 1 but for 0, before the point, and the exponent
        // of 2 after p, as musl prints subnormals too.
        char buf[16], *s = buf;
        if (t & 32)
            prefix += 9;
        pl += 2;
        if (m) {
            while (!(m >> 52)) {
                m <<= 1;
                e2--;
            }
            e2 += 52;
        }
        if (p >= 0 && p < 13) {
            int drop = 52 - 4 * p;
            uint64_t q = m >> drop, rem = m & ((1ULL << drop) - 1), half = 1ULL << (drop - 1);
            if (rem > half || (rem == half && (q & 1)))
                q++;
            m = q << drop;      // 0x1.f rounded to 0 places is 0x2
        }
        estr = fmt_u((uint32_t)(e2 < 0 ? -e2 : e2), ebuf);
        if (estr == ebuf)
            *--estr = '0';
        *--estr = e2 < 0 ? '-' : '+';
        *--estr = (char)(t + ('p' - 'a'));

        uint64_t frac = m & ((1ULL << 52) - 1);
        *s++ = xdigits[m >> 52] | (t & 32);
        if (frac || p > 0 || (fl & ALT))
            *s++ = '.';
        for (; frac; frac = (frac << 4) & ((1ULL << 52) - 1))
            *s++ = xdigits[frac >> 48] | (t & 32);

        if (p > 0 && s - buf - 2 < p)
            l = p + 2 + (int)(ebuf - estr);
        else
            l = (int)(s - buf) + (int)(ebuf - estr);
        fill(o, ' ', w, pl + l, fl);
        emit_s(o, prefix, pl);
        fill(o, '0', w, pl + l, fl ^ ZERO);
        emit_s(o, buf, s - buf);
        emit_n(o, '0', l - (int)(ebuf - estr) - (int)(s - buf));
        emit_s(o, estr, ebuf - estr);
        fill(o, ' ', w, pl + l, fl ^ LEFT);
        return;
    }
    if (p < 0)
        p = 6;

    uint32_t big[BIG], *a, *d, *r, *z;
    int e, i, j;
    a = z = e2 < 0 ? big : big + BIG - 2;
    if (m >= 1000000000)
        *z++ = (uint32_t)(m / 1000000000);
    *z++ = (uint32_t)(m % 1000000000);
    r = z - 1;

    while (e2 > 0) {
        uint32_t carry = 0;
        int sh = MIN(29, e2);
        for (d = z - 1; d >= a; d--) {
            uint64_t x = ((uint64_t)*d << sh) + carry;
            *d = (uint32_t)(x % 1000000000);
            carry = (uint32_t)(x / 1000000000);
        }
        if (carry)
            *--a = carry;
        while (z > a && !z[-1])
            z--;
        e2 -= sh;
    }
    while (e2 < 0) {
        uint32_t carry = 0, *b;
        int sh = MIN(9, -e2), need = 1 + (p + DBL_MANT_DIG / 3 + 8) / 9;
        for (d = a; d < z; d++) {
            uint32_t rm = *d & ((1u << sh) - 1);
            *d = (*d >> sh) + carry;
            carry = (1000000000u >> sh) * rm;
        }
        if (!*a)
            a++;
        if (carry)
            *z++ = carry;
        // Digits far past the precision are not worth computing.
        b = (t | 32) == 'f' ? r : a;
        if (z - b > need)
            z = b + need;
        e2 += sh;
    }

    if (a < z)
        for (i = 10, e = 9 * (int)(r - a); *a >= (uint32_t)i; i *= 10, e++)
            ;
    else
        e = 0;

    // Rounds at j digits after the point, which may be negative.
    j = p - ((t | 32) != 'f') * e - ((t | 32) == 'g' && p);
    if (j < 9 * (z - r - 1)) {
        uint32_t x;
        // The offsets keep the division away from negative numbers.
        d = r + 1 + ((j + 9 * DBL_MAX_EXP) / 9 - DBL_MAX_EXP);
        j += 9 * DBL_MAX_EXP;
        j %= 9;
        for (i = 10, j++; j < 9; i *= 10, j++)
            ;
        x = *d % (uint32_t)i;
        if (x || d + 1 != z) {
            int odd = (*d / (uint32_t)i & 1) || (i == 1000000000 && d > a && (d[-1] & 1));
            uint32_t half = (uint32_t)i / 2;
            *d -= x;
            if (x > half || (x == half && (d + 1 != z || odd))) {
                *d = *d + (uint32_t)i;
                while (*d > 999999999) {
                    *d-- = 0;
                    if (d < a)
                        *--a = 0;
                    (*d)++;
                }
                for (i = 10, e = 9 * (int)(r - a); *a >= (uint32_t)i; i *= 10, e++)
                    ;
            }
        }
        if (z > d + 1)
            z = d + 1;
    }
    for (; z > a && !z[-1]; z--)
        ;

    if ((t | 32) == 'g') {
        if (!p)
            p++;
        if (p > e && e >= -4) {
            t--;
            p -= e + 1;
        } else {
            t -= 2;
            p--;
        }
        if (!(fl & ALT)) {
            // The zeros at the end of the last word.
            if (z > a && z[-1])
                for (i = 10, j = 0; z[-1] % (uint32_t)i == 0; i *= 10, j++)
                    ;
            else
                j = 9;
            if ((t | 32) == 'f')
                p = MIN(p, MAX(0, 9 * (int)(z - r - 1) - j));
            else
                p = MIN(p, MAX(0, 9 * (int)(z - r - 1) + e - j));
        }
    }
    l = 1 + p + (p || (fl & ALT));
    if ((t | 32) == 'f') {
        if (e > 0)
            l += e;
    } else {
        estr = fmt_u((uint32_t)(e < 0 ? -e : e), ebuf);
        while (ebuf - estr < 2)
            *--estr = '0';
        *--estr = e < 0 ? '-' : '+';
        *--estr = (char)t;
        l += (int)(ebuf - estr);
    }

    fill(o, ' ', w, pl + l, fl);
    emit_s(o, prefix, pl);
    fill(o, '0', w, pl + l, fl ^ ZERO);

    char buf[9 + 9];
    if ((t | 32) == 'f') {
        if (a > r)
            a = r;
        for (d = a; d <= r; d++) {
            char *s = fmt_u(*d, buf + 9);
            if (d != a)
                while (s > buf)
                    *--s = '0';
            else if (s == buf + 9)
                *--s = '0';
            emit_s(o, s, buf + 9 - s);
        }
        if (p || (fl & ALT))
            emit(o, '.');
        for (; d < z && p > 0; d++, p -= 9) {
            char *s = fmt_u(*d, buf + 9);
            while (s > buf)
                *--s = '0';
            emit_s(o, s, MIN(9, p));
        }
        emit_n(o, '0', p);
    } else {
        if (z <= a)
            z = a + 1;
        for (d = a; d < z && p >= 0; d++) {
            char *s = fmt_u(*d, buf + 9);
            if (s == buf + 9)
                *--s = '0';
            if (d != a)
                while (s > buf)
                    *--s = '0';
            else {
                emit(o, *s++);
                if (p > 0 || (fl & ALT))
                    emit(o, '.');
            }
            emit_s(o, s, MIN(buf + 9 - s, p));
            p -= (int)(buf + 9 - s);
        }
        emit_n(o, '0', p);
        emit_s(o, estr, ebuf - estr);
    }
    fill(o, ' ', w, pl + l, fl ^ LEFT);
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
            fmt_fp(o, va_arg(ap, double), width, prec, flags, c);
            break;
        default:
            while (start < fmt)
                emit(o, *start++);
            break;
        }
    }
}

static int finish(struct out *o)
{
    if (o->cap)
        o->buf[o->len < o->cap ? o->len : o->cap - 1] = '\0';
    return (int)o->len;
}

int vsnprintf(char *buf, size_t size, const char *fmt, va_list ap)
{
    struct out o = {buf, size, 0, 0};
    format(&o, fmt, ap);
    return finish(&o);
}

int vsprintf(char *buf, const char *fmt, va_list ap)
{
    return vsnprintf(buf, SIZE_MAX, fmt, ap);
}

int vfprintf(FILE *f, const char *fmt, va_list ap)
{
    struct out o = {NULL, 0, 0, f};
    format(&o, fmt, ap);
    return (int)o.len;
}

int vprintf(const char *fmt, va_list ap)
{
    return vfprintf(stdout, fmt, ap);
}

int fprintf(FILE *f, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vfprintf(f, fmt, ap);
    va_end(ap);
    return n;
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
