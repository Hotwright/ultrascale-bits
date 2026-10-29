// Entry for a bare-metal program on a KV260 A53 core, loaded into OCM by
// env/kv260_run_bm.sh after `rst -processor`: the core starts at EL3 with
// the MMU and caches off, so every access is Device memory.
    .section .text.start, "ax"
    .global _start
_start:
    msr     cptr_el3, xzr           // allow FP/SIMD (q registers)
    mov     x0, #(3 << 20)
    msr     cpacr_el1, x0
    isb
    ldr     x0, =__stack_top
    mov     sp, x0
    ldr     x0, =__bss_start
    ldr     x1, =__bss_end
1:  cmp     x0, x1
    b.hs    2f
    str     xzr, [x0], #8
    b       1b
2:  bl      main
    ldr     x1, =bm_exit
    str     w0, [x1]
    dsb     sy
3:  wfe
    b       3b
