// get is imported from env: get(i) = i + 100. It keeps clang from folding
// the calls below at compile time.
int get(int);

// Initialized data, in data segments.
static const char text[] = "Hello, NICE!";
static int table[5] = {3, 1, 4, 1, 5};
// Zero at start-up, so not in a data segment.
static int counter;

// A byte at any offset of the string.
__attribute__((noinline)) int char_at(int i)
{
    return text[i];
}

// table changes, so it is not constant.
__attribute__((noinline)) int bump(int *p)
{
    *p += get(0);
    return *p;
}

// Clang turns this switch into a table of the results in a data segment,
// and an i32.load from it.
__attribute__((noinline)) int lookup(int x)
{
    switch (x) {
    case 0: return 17;
    case 1: return 42;
    case 2: return -5;
    case 3: return 1000;
    case 4: return 7;
    case 5: return 300;
    default: return 0;
    }
}

int main(void)
{
    int r = char_at(get(-100)) + char_at(get(-93));    // 'H' + 'N'
    r += bump(&table[2]) + bump(&table[2]);             // 104 + 204
    r += bump(&counter);                                // 100
    r += lookup(get(-97)) + lookup(get(-98));           // 1000 - 5
    r += lookup(get(-94));                              // 0
    return r;
}
