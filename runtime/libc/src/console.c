// The streams stdin, stdout, and stderr, and the character and line
// functions on them, on the console routines of nice.c. There is one
// console, so stdout and stderr are the same stream.
#include <nice.h>
#include <stdio.h>

// back is the byte that ungetc or scanf gave back, for the next read, or
// EOF if there is none. cr is set when the last byte read was a CR.
struct _FILE {
    int back;
    int cr;
};

static FILE in = {EOF, 0};
static FILE out = {EOF, 0};
static FILE err = {EOF, 0};

FILE *stdin = &in;
FILE *stdout = &out;
FILE *stderr = &err;

int fputc(int c, FILE *f)
{
    (void)f;
    nice_putc(c);
    return (unsigned char)c;
}

int putc(int c, FILE *f)
{
    return fputc(c, f);
}

int putchar(int c)
{
    return fputc(c, stdout);
}

int fputs(const char *s, FILE *f)
{
    (void)f;
    nice_print(s);
    return 0;
}

int puts(const char *s)
{
    nice_print(s);
    nice_putc('\n');
    return 0;
}

// Waits for the next input byte. nice_getc returns -1, which is EOF, once
// the line's input has ended. stdin is a text stream, whose line ends C
// lets the library translate (C11 7.21.2): a CR, the Enter key (DEVICES.md
// §1), is '\n', and so is a CR LF. After a CR it does not wait for an LF,
// which a keyboard never sends: the next read drops one.
int fgetc(FILE *f)
{
    int c;
    if (f->back != EOF) {
        c = f->back;
        f->back = EOF;
        return c;
    }
    c = nice_getc();
    if (f->cr && c == '\n')
        c = nice_getc();
    f->cr = c == '\r';
    return f->cr ? '\n' : c;
}

int getc(FILE *f)
{
    return fgetc(f);
}

int getchar(void)
{
    return fgetc(stdin);
}

// Holds one byte only, as C guarantees.
int ungetc(int c, FILE *f)
{
    if (c == EOF || f->back != EOF)
        return EOF;
    f->back = (unsigned char)c;
    return f->back;
}

// NULL only at the end of the input before the first byte, as C says: with
// n = 1 nothing is read, and s becomes "".
char *fgets(char *s, int n, FILE *f)
{
    int k = 0;
    if (n <= 0)
        return NULL;
    while (k < n - 1) {
        int c = fgetc(f);
        if (c == EOF) {
            if (k == 0)
                return NULL;
            break;
        }
        s[k++] = (char)c;
        if (c == '\n')
            break;
    }
    s[k] = '\0';
    return s;
}

int fflush(FILE *f)
{
    (void)f;
    return 0;
}
