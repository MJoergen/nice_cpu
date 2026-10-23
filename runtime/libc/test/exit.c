// exit halts with its status in R1, and the emulator exits with status 0.
// "before" is printed, "after" is not, and R1 = 3.
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    puts("before");
    exit(3);
    puts("after");
    return 0;
}
