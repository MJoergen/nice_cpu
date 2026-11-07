// The input of __floatscan (floatscan.c): the string s, or the stream f if
// s is NULL, and of that at most lim bytes if lim is not 0. n counts the
// bytes taken, last is the last byte read, and fail is set when the input
// does not begin with a float. prec is 0 for float, 1 for double; pok 1
// lets the float end before a partial "0x", exponent, or the like, as
// strtod does, and pok 0 makes those fail, as scanf does.
#ifndef FLOATSCAN_H
#define FLOATSCAN_H

#include <stdio.h>

struct fscan {
    const char *s;
    FILE *f;
    int lim;
    int n;
    int last;
    int fail;
};

double __floatscan(struct fscan *f, int prec, int pok);

#endif
