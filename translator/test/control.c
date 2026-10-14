// get is imported from env: get(i) = i + 100. It keeps clang from folding
// the calls below at compile time.
int get(int);

// Euclid's algorithm by subtraction.
__attribute__((noinline)) unsigned gcd(unsigned a, unsigned b)
{
    while (a != b) {
        if (a > b)
            a -= b;
        else
            b -= a;
    }
    return a;
}

// Each case does something different, so that clang cannot turn the
// switch into a table in linear memory, which nicewasm does not support
// yet.
__attribute__((noinline)) int sw(int x, int y)
{
    switch (x) {
    case 0: return get(y);
    case 1: return y - get(3);
    case 2: return y ^ 0x55;
    case 4: return gcd(y, 6);
    default: return y + x;
    }
}

__attribute__((noinline)) unsigned long long fib(int n)
{
    unsigned long long a = 0, b = 1;
    for (int i = 0; i < n; i++) {
        unsigned long long t = a + b;
        a = b;
        b = t;
    }
    return a;
}

int main(void)
{
    int r = gcd(get(971), get(362));
    r += sw(get(-100), 1) + sw(get(-99), 20) + sw(get(-98), 0x0F) + sw(get(-96), 9)
         + sw(get(-103), 30);
    if (fib(get(-40)) == 1548008755920ULL)
        r += 1000;
    return r;
}
