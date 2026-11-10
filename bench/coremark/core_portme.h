/*
Copyright 2018 Embedded Microprocessor Benchmark Consortium (EEMBC)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Original Author: Shay Gal-on
*/
/* The port of CoreMark to NICE, from barebones/core_portme.h, built by
   clang for wasm32, translated by nicewasm, and run on the C library of
   runtime/libc (bench/README.md, CoreMark). Built for the host, with
   make native, it is the same program on the host's C library, as a
   check of the CRCs. */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stddef.h>

/* The seconds and the iterations per second are printed as doubles, by
   the C library's printf. */
#define HAS_FLOAT  1
#define HAS_TIME_H 0
#define USE_CLOCK  0
#define HAS_STDIO  1
#define HAS_PRINTF 1

/* The ticks are the cycle counter of SYSTEM.md §3, so a second is the
   clock of the board, 100 MHz unless NICE_CLOCK_HZ says otherwise. On
   the host they are those of clock(). */
#ifdef __wasm__
#ifndef NICE_CLOCK_HZ
#define NICE_CLOCK_HZ 100000000
#endif
#define EE_TICKS_PER_SEC NICE_CLOCK_HZ
#else
#include <time.h>
#define EE_TICKS_PER_SEC CLOCKS_PER_SEC
#endif

#ifndef COMPILER_VERSION
#ifdef __wasm__
#define COMPILER_VERSION __VERSION__ ", wasm32, through nicewasm"
#else
#define COMPILER_VERSION __VERSION__
#endif
#endif
#ifndef COMPILER_FLAGS
#define COMPILER_FLAGS FLAGS_STR
#endif
#ifndef MEM_LOCATION
#define MEM_LOCATION "STATIC"
#endif

/* Pointers are 32 bits in wasm32, and on most hosts 64. */
typedef signed short   ee_s16;
typedef unsigned short ee_u16;
typedef signed int     ee_s32;
typedef double         ee_f32;
typedef unsigned char  ee_u8;
typedef unsigned int   ee_u32;
typedef size_t         ee_ptr_int;
typedef size_t         ee_size_t;
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x)-1) & ~3))

/* A run of 2^32 ticks or more, 42.9 seconds at 100 MHz, does not fit
   CORE_TICKS. get_time then says so, and the CoreMark/MHz line, which
   keeps all 64 bits, is still right. */
#define CORETIMETYPE unsigned long long
typedef ee_u32 CORE_TICKS;

/* The seeds and the iterations are read from the console by
   portable_init into the volatile variables. */
#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD  MEM_STATIC

#define MULTITHREAD       1
#define USE_PTHREAD       0
#define USE_FORK          0
#define USE_SOCKET        0
#define MAIN_HAS_NOARGC   1
#define MAIN_HAS_NORETURN 0

extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S
{
    ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

#endif /* CORE_PORTME_H */
