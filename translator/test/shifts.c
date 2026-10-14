// get is imported from env: get(i) = i + 100. It keeps clang from folding
// the calls below at compile time.
int get(int);

static const unsigned char digits[] = "123456789";

// The bitwise CRC-32 of IEEE 802.3. The CRC of "123456789" is the
// standard check value 0xCBF43926.
__attribute__((noinline)) unsigned crc32(const unsigned char *p, int n)
{
    unsigned crc = 0xFFFFFFFF;
    for (int i = 0; i < n; i++) {
        crc ^= p[i];
        for (int k = 0; k < 8; k++)
            crc = (crc >> 1) ^ (0xEDB88320 & -(crc & 1));
    }
    return ~crc;
}

// Clang turns this into i32.rotl.
__attribute__((noinline)) unsigned rotl(unsigned x, int n)
{
    return (x << (n & 31)) | (x >> (-n & 31));
}

// i64.shl, then i64.shr_s.
__attribute__((noinline)) long long shift64(long long x, int l, int r)
{
    return (x << l) >> r;
}

int main(void)
{
    unsigned r = crc32(digits, get(-91));               // 0xCBF43926
    r ^= rotl(get(-99), get(-69));                      // 1 rotl 31 = 0x80000000
    r += (unsigned)shift64(get(-99), get(-60), get(-63));  // 1 << 40 >> 37 = 8
    r += (unsigned)shift64(get(-101), get(-60), get(-60)); // -1 << 40 >> 40 = -1
    return r;
}
