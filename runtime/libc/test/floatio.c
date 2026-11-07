// The float conversions of printf and scanf, and strtod, strtof, and atof.
// The console input is test/floatio.input:
//
//   3.25e1 -0x1.8p1
//   1e+z
//
// main returns 0.
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    // Ties round to even, in decimal as in hex: 0.5, 2.5, and 0.25 are
    // exact, 1.5 is 0x1.8, and 1.96875 is 0x1.f8.
    printf("[%.0f] [%.0f] [%.1f] [%.0a] [%.1a]\n", 0.5, 2.5, 0.25, 1.5, 1.96875);
    // %g takes %e's form when the exponent is below -4 or not below the
    // precision, and drops the zeros at the end.
    printf("[%.2e] [%.3g] [%g] [%g] [%g]\n", 12345.0, 0.0001234, 1e-5, 123456789.0, 100000.0);
    // The alternate forms keep the point, and %#g its zeros. 999.5 rounds
    // to 1.00e+03, whose exponent 3 is not below the precision 3.
    printf("[%#.0f] [%#g] [%#.0e] [%#.3g]\n", 3.0, 1.0, 5.0, 999.5);
    printf("[%+.3f] [% f] [%08.2f] [%-8.1f|] [%+010.3e]\n", 3.14159, 1.0, -3.14159, 2.5, 12.5);
    // Infinity and NaN ignore 0, and -0 keeps its sign.
    double inf = __builtin_inf(), nan = __builtin_nan("");
    printf("[%f] [%F] [%e] [%5.1f] [%-6f|] [%06f] [%+g]\n", inf, -inf, nan, -0.0, inf, -inf, 0.0);
    // %a: 1.0, -1.25 * 2^3, 0, the smallest subnormal, which musl prints
    // as 0x1p-1074, and 0.1, 0x1.999999999999ap-4, rounded up.
    printf("[%a] [%A] [%a] [%a] [%.3a]\n", 1.0, -10.0, 0.0, 5e-324, 0.1);
    // Exact decimals: 10^22 is a double, 0.1 is not.
    printf("[%.0f] [%.20g] [%.17g] [%e] [%.3e]\n", 1e22, 0.1, 0.1, 1.7976931348623157e308, 5e-324);

    char *end;
    double d = strtod(" -1.5e3xyz", &end);
    printf("%g [%s]", d, end);
    d = strtod("0x1.8p1", &end);
    printf(" %g [%s]", d, end);
    // A partial exponent or "0x" ends the float before it.
    d = strtod("1e+", &end);
    printf(" %g [%s]", d, end);
    d = strtod("0xg", &end);
    printf(" %g [%s]\n", d, end);
    const char *abc = "abc";
    d = strtod(abc, &end);
    printf("%g %d", d, end == abc);
    d = strtod("infinity", &end);
    printf(" %g [%s]", d, end);
    d = strtod("-inf", &end);
    printf(" %g [%s]", d, end);
    d = strtod("nan(1)x", &end);
    printf(" %g [%s]\n", d, end);
    // 1 + 2^-53, halfway between 1 and the next double, rounds to even;
    // a bit more rounds up. Then the smallest subnormal.
    printf("%a %a %a\n", strtod("1.00000000000000011102230246251565404236316680908203125", NULL),
           strtod("1.000000000000000111022302462515654042363166809082031251", NULL),
           strtod("4.9406564584124654e-324", NULL));
    errno = 0;
    d = strtod("1e400", NULL);
    printf("%g %d", d, errno);
    errno = 0;
    d = strtod("-1e-400", NULL);
    printf(" %g %d\n", d, errno);
    // FLT_MAX, and the float nearest 0.1, printed as a double.
    printf("%.9g %a %g\n", strtof("3.4028235e38", NULL), strtof("0.1", NULL), atof("2.5"));

    float f;
    double g, h;
    int n = sscanf("1.5 -2e-3 0x10p0", "%f %lf %le", &f, &g, &h);
    printf("%d: %g %g %g\n", n, f, g, h);
    // A width cuts the float, and the rest is the next one.
    n = sscanf("123.456", "%4lf%lf", &g, &h);
    printf("%d: %g %g\n", n, g, h);
    n = sscanf("nan inf -INFINITY", "%lf %lf %f", &g, &h, &f);
    printf("%d: %g %g %g\n", n, g, h, f);
    n = sscanf("1.5 2.5", "%*f %lf", &g);
    printf("%d: %g\n", n, g);

    // From the console. "1e+" before a letter is a matching failure, as C
    // says, and the letter stays in the input.
    n = scanf("%lf %f", &g, &f);
    printf("%d: %g %g\n", n, g, f);
    n = scanf("%lf", &g);
    printf("%d %c\n", n, getchar());
    return 0;
}
