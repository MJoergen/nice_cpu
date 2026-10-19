// A benchmark for code that reaches NICE through wasm (ISA.md §9.4).
//
// Six phases, each a well-known kernel with a known result. Each phase is
// timed with the performance counters of SYSTEM.md §3, and main prints one
// line per phase: the instructions, the cycles, the result, and whether it
// is the expected one. The expected values come from expected.py, which
// computes each phase in Python from the same sizes. The native build,
// "make native", runs the same C on the host as a second check.
//
// The phases, and the translator costs each one isolates:
//
//   rng64      xorshift64* fills a byte buffer and an array of integers.
//              i64 multiplication and shifts, byte stores, word stores.
//   crc32      A table-driven CRC-32 of the buffer. Byte loads, word loads
//              with a computed index, shifts, and xor.
//   bst        The integers go into a binary search tree of static nodes,
//              and a recursive walk hashes it. Loads and stores of struct
//              fields at constant offsets, and calls.
//   heapsort   Sorts the integers in place. Word loads and stores with
//              computed indices, signed comparisons, swaps.
//   vm         A bytecode interpreter runs a small loop. A switch, which
//              is a br_table in wasm, byte fetches, and a word stack.
//   strings    Strings made from the buffer are sorted with strcmp, joined
//              with strcpy, and searched with strstr. Byte accesses through
//              the C library.
//
// The sizes are the defines below. After changing one, run
// "python3 expected.py" and put its values in the EXPECT defines.

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifdef __wasm__
#include <nice.h>
#else
// The native build has no counters. It checks the results only.
static unsigned long long nice_cycles(void) { return 0; }
static unsigned long long nice_instructions(void) { return 0; }
#endif

#define BUF_BYTES 4096  // the byte buffer: filled by rng64, summed by crc32
#define ARR_WORDS 1024  // the integers: filled by rng64, put in the tree, sorted
#define VM_LOOPS 2000   // iterations of the interpreted loop
#define STR_COUNT 64    // the strings, 4 to STR_MAXLEN letters each
#define STR_MAXLEN 12

// From expected.py, for the sizes above.
#define EXPECT_RNG64 0x0E18CD0Au
#define EXPECT_CRC32 0x2DF3B109u
#define EXPECT_BST 0x55A72225u
#define EXPECT_HEAPSORT 0xBDB22882u
#define EXPECT_VM 0x04156880u
#define EXPECT_STRINGS 0xD9867CF6u

#define NOINLINE __attribute__((noinline))

#define FNV_BASIS 0x811C9DC5u
#define FNV_PRIME 16777619u

static uint8_t buf[BUF_BYTES];
static int32_t arr[ARR_WORDS];

// rng64: xorshift64*. The seed is volatile so that clang cannot compute the
// phases at compile time.

static volatile uint64_t seed = 0x9E3779B97F4A7C15ull;
static uint64_t rng_state;

static uint64_t next64(void)
{
    uint64_t x = rng_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    rng_state = x;
    return x * 0x2545F4914F6CDD1Dull;
}

// Fills buf with the bytes of BUF_BYTES / 8 values, least significant byte
// first, and arr with the high words of ARR_WORDS more. Returns the two
// words of the final state, xored.
NOINLINE static uint32_t phase_rng64(void)
{
    rng_state = seed;
    for (int i = 0; i < BUF_BYTES / 8; i++) {
        uint64_t v = next64();
        for (int k = 0; k < 8; k++)
            buf[8 * i + k] = (uint8_t)(v >> (8 * k));
    }
    for (int i = 0; i < ARR_WORDS; i++)
        arr[i] = (int32_t)(next64() >> 32);
    return (uint32_t)(rng_state ^ (rng_state >> 32));
}

// crc32: the usual reflected CRC-32, as zlib computes it. The table is
// built here, so its 256 * 8 steps are part of the phase.

static uint32_t crc_table[256];

NOINLINE static uint32_t phase_crc32(void)
{
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++)
            c = (c & 1) ? (c >> 1) ^ 0xEDB88320u : c >> 1;
        crc_table[i] = c;
    }
    uint32_t crc = 0xFFFFFFFFu;
    for (int i = 0; i < BUF_BYTES; i++)
        crc = crc_table[(crc ^ buf[i]) & 0xFF] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFu;
}

// bst: a binary search tree of the integers, in the order of arr. A key
// that is already there has its count raised. The walk is in order and
// hashes each key with its depth and count.

struct node {
    int32_t key;
    uint32_t count;
    struct node *left;
    struct node *right;
};

static struct node nodes[ARR_WORDS];
static uint32_t nodes_used;

static uint32_t walk(const struct node *n, uint32_t depth, uint32_t h)
{
    if (n == 0)
        return h;
    h = walk(n->left, depth + 1, h);
    h = (h ^ (uint32_t)n->key) * FNV_PRIME + depth * n->count;
    return walk(n->right, depth + 1, h);
}

NOINLINE static uint32_t phase_bst(void)
{
    struct node *root = 0;
    nodes_used = 0;
    for (int i = 0; i < ARR_WORDS; i++) {
        int32_t key = arr[i];
        struct node **link = &root;
        struct node *n = root;
        while (n != 0 && n->key != key) {
            link = key < n->key ? &n->left : &n->right;
            n = *link;
        }
        if (n != 0) {
            n->count++;
        } else {
            n = &nodes[nodes_used++];
            n->key = key;
            n->count = 1;
            n->left = 0;
            n->right = 0;
            *link = n;
        }
    }
    return walk(root, 1, FNV_BASIS);
}

// heapsort: sorts arr in place, as signed integers. The result is an
// FNV-1a hash of the sorted array, or 0 if it is not sorted.

static void sift(int32_t *a, int n, int i)
{
    for (;;) {
        int l = 2 * i + 1;
        if (l >= n)
            return;
        int m = (l + 1 < n && a[l + 1] > a[l]) ? l + 1 : l;
        if (a[m] <= a[i])
            return;
        int32_t t = a[i];
        a[i] = a[m];
        a[m] = t;
        i = m;
    }
}

NOINLINE static uint32_t phase_heapsort(void)
{
    int n = ARR_WORDS;
    for (int i = n / 2 - 1; i >= 0; i--)
        sift(arr, n, i);
    for (int end = n - 1; end > 0; end--) {
        int32_t t = arr[0];
        arr[0] = arr[end];
        arr[end] = t;
        sift(arr, end, 0);
    }
    uint32_t h = FNV_BASIS;
    for (int i = 0; i < n; i++) {
        if (i > 0 && arr[i - 1] > arr[i])
            return 0;
        h = (h ^ (uint32_t)arr[i]) * FNV_PRIME;
    }
    return h;
}

// vm: a stack machine with ten opcodes, each one byte, with its operand in
// the next byte. The program computes acc = (acc * 31) ^ i for i from 0 to
// VM_LOOPS - 1, in cells 1 and 0, with VM_LOOPS in cell 2, and halts with
// acc as the result.

enum { HALT, PUSH, LOAD, STORE, ADD, MUL, XOR, DUP, JNZ, LT };

static const uint8_t vm_prog[] = {
    LOAD, 1, PUSH, 31, MUL, LOAD, 0, XOR, STORE, 1,  // acc = (acc * 31) ^ i
    LOAD, 0, PUSH, 1, ADD, DUP, STORE, 0,            // i = i + 1, and leave i
    LOAD, 2, LT, JNZ, 0,                             // if i < n, go to 0
    HALT
};

NOINLINE static uint32_t phase_vm(void)
{
    uint32_t cells[4] = {0, 0, VM_LOOPS, 0};
    uint32_t stack[16];
    int sp = 0;
    unsigned pc = 0;
    for (;;) {
        uint8_t op = vm_prog[pc++];
        switch (op) {
        case HALT:
            return cells[1];
        case PUSH:
            stack[sp++] = (uint32_t)(int32_t)(int8_t)vm_prog[pc++];
            break;
        case LOAD:
            stack[sp++] = cells[vm_prog[pc++]];
            break;
        case STORE:
            cells[vm_prog[pc++]] = stack[--sp];
            break;
        case ADD:
            sp--;
            stack[sp - 1] += stack[sp];
            break;
        case MUL:
            sp--;
            stack[sp - 1] *= stack[sp];
            break;
        case XOR:
            sp--;
            stack[sp - 1] ^= stack[sp];
            break;
        case DUP:
            stack[sp] = stack[sp - 1];
            sp++;
            break;
        case JNZ: {
            unsigned target = vm_prog[pc++];
            if (stack[--sp] != 0)
                pc = target;
            break;
        }
        case LT:
            sp--;
            stack[sp - 1] = (int32_t)stack[sp - 1] < (int32_t)stack[sp];
            break;
        default:
            return 0;
        }
    }
}

// strings: STR_COUNT strings of lowercase letters, made from the bytes of
// buf, are sorted by insertion with strcmp, joined with strcpy, searched
// for "ab" with strstr, and hashed with FNV-1a. The result combines the
// hash, the total length, and the number of matches.

static char pool[STR_COUNT * (STR_MAXLEN + 1)];
static char *strs[STR_COUNT];
static char joined[STR_COUNT * (STR_MAXLEN + 1)];

NOINLINE static uint32_t phase_strings(void)
{
    char *p = pool;
    for (int j = 0; j < STR_COUNT; j++) {
        const uint8_t *b = buf + 16 * j;
        int len = 4 + b[0] % (STR_MAXLEN - 3);
        strs[j] = p;
        for (int k = 0; k < len; k++)
            p[k] = (char)('a' + b[1 + k] % 26);
        p[len] = 0;
        p += len + 1;
    }
    for (int j = 1; j < STR_COUNT; j++) {
        char *s = strs[j];
        int k = j;
        while (k > 0 && strcmp(strs[k - 1], s) > 0) {
            strs[k] = strs[k - 1];
            k--;
        }
        strs[k] = s;
    }
    char *q = joined;
    uint32_t total = 0;
    for (int j = 0; j < STR_COUNT; j++) {
        strcpy(q, strs[j]);
        size_t len = strlen(q);
        total += (uint32_t)len;
        q += len;
    }
    uint32_t matches = 0;
    for (const char *m = joined; (m = strstr(m, "ab")) != 0; m++)
        matches++;
    uint32_t h = FNV_BASIS;
    for (const char *c = joined; *c != 0; c++)
        h = (h ^ (uint8_t)*c) * FNV_PRIME;
    return h + total * 65599u + matches;
}

// Timing. The instruction counts leave out the reads of the counters, and
// the cycle counts include them.

static unsigned long long start_cycles, start_instructions;
static unsigned long long total_cycles, total_instructions;
static int failures;

static void begin(void)
{
    start_cycles = nice_cycles();
    start_instructions = nice_instructions();
}

static void end(const char *name, uint32_t result, uint32_t expected)
{
    unsigned long long instructions = nice_instructions() - start_instructions;
    unsigned long long cycles = nice_cycles() - start_cycles;
    total_instructions += instructions;
    total_cycles += cycles;
    if (result != expected)
        failures++;
    printf("%-9s %12llu %12llu  %08x  %s\n", name, instructions, cycles, result,
           result == expected ? "ok" : "FAIL");
}

#define RUN(name, phase, expected)        \
    do {                                  \
        begin();                          \
        uint32_t result = phase();        \
        end(name, result, expected);      \
    } while (0)

// Returns the number of phases whose result is wrong.
int main(void)
{
    printf("phase      instructions       cycles  result\n");
    RUN("rng64", phase_rng64, EXPECT_RNG64);
    RUN("crc32", phase_crc32, EXPECT_CRC32);
    RUN("bst", phase_bst, EXPECT_BST);
    RUN("heapsort", phase_heapsort, EXPECT_HEAPSORT);
    RUN("vm", phase_vm, EXPECT_VM);
    RUN("strings", phase_strings, EXPECT_STRINGS);
    printf("%-9s %12llu %12llu\n", "total", total_instructions, total_cycles);
    return failures;
}
