// A passing assert is silent. A failing one prints file:line: function:
// Assertion `expression' failed. and then traps like abort, R1 = 1. The
// file name is relative, so the output does not depend on the build directory.
#include <assert.h>
#include <stdio.h>

static_assert(sizeof(int) == 4, "int is 32 bits");

static int check(int x)
{
    assert(x > 0);
    return x;
}

int main(void)
{
    puts("start");
    check(1);
    puts("passed");
    check(-1);
    puts("after");
    return 0;
}
