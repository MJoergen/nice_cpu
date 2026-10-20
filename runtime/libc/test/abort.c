// abort traps: wasm's unreachable, code 1 (WASM.md). The default handler
// halts with the code in R1, and the emulator exits with status 2. So
// "before" is printed, "after" is not, and R1 = 1.
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    puts("before");
    abort();
    puts("after");
    return 0;
}
