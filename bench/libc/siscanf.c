/* siscanf with %d alone, whose size runtime/README.md quotes (make words). */
#include <stdio.h>

int main(void) {
    int x;
    return siscanf("12", "%d", &x);
}
