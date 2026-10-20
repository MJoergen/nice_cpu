// The corners of string.h and ctype.h that test/string.c leaves out:
// memmove both ways, memset and memchr with a value above 255, bytes above
// 0x7F, which compare as unsigned char, n = 0, strchr and strrchr of the
// terminator, strstr with an empty needle or haystack, strncpy without a
// terminator, and each ctype class over all of EOF and 0 to 255. main
// returns 0.
#include <ctype.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    char b[12];
    strcpy(b, "abcdefgh");
    memmove(b, b + 2, 5);       // down: cdefg, then fgh stays
    printf("[%s]\n", b);
    strcpy(b, "abcdefgh");
    memmove(b + 2, b, 5);       // up: ab, then abcde, then h stays
    printf("[%s]\n", b);
    memset(b, 0x141, 3);        // only the low byte counts: 'A'
    memcpy(b + 3, "xy", 0);     // n = 0 changes nothing
    printf("[%s]\n", b);

    printf("%d %d %d %d %d %d\n", memcmp("\x80", "\x7f", 1) > 0, strncmp("a\xe9", "aA", 2) > 0,
           strcmp("\xe9", "\x7f") > 0, strcmp("", ""), strcmp("ab", "abc") < 0,
           memcmp("abc", "abd", 2) + strncmp("abc", "abd", 0));

    const char *s = "hello", *e = "", *a = "aaab";
    printf("%d %d %d %d\n", (int)(strchr(s, '\0') - s), (int)(strrchr(s, '\0') - s),
           (int)(strchr(s, 'l' + 256) - s), strrchr(s, 'z') == NULL);
    printf("%d %d\n", (int)((const char *)memchr(s, 'o' + 256, 5) - s), memchr(s, 'o', 4) == NULL);
    printf("%d %d %d %d %d\n", strstr(s, "") == s, strstr(e, "") == e, strstr(e, "a") == NULL,
           (int)(strstr(s, "lo") - s), (int)(strstr(a, "aab") - a));

    memset(b, '#', sizeof b);
    strncpy(b, "abcdef", 3);    // no terminator
    printf("%c%c%c%c\n", b[0], b[1], b[2], b[3]);
    strncpy(b, "", 4);          // four 0s
    printf("%d %d %c\n", b[0], b[3], b[4]);
    strcat(b, "");
    strncat(b, "xyz", 10);
    printf("[%s] %zu %zu %zu %zu\n", b, strlen(b), strnlen(b, 10), strlen(""), strnlen("abc", 0));

    int count[11] = {0}, up = 0, down = 0;
    for (int c = -1; c < 256; c++) {
        count[0] += isdigit(c) != 0;
        count[1] += islower(c) != 0;
        count[2] += isupper(c) != 0;
        count[3] += isalpha(c) != 0;
        count[4] += isalnum(c) != 0;
        count[5] += isxdigit(c) != 0;
        count[6] += isspace(c) != 0;
        count[7] += iscntrl(c) != 0;
        count[8] += isprint(c) != 0;
        count[9] += isgraph(c) != 0;
        count[10] += ispunct(c) != 0;
        up += toupper(c) != c;
        down += tolower(c) != c;
    }
    for (int i = 0; i < 11; i++)
        printf("%d ", count[i]);
    printf("%d %d %c%c\n", up, down, toupper('z'), tolower('A'));
    return 0;
}
