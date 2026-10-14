// get is imported from env and defined in sum5.asm: get(i) = i + 100. So
// main returns 101 + 102 - 103 + 104 * 105 = 11020. sum5 takes its fifth
// argument on the stack, and the * calls __mul.
int get(int);

__attribute__((noinline)) int sum5(int a, int b, int c, int d, int e)
{
    return a + b - c + d * e;
}

int main(void)
{
    return sum5(get(1), get(2), get(3), get(4), get(5));
}
