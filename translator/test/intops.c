// get is imported from env: get(i) = i + 100. It keeps clang from folding
// the calls below at compile time.
int get(int);

// Euclid's algorithm with %.
__attribute__((noinline)) unsigned gcd(unsigned a, unsigned b)
{
    while (b) {
        unsigned t = a % b;
        a = b;
        b = t;
    }
    return a;
}

// The decimal digits of a 64-bit number, summed: / and % on long long.
__attribute__((noinline)) int digit_sum(unsigned long long n)
{
    int s = 0;
    while (n) {
        s += n % 10;
        n /= 10;
    }
    return s;
}

// Signed division and long long multiplication.
__attribute__((noinline)) long long scale(long long x, int num, int den)
{
    return x * num / den;
}

int main(void)
{
    int r = gcd(get(1971), get(1171));                  // gcd(2071, 1271) = 1
    r += digit_sum(18446744073709551615ULL / get(-97)); // digits of 6148914691236517205
    r += (int)scale(get(-1100), get(-93), get(-97));    // -1000 * 7 / 3 = -2333
    r += __builtin_clz(get(-99)) + __builtin_ctzll(1ULL << get(-60)); // 31 + 40
    r += __builtin_popcount(get(155));                  // popcount(255) = 8
    r += (signed char)get(28);                          // (signed char)128 = -128
    return r;
}
