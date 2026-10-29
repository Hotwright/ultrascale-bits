/* A few things every bare-metal KV260 program needs, with no C library. */
#ifndef BM_H
#define BM_H
#include <stdint.h>

/* main's return value lands here; env/kv260_run_bm.sh prints it. */
extern volatile uint32_t bm_exit;

/* The console, UART1 (COM9 on the PC), already set up by the boot firmware.
 * Output also goes to a ring in OCM that kv260_run_bm.sh prints, so nothing
 * is lost when the serial port is closed. */
void bm_putc(char c);
void bm_puts(const char *s);
void bm_printf(const char *fmt, ...); /* %s %-12s %c %d %u %x %08x %p only */

static inline void bm_dsb(void) { __asm__ volatile("dsb sy" ::: "memory"); }
static inline uint32_t bm_rd32(uintptr_t a) { return *(volatile uint32_t *)a; }
static inline void bm_wr32(uintptr_t a, uint32_t v) { *(volatile uint32_t *)a = v; }

void *memset(void *d, int c, unsigned long n);
void *memcpy(void *d, const void *s, unsigned long n);
#endif
