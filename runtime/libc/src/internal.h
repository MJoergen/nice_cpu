// Shared by the library's own files only.
#ifndef _LIBC_INTERNAL_H
#define _LIBC_INTERNAL_H

// A byte that scanf read too far and gave back, for the next getchar, or
// EOF if there is none.
extern int __stdin_back;

#endif
