// stdin, stdout, and stderr, with fgets, fscanf, ungetc, fputs, and
// fprintf. The console input is test/stream.input, with no newline at the
// end:
//
//   first line
//   12 34
//   rest
//
// main returns 0.
#include <stdio.h>

int main(void)
{
    char buf[16];
    // n = 1 reads nothing, stores "", and returns buf, not NULL.
    buf[0] = 'x';
    char *q = fgets(buf, 1, stdin);
    printf("%d %d\n", q == buf, buf[0]);
    fgets(buf, sizeof buf, stdin);
    fputs(buf, stdout);

    int a, b;
    int n = fscanf(stdin, "%d %d", &a, &b);
    fprintf(stdout, "%d %d\n", n, a + b);

    // fscanf gave back the newline. Only one byte can be given back.
    int c = fgetc(stdin);
    int u1 = ungetc('Z', stdin);
    int u2 = ungetc('Y', stdin);
    fprintf(stdout, "%d %d %d\n", c, u1, u2);
    putc(getc(stdin), stdout);
    putc('\n', stdout);

    // n = 4 reads at most three bytes.
    fgets(buf, 4, stdin);
    fprintf(stderr, "%s\n", buf);
    fgets(buf, sizeof buf, stdin);
    fprintf(stdout, "%s\n", buf);
    char *p = fgets(buf, sizeof buf, stdin);
    fprintf(stdout, "%d\n", p == NULL);
    fflush(stdout);
    return 0;
}
