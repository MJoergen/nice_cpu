// get is imported from env: get(i) = i + 100. It keeps clang from folding
// the calls below at compile time.
int get(int);

// Zero at start-up, so no data segment.
static unsigned char buf[40];
static short shorts[8];

// Byte stores.
__attribute__((noinline)) void fill(unsigned char *p, int n, int x)
{
    for (int i = 0; i < n; i++)
        p[i] = x + i;
}

// Byte loads.
__attribute__((noinline)) unsigned sum(const unsigned char *p, int n)
{
    unsigned s = 0;
    for (int i = 0; i < n; i++)
        s += p[i];
    return s;
}

// An i32 load from any byte address.
__attribute__((noinline)) unsigned word_at(const unsigned char *p)
{
    unsigned w;
    __builtin_memcpy(&w, p, 4);
    return w;
}

// Signed 16-bit loads and stores.
__attribute__((noinline)) int shorts_sum(short *p, int n, int x)
{
    int s = 0;
    for (int i = 0; i < n; i++)
        p[i] = x - get(0);
    for (int i = 0; i < n; i++)
        s += p[i];
    return s;
}

int main(void)
{
    fill(buf, 40, get(-90));
    unsigned r = sum(buf, 40);
    r ^= word_at(buf + get(-95));
    r += shorts_sum(shorts, get(-92), get(-300));
    return r;
}
