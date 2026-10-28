#ifndef _ERRNO_H
#define _ERRNO_H

// One errno for the program: there are no threads.
extern int errno;
#define errno errno

#define EDOM 33
#define ERANGE 34
#define EILSEQ 84

#endif
