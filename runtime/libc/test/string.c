// string.h and ctype.h. main returns strlen("Hello, NICE!"), 12.
#include <ctype.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    char a[32] = "Hello";
    printf("%zu %zu\n", strlen(a), strnlen(a, 3));
    strcat(a, ", NICE");
    strncat(a, "!!!", 1);
    printf("[%s]\n", a);
    printf("%d %d %d %d\n", strcmp("abc", "abd") < 0, strcmp("abc", "abc"),
           strncmp("abcx", "abcy", 3), strcmp("\xff", "a") > 0);
    printf("[%s] [%s]\n", strchr(a, 'l'), strrchr(a, 'l'));
    printf("[%s] %d %d\n", strstr(a, "NI"), strstr(a, "xyz") == NULL, strchr(a, 'q') == NULL);

    char b[8];
    strncpy(b, "ab", sizeof b);
    printf("%d\n", b[7]);
    memset(b, 'x', 7);
    b[7] = '\0';
    printf("[%s]\n", b);
    memcpy(b + 1, "123", 3);
    printf("[%s]\n", b);
    memmove(b + 2, b + 1, 5);
    printf("[%s]\n", b);
    const char *h = "hello";
    printf("%d %d\n", memcmp("abc", "abd", 3) < 0, (int)((const char *)memchr(h, 'l', 5) - h));

    printf("%d%d%d%d%d%d %c%c\n", isdigit('7') != 0, isalpha('7') != 0, isspace('\t') != 0,
           isxdigit('F') != 0, ispunct('!') != 0, isalnum('_') != 0, toupper('q'), tolower('Q'));
    return (int)strlen(a);
}
