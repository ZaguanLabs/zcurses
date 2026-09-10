/* Independent curses primitive probe. Build against one curses at a time. */
#define _XOPEN_SOURCE 700
#include <curses.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    FILE *report, *control;
    WINDOW *pad;
    char ack[16];
    int wide, result;
    wint_t key = 0;
    if (argc != 4) return 2;
    report = fdopen(atoi(argv[1]), "w");
    control = fdopen(atoi(argv[2]), "r");
    wide = atoi(argv[3]);
    if (!report || !control) return 2;
    setlocale(LC_ALL, "");
    if (!initscr()) return 2;
    cbreak(); noecho();
    pad = newpad(1, 1);
    if (!pad) { endwin(); return 2; }
    keypad(pad, TRUE); wtimeout(pad, 0);
    mvwaddstr(stdscr, 0, 0, "UNPRESENTED_PAD_FRAME");
    wnoutrefresh(stdscr);
    result = wide ? wget_wch(pad, &key) : wgetch(pad);
    if (result != ERR) { endwin(); return 3; }
    fprintf(report, "polled\n"); fflush(report);
    if (!fgets(ack, sizeof(ack), control)) return 4;
    wtimeout(pad, 1000);
    result = wide ? wget_wch(pad, &key) : wgetch(pad);
    if ((wide && (result != OK || key != 'K')) || (!wide && result != 'K')) {
        endwin(); return 5;
    }
    fprintf(report, "read\n"); fflush(report);
    if (!fgets(ack, sizeof(ack), control)) return 4;
    if (doupdate() == ERR) { endwin(); return 6; }
    fprintf(report, "presented\n"); fflush(report);
    if (!fgets(ack, sizeof(ack), control)) return 4;
    delwin(pad); endwin();
    return 0;
}
