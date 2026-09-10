#include <stdio.h>
#include "../../Src/Modules/zdraw_grapheme.h"
int main(void)
{
    unsigned int cp;
    int expected, first = 1;
    struct zdraw_grapheme_state state = {0};
    while (scanf("%x %d", &cp, &expected) == 2) {
        if (cp == 0xffffffffU) {
            struct zdraw_grapheme_state empty = {0};
            state = empty;
            first = 1;
        } else {
            int actual = zdraw_grapheme_break(&state, cp);
            if (actual != expected) {
                fprintf(stderr, "U+%04X: expected %d got %d (first=%d)\n", cp, expected, actual, first);
                return 1;
            }
            first = 0;
        }
    }
    return ferror(stdin) ? 1 : 0;
}
