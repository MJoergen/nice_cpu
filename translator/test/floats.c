// get is imported from env: get(i) = i + 100. It keeps clang from folding
// the arithmetic at compile time.
int get(int);

// The mean of n doubles, from an array in linear memory.
__attribute__((noinline)) double mean(const double *x, int n)
{
    double s = 0;
    for (int i = 0; i < n; i++)
        s += x[i];
    return s / n;
}

// Newton's method for the square root, in float.
__attribute__((noinline)) float root(float x)
{
    float r = x;
    for (int i = 0; i < 20; i++)
        r = 0.5f * (r + x / r);
    return r;
}

static double data[4] = {1.5, 2.5, 4.0, 8.0};

int main(void)
{
    double a = get(-97) / 2.0;              // 3 / 2 = 1.5
    float b = (float)get(-98) * 0.25f;      // 2 * 0.25 = 0.5
    double c = a * a + b;                   // 2.25 + 0.5 = 2.75
    int r = (int)(c * 1000.0);              // 2750
    r += (int)__builtin_sqrt((double)get(44)); // sqrt(144) = 12
    r += (int)mean(data, get(-96));         // (1.5 + 2.5 + 4 + 8) / 4 = 4
    r += (int)(root(get(-75)) * 100.0f);    // sqrt(25) = 5, so 500
    r += -7.9 < get(-108);                  // -7.9 < -8 is false: 0
    return r;                               // 2750 + 12 + 4 + 500 = 3266
}
