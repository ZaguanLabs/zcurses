/* Unicode 17 extended grapheme boundaries (UAX #29 revision 47).
 * Original zdraw implementation; distributed under the same license as zdraw.c.
 * The generated property table carries the separate Unicode data license.
 * This streaming engine also handles controls; text queries validate their
 * printable subset and suppress boundaries inside native zero-width units.
 */
#include "zdraw_grapheme_data.h"

struct zdraw_grapheme_state {
    int started, previous, ri_odd, pictographic, zwj_pictographic, indic;
};

static unsigned int
zdraw_grapheme_props(unsigned int point)
{
    unsigned int lo = 0, hi = sizeof(zdraw_grapheme_ranges) / sizeof(zdraw_grapheme_ranges[0]);
    while (lo < hi) {
        unsigned int mid = lo + (hi - lo) / 2;
        const struct zdraw_grapheme_range *range = &zdraw_grapheme_ranges[mid];
        if (point < range->first) hi = mid;
        else if (point > range->last) lo = mid + 1;
        else return range->props;
    }
    return 0;
}

/* Consume one Unicode scalar; return whether it starts a new cluster.
 * Only parity and finite suffix states are retained, even for long sequences. */
static int
zdraw_grapheme_break(struct zdraw_grapheme_state *state, unsigned int point)
{
    unsigned int props = zdraw_grapheme_props(point);
    int next = props & 15, ep = !!(props & 16), incb = props >> 5;
    int prev = state->previous, boundary = 1;
    if (!state->started) boundary = 1;                              /* GB1 */
    else if (prev == ZDG_CR && next == ZDG_LF) boundary = 0;         /* GB3 */
    else if (prev == ZDG_CR || prev == ZDG_LF || prev == ZDG_Control ||
             next == ZDG_CR || next == ZDG_LF || next == ZDG_Control) boundary = 1;
    else if (prev == ZDG_L && (next == ZDG_L || next == ZDG_V ||
             next == ZDG_LV || next == ZDG_LVT)) boundary = 0;      /* GB6 */
    else if ((prev == ZDG_LV || prev == ZDG_V) &&
             (next == ZDG_V || next == ZDG_T)) boundary = 0;        /* GB7 */
    else if ((prev == ZDG_LVT || prev == ZDG_T) && next == ZDG_T) boundary = 0;
    else if (next == ZDG_Extend || next == ZDG_ZWJ || next == ZDG_SpacingMark)
        boundary = 0;                                             /* GB9/9a */
    else if (prev == ZDG_Prepend) boundary = 0;                     /* GB9b */
    else if (incb == 1 && state->indic == 2) boundary = 0;           /* GB9c */
    else if (ep && prev == ZDG_ZWJ && state->zwj_pictographic) boundary = 0;
    else if (prev == ZDG_Regional_Indicator && next == ZDG_Regional_Indicator &&
             state->ri_odd) boundary = 0;                          /* GB12/13 */
    state->zwj_pictographic = next == ZDG_ZWJ && state->pictographic;
    if (ep) state->pictographic = 1;
    else if (next != ZDG_Extend) state->pictographic = 0;
    if (incb == 1) state->indic = 1;
    else if (incb == 3 && state->indic) state->indic = 2;
    else if (incb != 2) state->indic = 0;
    state->ri_odd = next == ZDG_Regional_Indicator ? !state->ri_odd : 0;
    state->previous = next;
    state->started = 1;
    return boundary;
}
