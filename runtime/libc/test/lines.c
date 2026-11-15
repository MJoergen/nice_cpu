// The line ends of stdin, a text stream: a CR, as the Enter key sends it
// (DEVICES.md §1), is '\n' to fgetc, getchar, fgets, and scanf, and so is
// a CR LF, while nice_getc returns the bytes as they come. The console
// input is test/lines.input:
//
//   "one\rtwo\nthree\r\n\n\rfour\r\n12\r34\rX\rend\r"
//
// fgets reads "one", "two", and "three", each with its '\n', then an empty
// line ended by LF and one ended by CR. getchar reads the 4 bytes of
// "four" up to its '\n'. scanf drops the LF of "four"'s CR LF and reads
// two numbers on two lines, and gives back the '\n' after the second,
// which getchar then reads. nice_getc reads 'X' and a raw CR. fgets reads
// "end", which the CR at the end of the input ends, and then NULL.
// main returns 0.
#include <nice.h>
#include <stdio.h>
#include <string.h>

static void show(const char *s)
{
    putchar('[');
    for (; *s; s++) {
        if (*s == '\n')
            fputs("\\n", stdout);
        else if (*s == '\r')
            fputs("\\r", stdout);
        else
            putchar(*s);
    }
    puts("]");
}

int main(void)
{
    char buf[16];
    for (int i = 0; i < 5; i++) {
        fgets(buf, sizeof buf, stdin);
        show(buf);
    }
    int c, n = 0;
    while ((c = getchar()) != '\n' && c != EOF)
        n++;
    printf("getchar %d\n", n);
    int a, b;
    int k = scanf("%d %d", &a, &b);
    printf("scanf %d %d %d %d\n", k, a, b, getchar());
    int x = nice_getc();
    int y = nice_getc();
    printf("nice_getc %d %d\n", x, y);
    fgets(buf, sizeof buf, stdin);
    show(buf);
    printf("%d\n", fgets(buf, sizeof buf, stdin) == NULL);
    return 0;
}
