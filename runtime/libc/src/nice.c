// The functions of nice.h that are not wasm imports.
#include <nice.h>

unsigned long long nice_counter64(unsigned lo)
{
    unsigned low = nice_peek(lo);
    return (unsigned long long)nice_peek(lo + 1) << 32 | low;
}
