#ifndef _STDIO_H
#define _STDIO_H

#include <stdarg.h>
#include <stddef.h>

#define EOF (-1)

typedef struct _FILE FILE;

// The console is the only stream, so stdout and stderr are the same.
extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;

int putchar(int c);
int puts(const char *s);
int getchar(void);
int fputc(int c, FILE *f);
int putc(int c, FILE *f);
int fputs(const char *s, FILE *f);
int fgetc(FILE *f);
int getc(FILE *f);
int ungetc(int c, FILE *f);
char *fgets(char *s, int n, FILE *f);
int fflush(FILE *f);

int printf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
int sprintf(char *buf, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
int snprintf(char *buf, size_t size, const char *fmt, ...)
    __attribute__((format(printf, 3, 4)));
int fprintf(FILE *f, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
int vfprintf(FILE *f, const char *fmt, va_list ap);
int vprintf(const char *fmt, va_list ap);
int vsprintf(char *buf, const char *fmt, va_list ap);
int vsnprintf(char *buf, size_t size, const char *fmt, va_list ap);

int scanf(const char *fmt, ...) __attribute__((format(scanf, 1, 2)));
int sscanf(const char *s, const char *fmt, ...) __attribute__((format(scanf, 2, 3)));
int fscanf(FILE *f, const char *fmt, ...) __attribute__((format(scanf, 2, 3)));
int vfscanf(FILE *f, const char *fmt, va_list ap);
int vscanf(const char *fmt, va_list ap);
int vsscanf(const char *s, const char *fmt, va_list ap);

#endif
