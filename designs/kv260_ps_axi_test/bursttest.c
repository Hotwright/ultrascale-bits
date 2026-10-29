/* PS-side burst test for axi.v. One source, two ways to run it:
 *   under Linux:  sw/build.sh linux bursttest bursttest.c; sudo ./bursttest
 *   bare metal:   sw/build.sh baremetal bursttest.elf bursttest.c
 *                 env/kv260_run_bm.sh bursttest.elf
 * Each access is issued by one A53 instruction against /dev/mem (Device
 * memory); the PL slave's counters at 0x20-0x2C then say how many AXI
 * transactions it took and the longest AxLEN/AxSIZE seen. The clear write
 * zeroes them after it is counted, so it is not in AW; reading them is itself
 * one 128-bit read, counted in AR. The expected counts are what the A53
 * issues to Device memory (bare metal, MMU off): ld1 x4 goes out as 8 reads
 * and stp q as 2 writes; only ldp q is one burst. */
#include <stdint.h>
#ifdef __linux__
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#else
#include "bm.h"
#define printf bm_printf
#define fflush(f) ((void)0)
#endif

static volatile uint32_t *p;
static int fails;

static void step(const char *s) { printf("> %s\n", s); fflush(stdout); }

static void clear(void) { step("clear counters (32-bit write)"); p[8] = 0; __asm__ volatile("dsb sy" ::: "memory"); }

static void counters(const char *what, unsigned exp_aw, unsigned exp_ar)
{
    uint32_t c[4] __attribute__((aligned(16))); /* str q: Device memory when bare */
    step("read counters (ldr q)");
    __asm__ volatile("dsb sy; ldr q0, [%1]; str q0, [%0]; dsb sy"
                     :: "r"(c), "r"(p + 8) : "v0", "memory");
    unsigned aw = c[0], ar = c[1] - 1; /* less this read */
    printf("%-34s AW %u (len %u size %u)  AR %u (len %u size %u)%s\n", what,
           aw, c[2] & 0xff, (c[2] >> 8) & 7, ar, c[3] & 0xff, (c[3] >> 8) & 7,
           (exp_aw == ~0u || (aw == exp_aw && ar == exp_ar)) ? "" : "   <-- unexpected count");
}

static void check(const char *what, uint32_t got, uint32_t exp)
{
    if (got != exp) { printf("FAIL %s: %08x, expected %08x\n", what, got, exp); fails++; }
}

int main(void)
{
#ifdef __linux__
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("/dev/mem"); return 1; }
    p = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0xA0000000);
    if (p == MAP_FAILED) { perror("mmap"); return 1; }
    setvbuf(stdout, NULL, _IONBF, 0);
#else
    p = (volatile uint32_t *)0xA0000000; /* MMU off: Device memory already */
#endif
    step("read ID (32-bit)");
    check("ID", p[4], 0xC0DE0A51);
    uint32_t w[16] __attribute__((aligned(16))), r[16] __attribute__((aligned(16)));
    for (int i = 0; i < 16; i++) w[i] = 0x01020304u * (i + 1) ^ 0xa5a5a5a5u;

    clear();
    step("access");
    __asm__ volatile("ldr q0, [%0]; str q0, [%1]; dsb sy" :: "r"(w), "r"(p) : "v0", "memory");
    counters("str q (16 B)", 1, 0);
    memset(r, 0, sizeof r);
    clear();
    step("access");
    __asm__ volatile("ldr q0, [%0]; str q0, [%1]; dsb sy" :: "r"(p), "r"(r) : "v0", "memory");
    counters("ldr q (16 B)", 0, 1);
    for (int i = 0; i < 4; i++) check("ldr q lane", r[i], w[i]);

    clear();
    step("access");
    __asm__ volatile("ldp q0, q1, [%0]; stp q0, q1, [%1]; dsb sy" :: "r"(p), "r"(r) : "v0", "v1", "memory");
    counters("ldp q (32 B)", 0, 1);
    for (int i = 0; i < 4; i++) check("ldp q line 0", r[i], w[i]);
    check("ldp q line 1 ID", r[4], 0xC0DE0A51);

    clear();
    step("access");
    __asm__ volatile("ld1 {v0.16b, v1.16b, v2.16b, v3.16b}, [%0]; st1 {v0.16b, v1.16b, v2.16b, v3.16b}, [%1]; dsb sy"
                     :: "r"(p), "r"(r) : "v0", "v1", "v2", "v3", "memory");
    counters("ld1 x4 (64 B)", 0, 8);
    check("ld1 line 0", r[0], w[0]);
    check("ld1 line 1 ID", r[4], 0xC0DE0A51);
    check("ld1 line 3", r[12], 0xDEAD0030);

    clear();
    step("access");
    __asm__ volatile("ldp q0, q1, [%0]; stp q0, q1, [%1]; dsb sy" :: "r"(w + 8), "r"(p) : "v0", "v1", "memory");
    counters("stp q (32 B)", 2, 0);
    check("stp q r0 after", p[0], w[8]);
    check("stp q r3 after", p[3], w[11]);

    clear();
    step("memcpy");
    uint32_t big[256] __attribute__((aligned(16)));
    memcpy(big, (const void *)p, sizeof big);
    __asm__ volatile("" :: "r"(big) : "memory"); /* keep the whole copy */
    counters("memcpy 1 KiB from PL", ~0u, ~0u);
    check("memcpy ID", big[4], 0xC0DE0A51);
    check("memcpy line 3", big[12], 0xDEAD0030);

    printf(fails ? "FAIL (%d)\n" : "PASS\n", fails);
    return fails != 0;
}
