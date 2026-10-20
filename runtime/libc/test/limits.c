// Arguments at the edges of their ranges, in the printf family, malloc,
// and strtoul. main returns 0.
//
// C17 7.21.6.5: if snprintf's size is 0, nothing is written, and the
// buffer may be a null pointer. So snprintf(NULL, 0, ...) only measures:
// it returns 5 and prints nothing.
//
// malloc(0xFFFFFFF0) cannot be met in 64 KB, so it returns NULL.
//
// strtoul negates the value of a number with a minus sign in unsigned
// long, so "-4294967295" is -(2^32 - 1) = 1 mod 2^32. Only a value above
// ULONG_MAX gives ULONG_MAX.
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    int n = snprintf(NULL, 0, "%d", 12345);
    printf("[%d]\n", n);
    printf("%d\n", malloc(0xFFFFFFF0u) == NULL);
    printf("%lu\n", strtoul("-4294967295", NULL, 10));
    return 0;
}
