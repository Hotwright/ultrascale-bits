#include <stdarg.h>
#include "bm.h"

#define UART1 0xFF010000u
#define UART_SR 0x2C
#define UART_FIFO 0x30
#define SR_TXFULL (1u << 4)

volatile uint32_t bm_exit __attribute__((section(".data"))) = 0xFFFFFFFFu;

/* Read back by kv260_run_bm.sh: the symbol's address comes from the ELF. */
char bm_log[8192];
volatile uint32_t bm_log_len;

void bm_putc(char c)
{
    if (bm_log_len < sizeof bm_log)
        bm_log[bm_log_len++] = c;
    if (c == '\n')
        bm_putc('\r');
    for (int i = 0; i < 100000 && (bm_rd32(UART1 + UART_SR) & SR_TXFULL); i++)
        ;
    bm_wr32(UART1 + UART_FIFO, (uint8_t)c);
}

void bm_puts(const char *s)
{
    while (*s)
        bm_putc(*s++);
}

static void num(unsigned long v, unsigned base, int width, char pad)
{
    char b[24];
    int n = 0;
    do {
        b[n++] = "0123456789abcdef"[v % base];
        v /= base;
    } while (v);
    while (n < width--)
        bm_putc(pad);
    while (n)
        bm_putc(b[--n]);
}

void bm_printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    for (; *fmt; fmt++) {
        if (*fmt != '%') {
            bm_putc(*fmt);
            continue;
        }
        char pad = ' ';
        int width = 0, left = 0;
        if (*++fmt == '-')
            left = 1, fmt++;
        if (*fmt == '0')
            pad = '0', fmt++;
        while (*fmt >= '0' && *fmt <= '9')
            width = width * 10 + *fmt++ - '0';
        switch (*fmt) {
        case 's': {
            const char *str = va_arg(ap, const char *);
            int n = 0;
            while (str[n])
                n++;
            for (; !left && n < width; width--)
                bm_putc(' ');
            bm_puts(str);
            for (; left && n < width; width--)
                bm_putc(' ');
            break;
        }
        case 'c': bm_putc((char)va_arg(ap, int)); break;
        case 'd': {
            int v = va_arg(ap, int);
            if (v < 0)
                bm_putc('-'), v = -v;
            num((unsigned)v, 10, width, pad);
            break;
        }
        case 'u': num(va_arg(ap, unsigned), 10, width, pad); break;
        case 'x': num(va_arg(ap, unsigned), 16, width, pad); break;
        case 'p': bm_puts("0x"); num((unsigned long)va_arg(ap, void *), 16, 0, ' '); break;
        default: bm_putc(*fmt); break;
        }
    }
    va_end(ap);
}

/* Byte-wise: the MMU is off, so all memory is Device and must not see
 * unaligned accesses. */
void *memset(void *d, int c, unsigned long n)
{
    volatile char *p = d;
    while (n--)
        *p++ = (char)c;
    return d;
}

void *memcpy(void *d, const void *s, unsigned long n)
{
    volatile char *p = d;
    const volatile char *q = s;
    while (n--)
        *p++ = *q++;
    return d;
}
