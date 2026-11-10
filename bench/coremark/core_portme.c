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
/* The port of CoreMark to NICE, from barebones/core_portme.c
   (core_portme.h, and bench/README.md, CoreMark). */
#include <stdlib.h>
#include "coremark.h"
#include "core_portme.h"
#ifdef __wasm__
#include <nice.h>
#endif

/* The seeds and the iterations, which portable_init reads from the
   console before main reads them here. Seed 5, the algorithms to run,
   stays 0, which means all three. */
volatile ee_s32 seed1_volatile = 0;
volatile ee_s32 seed2_volatile = 0;
volatile ee_s32 seed3_volatile = 0;
volatile ee_s32 seed4_volatile = 0;
volatile ee_s32 seed5_volatile = 0;

/* The ticks: the cycle counter on NICE, clock() on the host. */
static CORETIMETYPE
read_ticks(void)
{
#ifdef __wasm__
    return nice_cycles();
#else
    return (CORETIMETYPE)clock();
#endif
}

static CORETIMETYPE start_time_val, stop_time_val;

void
start_time(void)
{
    start_time_val = read_ticks();
}

void
stop_time(void)
{
    stop_time_val = read_ticks();
}

/* The ticks of the last run, which must fit 32 bits. */
CORE_TICKS
get_time(void)
{
    CORETIMETYPE elapsed = stop_time_val - start_time_val;
    if (elapsed >> 32)
    {
        ee_printf("ERROR! %llu ticks do not fit CORE_TICKS!\n", elapsed);
    }
    return (CORE_TICKS)elapsed;
}

secs_ret
time_in_secs(CORE_TICKS ticks)
{
    return (secs_ret)ticks / (secs_ret)EE_TICKS_PER_SEC;
}

ee_u32 default_num_contexts = 1;

/* Reads seeds 1 to 3 and the iterations from the console, as C integers
   in decimal or hexadecimal: 0 0 0x66 for the performance run, 0x3415
   0x3415 0x66 for the validation run, and 0 iterations for the run of 10
   seconds or more that CoreMark times itself. Without four numbers, or
   with fewer than 0 iterations, it says so and exits with 1. */
void
portable_init(core_portable *p, int *argc, char *argv[])
{
    int s1 = 0, s2 = 0, s3 = 0, iterations = -1;

    (void)argc;
    (void)argv;
    if (scanf("%i %i %i %i", &s1, &s2, &s3, &iterations) != 4
        || iterations < 0)
    {
        ee_printf(
            "ERROR! Give seeds 1 to 3 and the iterations on the console, "
            "such as 0 0 0x66 0\n");
        exit(1);
    }
    seed1_volatile = s1;
    seed2_volatile = s2;
    seed3_volatile = s3;
    seed4_volatile = iterations;

    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *))
    {
        ee_printf(
            "ERROR! Please define ee_ptr_int to a type that holds a "
            "pointer!\n");
    }
    if (sizeof(ee_u32) != 4)
    {
        ee_printf("ERROR! Please define ee_u32 to a 32b unsigned type!\n");
    }
    p->portable_id = 1;
}

/* On NICE, prints the cycles of one iteration and the iterations per
   million cycles, CoreMark/MHz, with three decimals in integer
   arithmetic, from all 64 bits of the cycles. p is the port of
   results[0] in main, which holds the iterations. */
void
portable_fini(core_portable *p)
{
#ifdef __wasm__
    core_results *r
        = (core_results *)((char *)p - offsetof(core_results, port));
    unsigned long long cycles = stop_time_val - start_time_val;
    unsigned long long n      = r->iterations;

    if (n > 0 && cycles > 0)
    {
        unsigned long long milli = 1000000000ull * n / cycles;
        ee_printf("Cycles/iteration : %llu\n", cycles / n);
        ee_printf("CoreMark/MHz     : %llu.%03llu\n", milli / 1000, milli % 1000);
    }
#endif
    p->portable_id = 0;
}
