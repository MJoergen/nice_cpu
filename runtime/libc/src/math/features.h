// In place of musl's features.h, which libm.h includes for hidden alone
// (COPYRIGHT).
#ifndef _FEATURES_H
#define _FEATURES_H

#define hidden __attribute__((__visibility__("hidden")))

#endif
