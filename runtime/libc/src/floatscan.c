// __floatscan, which reads a float for strtod and scanf: musl's
// src/internal/floatscan.c (math/COPYRIGHT), in double where musl has long
// double, as musl is built where long double is double, such as on 32-bit
// Arm. Its shgetc, shunget, and shlim are the functions below, on struct
// fscan in place of musl's FILE. strtod, strtof, and atof are musl's too.
// Five changes fix what musl gets wrong in double, each found by
// test/fuzz_strtod.py or a test of it against glibc on the host:
// - hexfloat keeps 15 hex digits, not 14, so that the first digit it drops
//   lies below the bit it rounds at, as with musl's long doubles. With 14,
//   0x1ffd052e0b574485p0 rounds down, its tail 0x85 taken for one half.
// - hexfloat rounds a subnormal of 31 bits, such as 0x3628fc0946bcd9p-1097,
//   with its own rule, since the sticky bit would be the half.
// - A hex float that rounds to 0 keeps its sign. It sets ERANGE then, and
//   when it rounds up to infinity, such as 0x1.fffffffffffff8p1023, also
//   when the rounding is left to scalbn, which sets no errno here.
// - decfloat's sticky bit has the sign of the float, so that
//   -2.4703282292062328e-324 does not round to 0.
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <float.h>
#include <limits.h>
#include <errno.h>
#include <ctype.h>

#include "floatscan.h"

#define LD_B1B_DIG 2
#define LD_B1B_MAX 9007199, 254740991
#define KMAX 128

#define MASK (KMAX-1)

// The next byte, or EOF at the end of the input or after lim bytes.
static int shgetc(struct fscan *f)
{
    int c;
    if (f->lim && f->n >= f->lim)
        c = EOF;
    else if (f->s)
        c = f->s[f->n] ? (unsigned char)f->s[f->n] : EOF;
    else
        c = fgetc(f->f);
    f->last = c;
    if (c != EOF)
        f->n++;
    return c;
}

// Gives back the last byte read, unless it was EOF. A string can give back
// any number of bytes; __floatscan gives back more than one only for
// strtod, whose pok is 1.
static void shunget(struct fscan *f)
{
    if (f->last != EOF) {
        f->n--;
        if (!f->s)
            ungetc(f->last, f->f);
    }
    f->last = 0;
}


static long long scanexp(struct fscan *f, int pok)
{
	int c;
	int x;
	long long y;
	int neg = 0;
	
	c = shgetc(f);
	if (c=='+' || c=='-') {
		neg = (c=='-');
		c = shgetc(f);
		if (c-'0'>=10U && pok) shunget(f);
	}
	if (c-'0'>=10U) {
		shunget(f);
		return LLONG_MIN;
	}
	for (x=0; c-'0'<10U && x<INT_MAX/10; c = shgetc(f))
		x = 10*x + c-'0';
	for (y=x; c-'0'<10U && y<LLONG_MAX/100; c = shgetc(f))
		y = 10*y + c-'0';
	for (; c-'0'<10U; c = shgetc(f));
	shunget(f);
	return neg ? -y : y;
}


static double decfloat(struct fscan *f, int c, int bits, int emin, int sign, int pok)
{
	uint32_t x[KMAX];
	static const uint32_t th[] = { LD_B1B_MAX };
	int i, j, k, a, z;
	long long lrp=0, dc=0;
	long long e10=0;
	int lnz = 0;
	int gotdig = 0, gotrad = 0;
	int rp;
	int e2;
	int emax = -emin-bits+3;
	int denormal = 0;
	double y;
	double frac=0;
	double bias=0;
	static const int p10s[] = { 10, 100, 1000, 10000,
		100000, 1000000, 10000000, 100000000 };

	j=0;
	k=0;

	/* Don't let leading zeros consume buffer space */
	for (; c=='0'; c = shgetc(f)) gotdig=1;
	if (c=='.') {
		gotrad = 1;
		for (c = shgetc(f); c=='0'; c = shgetc(f)) gotdig=1, lrp--;
	}

	x[0] = 0;
	for (; c-'0'<10U || c=='.'; c = shgetc(f)) {
		if (c == '.') {
			if (gotrad) break;
			gotrad = 1;
			lrp = dc;
		} else if (k < KMAX-3) {
			dc++;
			if (c!='0') lnz = dc;
			if (j) x[k] = x[k]*10 + c-'0';
			else x[k] = c-'0';
			if (++j==9) {
				k++;
				j=0;
			}
			gotdig=1;
		} else {
			dc++;
			if (c!='0') {
				lnz = (KMAX-4)*9;
				x[KMAX-4] |= 1;
			}
		}
	}
	if (!gotrad) lrp=dc;

	if (gotdig && (c|32)=='e') {
		e10 = scanexp(f, pok);
		if (e10 == LLONG_MIN) {
			if (pok) {
				shunget(f);
			} else {
				f->fail = 1;
				return 0;
			}
			e10 = 0;
		}
		lrp += e10;
	} else if (c>=0) {
		shunget(f);
	}
	if (!gotdig) {
		errno = EINVAL;
		f->fail = 1;
		return 0;
	}

	/* Handle zero specially to avoid nasty special cases later */
	if (!x[0]) return sign * 0.0;

	/* Optimize small integers (w/no exponent) and over/under-flow */
	if (lrp==dc && dc<10 && (bits>30 || x[0]>>bits==0))
		return sign * (double)x[0];
	if (lrp > -emin/2) {
		errno = ERANGE;
		return sign * DBL_MAX * DBL_MAX;
	}
	if (lrp < emin-2*DBL_MANT_DIG) {
		errno = ERANGE;
		return sign * DBL_MIN * DBL_MIN;
	}

	/* Align incomplete final B1B digit */
	if (j) {
		for (; j<9; j++) x[k]*=10;
		k++;
		j=0;
	}

	a = 0;
	z = k;
	e2 = 0;
	rp = lrp;

	/* Optimize small to mid-size integers (even in exp. notation) */
	if (lnz<9 && lnz<=rp && rp < 18) {
		if (rp == 9) return sign * (double)x[0];
		if (rp < 9) return sign * (double)x[0] / p10s[8-rp];
		int bitlim = bits-3*(int)(rp-9);
		if (bitlim>30 || x[0]>>bitlim==0)
			return sign * (double)x[0] * p10s[rp-10];
	}

	/* Drop trailing zeros */
	for (; !x[z-1]; z--);

	/* Align radix point to B1B digit boundary */
	if (rp % 9) {
		int rpm9 = rp>=0 ? rp%9 : rp%9+9;
		int p10 = p10s[8-rpm9];
		uint32_t carry = 0;
		for (k=a; k!=z; k++) {
			uint32_t tmp = x[k] % p10;
			x[k] = x[k]/p10 + carry;
			carry = 1000000000/p10 * tmp;
			if (k==a && !x[k]) {
				a = (a+1 & MASK);
				rp -= 9;
			}
		}
		if (carry) x[z++] = carry;
		rp += 9-rpm9;
	}

	/* Upscale until desired number of bits are left of radix point */
	while (rp < 9*LD_B1B_DIG || (rp == 9*LD_B1B_DIG && x[a]<th[0])) {
		uint32_t carry = 0;
		e2 -= 29;
		for (k=(z-1 & MASK); ; k=(k-1 & MASK)) {
			uint64_t tmp = ((uint64_t)x[k] << 29) + carry;
			if (tmp > 1000000000) {
				carry = tmp / 1000000000;
				x[k] = tmp % 1000000000;
			} else {
				carry = 0;
				x[k] = tmp;
			}
			if (k==(z-1 & MASK) && k!=a && !x[k]) z = k;
			if (k==a) break;
		}
		if (carry) {
			rp += 9;
			a = (a-1 & MASK);
			if (a == z) {
				z = (z-1 & MASK);
				x[z-1 & MASK] |= x[z];
			}
			x[a] = carry;
		}
	}

	/* Downscale until exactly number of bits are left of radix point */
	for (;;) {
		uint32_t carry = 0;
		int sh = 1;
		for (i=0; i<LD_B1B_DIG; i++) {
			k = (a+i & MASK);
			if (k == z || x[k] < th[i]) {
				i=LD_B1B_DIG;
				break;
			}
			if (x[a+i & MASK] > th[i]) break;
		}
		if (i==LD_B1B_DIG && rp==9*LD_B1B_DIG) break;
		/* FIXME: find a way to compute optimal sh */
		if (rp > 9+9*LD_B1B_DIG) sh = 9;
		e2 += sh;
		for (k=a; k!=z; k=(k+1 & MASK)) {
			uint32_t tmp = x[k] & (1<<sh)-1;
			x[k] = (x[k]>>sh) + carry;
			carry = (1000000000>>sh) * tmp;
			if (k==a && !x[k]) {
				a = (a+1 & MASK);
				i--;
				rp -= 9;
			}
		}
		if (carry) {
			if ((z+1 & MASK) != a) {
				x[z] = carry;
				z = (z+1 & MASK);
			} else x[z-1 & MASK] |= 1;
		}
	}

	/* Assemble desired bits into floating point variable */
	for (y=i=0; i<LD_B1B_DIG; i++) {
		if ((a+i & MASK)==z) x[(z=(z+1 & MASK))-1] = 0;
		y = 1000000000.0 * y + x[a+i & MASK];
	}

	y *= sign;

	/* Limit precision for denormal results */
	if (bits > DBL_MANT_DIG+e2-emin) {
		bits = DBL_MANT_DIG+e2-emin;
		if (bits<0) bits=0;
		denormal = 1;
	}

	/* Calculate bias term to force rounding, move out lower bits */
	if (bits < DBL_MANT_DIG) {
		bias = copysign(scalbn(1, 2*DBL_MANT_DIG-bits-1), y);
		frac = fmod(y, scalbn(1, DBL_MANT_DIG-bits));
		y -= frac;
		y += bias;
	}

	/* Process tail of decimal input so it can affect rounding */
	if ((a+i & MASK) != z) {
		uint32_t t = x[a+i & MASK];
		if (t < 500000000 && (t || (a+i+1 & MASK) != z))
			frac += 0.25*sign;
		else if (t > 500000000)
			frac += 0.75*sign;
		else if (t == 500000000) {
			if ((a+i+1 & MASK) == z)
				frac += 0.5*sign;
			else
				frac += 0.75*sign;
		}
		if (DBL_MANT_DIG-bits >= 2 && !fmod(frac, 1))
			frac += sign;
	}

	y += frac;
	y -= bias;

	if ((e2+DBL_MANT_DIG & INT_MAX) > emax-5) {
		if (fabs(y) >= 2/DBL_EPSILON) {
			if (denormal && bits==DBL_MANT_DIG+e2-emin)
				denormal = 0;
			y *= 0.5;
			e2++;
		}
		if (e2+DBL_MANT_DIG>emax || (denormal && frac))
			errno = ERANGE;
	}

	return scalbn(y, e2);
}

static double hexfloat(struct fscan *f, int bits, int emin, int sign, int pok)
{
	uint32_t x = 0;
	double y = 0;
	double scale = 1;
	double bias = 0;
	int gottail = 0, gotrad = 0, gotdig = 0;
	long long rp = 0;
	long long dc = 0;
	long long e2 = 0;
	int d;
	int c;

	c = shgetc(f);

	/* Skip leading zeros */
	for (; c=='0'; c = shgetc(f)) gotdig = 1;

	if (c=='.') {
		gotrad = 1;
		c = shgetc(f);
		/* Count zeros after the radix point before significand */
		for (rp=0; c=='0'; c = shgetc(f), rp--) gotdig = 1;
	}

	for (; c-'0'<10U || (c|32)-'a'<6U || c=='.'; c = shgetc(f)) {
		if (c=='.') {
			if (gotrad) break;
			rp = dc;
			gotrad = 1;
		} else {
			gotdig = 1;
			if (c > '9') d = (c|32)+10-'a';
			else d = c-'0';
			if (dc<8) {
				x = x*16 + d;
			} else if (dc < DBL_MANT_DIG/4+2) {
				y += d*(scale/=16);
			} else if (d && !gottail) {
				y += 0.5*scale;
				gottail = 1;
			}
			dc++;
		}
	}
	if (!gotdig) {
		shunget(f);
		if (pok) {
			shunget(f);
			if (gotrad) shunget(f);
		} else {
			f->fail = 1;
		}
		return sign * 0.0;
	}
	if (!gotrad) rp = dc;
	while (dc<8) x *= 16, dc++;
	if ((c|32)=='p') {
		e2 = scanexp(f, pok);
		if (e2 == LLONG_MIN) {
			if (pok) {
				shunget(f);
			} else {
				f->fail = 1;
				return 0;
			}
			e2 = 0;
		}
	} else {
		shunget(f);
	}
	e2 += 4*rp - 32;

	if (!x) return sign * 0.0;
	if (e2 > -emin) {
		errno = ERANGE;
		return sign * DBL_MAX * DBL_MAX;
	}
	if (e2 < emin-2*DBL_MANT_DIG) {
		errno = ERANGE;
		return sign * DBL_MIN * DBL_MIN;
	}

	while (x < 0x80000000) {
		if (y>=0.5) {
			x += x + 1;
			y += y - 1;
		} else {
			x += x;
			y += y;
		}
		e2--;
	}

	if (bits > 32+e2-emin) {
		bits = 32+e2-emin;
		if (bits<0) bits=0;
	}

	if (bits < DBL_MANT_DIG)
		bias = copysign(scalbn(1, 32+DBL_MANT_DIG-bits-1), sign);

	/* The bits below x, in y, are a sticky bit for the rounding. When
	 * the rounding keeps 31 bits of x, its lowest bit is the half, so
	 * a sticky bit there would make or hide a tie. Then an odd x with
	 * bits below it rounds up, to x+1. */
	double xd = x;
	if (bits<32 && y) {
		if (bits<31 ? !(x&1) : (x&1)) xd++;
		y = 0;
	}

	y = bias + sign*xd + sign*y;
	y -= bias;

	if (!y) y = sign * 0.0;

	y = scalbn(y, e2);
	if (!y || isinf(y)) errno = ERANGE;
	return y;
}

double __floatscan(struct fscan *f, int prec, int pok)
{
	int sign = 1;
	size_t i;
	int bits;
	int emin;
	int c;

	switch (prec) {
	case 0:
		bits = FLT_MANT_DIG;
		emin = FLT_MIN_EXP-bits;
		break;
	case 1:
		bits = DBL_MANT_DIG;
		emin = DBL_MIN_EXP-bits;
		break;
	case 2:
		bits = DBL_MANT_DIG;
		emin = DBL_MIN_EXP-bits;
		break;
	default:
		return 0;
	}

	while (isspace((c=shgetc(f))));

	if (c=='+' || c=='-') {
		sign -= 2*(c=='-');
		c = shgetc(f);
	}

	for (i=0; i<8 && (c|32)=="infinity"[i]; i++)
		if (i<7) c = shgetc(f);
	if (i==3 || i==8 || (i>3 && pok)) {
		if (i!=8) {
			shunget(f);
			if (pok) for (; i>3; i--) shunget(f);
		}
		return sign * INFINITY;
	}
	if (!i) for (i=0; i<3 && (c|32)=="nan"[i]; i++)
		if (i<2) c = shgetc(f);
	if (i==3) {
		if (shgetc(f) != '(') {
			shunget(f);
			return NAN;
		}
		for (i=1; ; i++) {
			c = shgetc(f);
			if (c-'0'<10U || c-'A'<26U || c-'a'<26U || c=='_')
				continue;
			if (c==')') return NAN;
			shunget(f);
			if (!pok) {
				errno = EINVAL;
				f->fail = 1;
				return 0;
			}
			while (i--) shunget(f);
			return NAN;
		}
		return NAN;
	}

	if (i) {
		shunget(f);
		errno = EINVAL;
		f->fail = 1;
		return 0;
	}

	if (c=='0') {
		c = shgetc(f);
		if ((c|32) == 'x')
			return hexfloat(f, bits, emin, sign, pok);
		shunget(f);
		c = '0';
	}

	return decfloat(f, c, bits, emin, sign, pok);
}

static double strtox(const char *s, char **p, int prec)
{
    struct fscan f = {s, NULL, 0, 0, 0, 0};
    double y = __floatscan(&f, prec, 1);
    if (p)
        *p = (char *)s + (f.fail ? 0 : f.n);
    return y;
}

float strtof(const char *restrict s, char **restrict p)
{
    return (float)strtox(s, p, 0);
}

double strtod(const char *restrict s, char **restrict p)
{
    return strtox(s, p, 1);
}

double atof(const char *s)
{
    return strtod(s, NULL);
}
