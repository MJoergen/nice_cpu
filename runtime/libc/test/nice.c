// nice.h: the performance counters. The emulator counts one cycle for each
// instruction (ISA.md §8.5), so both counters move by the same amount. main
// returns 0.
#include <nice.h>
#include <stdio.h>

int main(void)
{
    unsigned long long cycles = nice_counter64(NICE_CYCLE_LO);
    unsigned long long instrs = nice_counter64(NICE_INSTR_LO);
    volatile int sum = 0;
    for (int i = 0; i < 100; i++)
        sum += i;
    unsigned long long instrs2 = nice_counter64(NICE_INSTR_LO);
    unsigned long long cycles2 = nice_counter64(NICE_CYCLE_LO);
    printf("%d\n", sum);
    printf("%d\n", instrs2 - instrs > 100);
    printf("%d\n", instrs2 - instrs < 10000);
    printf("%d\n", cycles2 - cycles > instrs2 - instrs);
    printf("%d\n", (unsigned)(instrs2 >> 32) == 0);
    return 0;
}
