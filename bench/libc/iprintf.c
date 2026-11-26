/* iprintf with %d alone, whose size runtime/README.md quotes (make words). */
#include <stdio.h>

int main(void) {
    volatile int x = 12;
    iprintf("%d\n", x);
    return 0;
}
