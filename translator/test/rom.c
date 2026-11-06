// Code that runs from a ROM (WASM.md, Code in a ROM), translated with
// --ram. It is linked with --export=__heap_base, so nicewasm reserves the
// memory up to there: the stack, the data segments, and the static data
// that is 0 at the start, which is in no segment.
//
// get is imported from env: get(i) = i + 100. It keeps clang from folding
// the code below at compile time.
int get(int);

// In a data segment.
static int table[4] = {1, 2, 3, 4};
static const char text[] = "ROM";

// Zero at the start, so in no data segment.
static int counts[64];
static int calls;

// Its argument is the address of a local, which clang puts on the stack
// in linear memory, below __stack_pointer.
__attribute__((noinline)) static void bump(int *p, int by)
{
    *p += by;
}

__attribute__((noinline)) static int sum(const int *p, int n)
{
    int s = 0;
    for (int i = 0; i < n; i++)
        s += p[i];
    return s;
}

int main(void)
{
    int local = get(0);
    bump(&local, 5);
    for (int i = 0; i < 64; i++)
        counts[i] += get(i) - 100;
    table[1] += get(10) - 100;
    calls++;
    return local + sum(counts, 64) + sum(table, 4) + text[get(0) - 100] + calls;
}
