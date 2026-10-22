#include "parallel.h"

void print(const char *s) {
    while (*s)
        sync_write(SYNC_PUTCHAR, *s++);
}

void println(const char *s) {
    print(s);
    sync_write(SYNC_PUTCHAR, '\n');
}

void print_int(int v) {
    char buf[12];
    int i = 0;
    unsigned u = v < 0 ? -(unsigned)v : (unsigned)v;
    if (v < 0)
        sync_write(SYNC_PUTCHAR, '-');
    do {
        buf[i++] = '0' + u % 10;
        u /= 10;
    } while (u);
    while (i)
        sync_write(SYNC_PUTCHAR, buf[--i]);
}

void print_hex(unsigned v) {
    print("0x");
    for (int s = 28; s >= 0; s -= 4)
        sync_write(SYNC_PUTCHAR, "0123456789abcdef"[(v >> s) & 0xf]);
}

// The compiler may emit calls to these for struct copies and array zeroing
void *memset(void *d, int c, unsigned n) {
    unsigned char *p = d;
    while (n--)
        *p++ = c;
    return d;
}

void *memcpy(void *d, const void *s, unsigned n) {
    unsigned char *p = d;
    const unsigned char *q = s;
    while (n--)
        *p++ = *q++;
    return d;
}
