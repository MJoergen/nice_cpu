# The error bound of SCALE10

This is the proof of the bounds that [DEVICES.md §11.3](../DEVICES.md#113-commands)
states for `SCALE10` beyond k = 22, for #181 and #167. It takes the
sequence of §11.3 as `emulator/test/fpu_model.py` computes it:
`scale10()` and `mul_pair()`.

## 1. The claim

Let Y be a finite nonzero binary64 value, X a whole number with
23 ≤ k = |X| ≤ 650, x = Y · 10^X exactly, and 2^E ≤ |x| < 2^(E+1). Let
r be the result of `SCALE10`, and q = 2^−1074. If r is finite:

1. For X > 0: |r − x| ≤ (0.5 + 2^−46) ulp(x).
2. For X < 0 and E ≥ −1021: |r − x| ≤ (0.5 + 1.5 · 2^(−1022−E) + 2^−46) ulp(x).
3. For X < 0 and E ≤ −1022: |r − x| ≤ (1.5 + 2^−46) q, and
   (2.5 + 2^−46) q if r > 2^−1021.

Here ulp(x) = 2^(max(E, −1022) − 52), so it is q for E ≤ −1022.

## 2. Notation and the rules of rounding

u = 2^−53. RN is rounding to nearest, ties to even, with the subnormals
of binary64. Every binary64 value is a multiple of q. For a real v:

- (R1) If |RN(v)| ≥ 2^−1022, then |RN(v) − v| ≤ u|v|.
- (R2) Otherwise, |RN(v) − v| ≤ q/2.
- (R3) A multiple of q below 2^−1021 is a binary64 value, as the
  spacing there is q. So (R2) gives an error only for a v that is not a
  multiple of q, and a sum of two binary64 values below 2^−1021 is exact.
- (R4) Fast2Sum: if a and b are binary64 values with |a| ≥ |b|, and
  h = RN(a + b), then h − a is exact, and so is b − (h − a). This holds
  with subnormals too.

A pair (h, l) is normalized if |l| ≤ ulp(h)/2. Then |l| ≤ u|h| when h is
normal, and l = 0 when h is subnormal, since l is a multiple of q.

## 3. The table

The pair of 10^m, for m = ±2^i, is hi = RN(10^m) and lo = RN(10^m − hi).
|10^m − hi| ≤ ulp(hi)/2, and ulp(hi)/2 is a power of 2, so |lo| ≤ ulp(hi)/2
and the pair is normalized. All the parts are normal: the smallest,
the low part of 10^−256, is near 10^−273. So

    |hi + lo − 10^m| ≤ ulp(lo)/2 ≤ u|lo| ≤ u²|hi|,

and the pair's value is 10^m · (1 + τ) with |τ| ≤ u²(1 + u).

For m > 0 both parts are whole numbers: a whole number rounds to a
whole number, as binary64 values from 2^53 on are all whole. So hi is
whole, then 10^m − hi, and then lo.

A script checked these statements on the table of the model.

## 4. One product

`mul_pair` computes, from the normalized pairs a = (a_h, a_l) and
b = (b_h, b_l), with P = |a_h · b_h|:

    p  = RN(a_h · b_h)
    e  = RN(a_h · b_h − p)        the fma
    t1 = RN(e + RN(a_h · b_l))
    t2 = RN(t1 + RN(a_l · b_h))
    h  = RN(p + t2)
    l  = RN(t2 − RN(h − p))

**The sum h + l is exactly p + t2.** If p is normal, |t2| ≤ 3.01 u P + 1.5q
is far below |p|, so (R4) applies: h − p and l are exact. If p is
subnormal, all of p, t2, h, and h − p are below 2^−1021, and the sums
are exact by (R3).

**The error of p + t2.** The exact product is

    a · b = a_h b_h + a_h b_l + a_l b_h + a_l b_l,

and p + t2 differs from it by the errors of the four roundings after p,
and by a_l b_l, which is left out. With (R1) for each rounding:

| Term | Bound of its size | Bound of its error |
|---|---|---|
| a_h b_h − p | u P | |
| RN(a_h b_l) | u P (1 + u) | u² P |
| e + RN(a_h b_l), rounded to t1 | u P (2 + u) | u² P (2 + u) |
| RN(a_l b_h) | u P (1 + u) | u² P |
| t1 + RN(a_l b_h), rounded to t2 | u P (3 + 3u) | u² P (3 + 3u) |
| a_l b_l, left out | u² P | u² P |

The sizes use |a_l| ≤ u|a_h| and |b_l| ≤ u|b_h|. The fma is exact under
(R1): its exact value a_h b_h − p is a multiple of ulp(a_h) · ulp(b_h)
smaller than ulp(p)/2, so it has at most 52 significant bits, and it is
a binary64 value when it is at least 2^−1022.

The sum is 8u²P(1 + u). As |a · b| ≥ P(1 − u)², the product is

    p + t2 = a · b · (1 + η) + ζ,   |η| ≤ 8u²(1 + 3u),

where ζ holds the errors that (R2) gives in place of (R1): at most three,
the fma, RN(a_h b_l), and RN(a_l b_h), each up to q/2. The two sums
have no such error, by (R3): a sum below 2^−1022 is exact. So
|ζ| ≤ 1.5q, plus the growth of the sums' rounding errors by u · 1.5q,
which the 2^−46 below covers.

**The result is normalized.** h = RN(p + t2) and l = p + t2 − h, so
|l| ≤ ulp(h)/2.

## 5. The chain

r starts as (Y, 0), which is normalized. The sequence makes m products,
with one pair of the table each: the bits of k from 0 to 8, then bit 9
as two products with the pair of 10^±256. k ≤ 650 gives m ≤ 9: below
512 at most the nine bits 0 to 8, and from 512 to 650, k − 512 ≤ 138, at
most seven bits of 0 to 7 and two products for bit 9.

With the errors of §3 and §4, after the last product

    h + l = x · Π(1 + τ_j)(1 + η_j) + Σ ζ_j · (the factors after product j),

so with m ≤ 9,

    |h + l − x| ≤ ((1 + 1.001u²)⁹ (1 + 8.001u²)⁹ − 1) |x| + |ζ_m| + Σ_{j<m} |ζ_j| · F_j
               ≤ 81.1 u² |x| + |ζ_m| + 9 · 1.5q · 1.0001 · 10^−16.

F_j bounds the product of the factors after product j. For X < 0 every
factor is below 1, and the last is at most 10^−16: k ≥ 23 has a bit of
4 or higher, and the last product is by its highest bit. The factors
are the pairs' values times (1 + η), so F_j ≤ 1.0001 · 10^−16.

**For X > 0, every ζ is 0.** The parts of the table are whole numbers
(§3), so a_h b_h, a_h b_l, and a_l b_h are multiples of q, and so is
the fma's exact value. By (R3) none of them rounds by (R2). So

    |h + l − x| ≤ 81.1 u² |x|.

**For X < 0, |ζ_m| ≤ 1.5q.** So

    |h + l − x| ≤ 81.1 u² |x| + 1.5q + 1.4 · 10^−15 q.

Call this bound δ.

## 6. The final sum

The result is r = RN(h + l) = RN(p + t2) = h.

**Case 1 and case 2, E ≥ −1021.** ulp(x) ≥ 2q, and δ < 2q ≤ ulp(x). If
h + l is in the binade of x, |r − x| ≤ ulp(x)/2 + δ. If h + l is in the
binade above, that is h + l ≥ 2^(E+1) > x, then
h + l < 2^(E+1) + ulp(x), as δ < ulp(x), so r = 2^(E+1), and
|r − x| ≤ h + l − x ≤ δ. If h + l is in the binade below, whose spacing
is ulp(x)/2, |r − x| ≤ ulp(x)/4 + δ. In each case

    |r − x| ≤ ulp(x)/2 + δ.

81.1 u² |x| < 81.1 · 2^−53 ulp(x) < 9.1 · 10^−15 ulp(x), and q ≤ ulp(x)/2,
so the small terms are below 2^−46 ulp(x) = 1.42 · 10^−14 ulp(x). With
1.5q = 1.5 · 2^(−1022−E) ulp(x) for X < 0, and nothing for X > 0, that is
claims 1 and 2.

For X > 0, x ≥ 2^−1074 · 10^23 > 2^−1000, so claim 1 covers every finite
result.

**Case 3, X < 0 and E ≤ −1022.** ulp(x) = q, and h + l is a multiple
of q.

- If h + l < 2^−1021, it is a binary64 value by (R3), so r = h + l and
  |r − x| ≤ δ ≤ (1.5 + 2^−46) q, as 81.1 u² |x| < 81.1 · 2^−53 q.
- If h + l ≥ 2^−1021 > x, then h + l ≤ x + δ < 2^−1021 + 1.6q, so r is
  2^−1021 or 2^−1021 + 2q. If r = 2^−1021, |r − x| ≤ h + l − x ≤ δ. If
  r = 2^−1021 + 2q, h + l ≥ 2^−1021 + q, so x ≥ 2^−1021 + q − δ, and
  |r − x| ≤ q + δ ≤ (2.5 + 2^−46) q.

That is claim 3.

## 7. How close the samples come

A search of the model in exact arithmetic, on 2026-11-15: 480,000
samples with a negative k and x in the binades from 2^−1030 to 2^−1015,
or anywhere, or with a positive k and a subnormal or small Y; and
320,000 with x just below 2^−1021, which reach the few values of Y
for each k whose x falls there. The worst error in each binade,
beside the bound:

| E | Worst | Bound |
|---|---|---|
| ≤ −1023 | 1.10 q | 1.5 q |
| −1022 | 1.48 q | 1.5 q |
| −1021 | 1.21 ulp | 1.25 ulp |
| −1020 | 0.86 ulp | 0.875 ulp |
| −1019 | 0.68 ulp | 0.6875 ulp |
| −1018 | 0.58 ulp | 0.59375 ulp |
| −1017 | 0.54 ulp | 0.546875 ulp |
| −1016 | 0.519 ulp | 0.5234 ulp |
| −1015 | 0.510 ulp | 0.5117 ulp |
| −1014 | 0.502 ulp | 0.5059 ulp |
| from −1013 on, and every X > 0 | below 0.5 ulp | 0.5 ulp and less than 0.003 more |

So the term of the underflow, 1.5q, is reached within a few percent.
No sample's result rounded up past 2^−1021, so the 2.5q of case 3 was
not seen; the samples there reached 1.31q.

The model's test, `scale10_check` in `emulator/test/fpu_model_test.py`,
checks the bounds on the five worst cases of the table, for E = −1019
and below, and on 4500 random samples, of which 1500 are aimed at the
lowest binades and at a positive k with a subnormal Y. The worst cases
make it fail with a bound a few percent too tight: 1.4q in place of
1.5q, either in case 3 or in the term of the underflow of case 2, and
0.49 in place of 0.5.

## 8. What it means for 15 digits

§11.3 says that a constant of up to 15 digits comes back while each
conversion is within 1.126 ulp. `DIGITS` scales |X| to a D below 10^15,
so its `SCALE10` has a result above 2^−969, within 0.5 + 2^−46 ulp. The
read, `FROMBCD` and then `SCALE10`, is within 0.875 + 2^−46 ulp for a
value from 2^−1020 up. So every such constant from 2^−1020 up, about
8.9 · 10^−308, comes back. Below that, the bound is 1.25 ulp or more,
and the proof does not cover it.
