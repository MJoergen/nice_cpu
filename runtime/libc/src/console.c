// The streams stdin, stdout, and stderr, and the character and line
// functions on them, on the console routines of nice.c. There is one
// console, so stdout and stderr are the same stream.
#include <nice.h>
#include <stdio.h>

// back is the byte that ungetc or scanf gave back, for the next read, or
// EOF if there is none.
struct _FILE {
    int back;
};

static FILE in = {EOF};
static FILE out = {EOF};
static FILE err = {EOF};

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
// the emulator's input has ended.
int fgetc(FILE *f)
{
    if (f->back != EOF) {
        int c = f->back;
        f->back = EOF;
        return c;
    }
    return nice_getc();
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

char *fgets(char *s, int n, FILE *f)
{
    int k = 0;
    while (k < n - 1) {
        int c = fgetc(f);
        if (c == EOF)
            break;
        s[k++] = (char)c;
        if (c == '\n')
            break;
    }
    if (k == 0)
        return NULL;
    s[k] = '\0';
    return s;
}

int fflush(FILE *f)
{
    (void)f;
    return 0;
}
