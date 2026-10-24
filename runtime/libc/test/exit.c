// exit halts with its status in R1, and the emulator exits with status 0.
// "before" and "0 1", EXIT_SUCCESS and EXIT_FAILURE, are printed, "after"
// is not, and R1 = 3.
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    puts("before");
    printf("%d %d\n", EXIT_SUCCESS, EXIT_FAILURE);
    exit(3);
    puts("after");
    return 0;
}
