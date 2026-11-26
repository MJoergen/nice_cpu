/* sscanf with %d alone, whose size runtime/README.md quotes (make words). */
#include <stdio.h>

int main(void) {
    int x;
    return sscanf("12", "%d", &x);
}
