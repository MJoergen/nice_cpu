// getchar, scanf, and sscanf. The console input is test/scanf.input:
//
//   Hello
//     42 -17 0x1f 077 abc
//   12345,word with spaces;rest
//   x=7 y=oops
//
// main returns 0.
#include <stdio.h>

int main(void)
{
    // getchar up to the end of the first line.
    char line[16];
    int c, k = 0;
    while ((c = getchar()) != '\n')
        line[k++] = (char)c;
    line[k] = '\0';
    printf("[%s] %d\n", line, k);

    int a, b;
    unsigned x, o;
    char w[8];
    int n = scanf("%d %d %x %o %7s", &a, &b, &x, &o, w);
    printf("%d: %d %d %u %u [%s]\n", n, a, b, x, o, w);

    // %3d stops after three digits. The newline that %7s gave back is
    // skipped first.
    char s[32], ch;
    n = scanf("%3d%d,%[^;]%c", &a, &b, s, &ch);
    printf("%d: %d %d [%s] %c\n", n, a, b, s, ch);

    // %*s stores nothing; %n is the number of bytes this call has taken.
    int pos;
    n = scanf("%*s%n", &pos);
    printf("%d %d\n", n, pos);

    // y=%d fails at "oops", which stays in the input.
    n = scanf(" x=%d y=%d", &a, &b);
    printf("%d %d\n", n, a);
    k = 0;
    while (getchar() != EOF)
        k++;
    n = scanf("%d", &a);
    printf("%d %d\n", k, n);

    signed char hh;
    short h;
    long long ll;
    n = sscanf("-5 70000 123456789012 ff", "%hhd %hd %lld %x", &hh, &h, &ll, &x);
    printf("%d: %d %d %lld %u\n", n, hh, h, ll, x);
    printf("%d %d %d\n", sscanf("abc", "%d", &a), sscanf("", "%d", &a), sscanf("  ", "%d", &a));
    n = sscanf("%42", "%%%d", &a);
    printf("%d %d\n", n, a);
    n = sscanf("12abcd", "%d%3c", &a, w);
    printf("%d %d %.3s\n", n, a, w);
    int i;
    n = sscanf("-0x10 010 10", "%i %i %i", &a, &b, &i);
    printf("%d: %d %d %d\n", n, a, b, i);
    char s2[8];
    n = sscanf("abc-def]x", "%[a-c-]%[]def]", s, s2);
    printf("%d [%s] [%s]\n", n, s, s2);
    return 0;
}
