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

int main(void)
{
    int r = char_at(get(-100)) + char_at(get(-93));    // 'H' + 'N'
    r += bump(&table[2]) + bump(&table[2]);             // 104 + 204
    r += bump(&counter);                                // 100
    return r;
}
