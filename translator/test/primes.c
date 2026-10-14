// get is imported from env: get(i) = i + 100. It keeps clang from
// computing the count at compile time.
int get(int);

#define LIMIT 1000

// composite[i] is set when i is not a prime. It is zero at the start, as
// it is not in a data segment.
static unsigned char composite[LIMIT + 1];

// The sieve of Eratosthenes: the number of primes up to n, for n <= LIMIT.
__attribute__((noinline)) int count_primes(int n)
{
    int count = 0;
    for (int i = 2; i <= n; i++) {
        if (composite[i])
            continue;
        count++;
        for (int j = i * i; j <= n; j += i)
            composite[j] = 1;
    }
    return count;
}

int main(void)
{
    return count_primes(get(LIMIT - 100)); // 168 primes up to 1000
}
