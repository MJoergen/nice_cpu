/* printf with %d alone, whose size runtime/README.md quotes (make words). */
#include <stdio.h>

int main(void) {
    volatile int x = 12;
    printf("%d\n", x);
    return 0;
}
