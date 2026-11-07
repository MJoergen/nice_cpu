// In place of musl's features.h, which the *_data.h files include for
// hidden alone (COPYRIGHT).
#ifndef _FEATURES_H
#define _FEATURES_H

#define hidden __attribute__((__visibility__("hidden")))

#endif
