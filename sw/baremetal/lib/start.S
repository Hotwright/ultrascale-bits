// Entry for a bare-metal program on a KV260 A53 core, in OCM, with the MMU
// and caches off, so every access is Device memory. Two ways in:
//   env/kv260_run_bm.sh: JTAG, after `rst -processor`, at EL3;
//   U-Boot (sw/baremetal/README.md): `dcache off; icache off; go`, at EL2.
    .section .text.start, "ax"
    .global _start
_start:
    mrs     x0, CurrentEL           // allow FP/SIMD (q registers) at every EL
    cmp     x0, #(3 << 2)
    b.ne    1f
    msr     cptr_el3, xzr
    b       2f
1:  cmp     x0, #(2 << 2)
    b.ne    2f
    mov     x0, #0x33ff             // CPTR_EL2: RES1 bits, TFP clear
    msr     cptr_el2, x0
2:  mov     x0, #(3 << 20)
    msr     cpacr_el1, x0
    isb
    ldr     x0, =__stack_top
    mov     sp, x0
    ldr     x0, =__bss_start
    ldr     x1, =__bss_end
3:  cmp     x0, x1
    b.hs    4f
    str     xzr, [x0], #8
    b       3b
4:  bl      main
    ldr     x1, =bm_exit
    str     w0, [x1]
    dsb     sy
5:  wfe
    b       5b
