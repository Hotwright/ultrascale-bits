#!/usr/bin/env python3
"""Bare-metal A53 burst test for axi.v, through xsdb (no Linux needed).

Assembles a short AArch64 program (keystone-engine), and writes an xsdb Tcl
script that puts it in OCM, runs it on Cortex-A53 #0 from a processor reset
(EL3, MMU off: the PL is Device-nGnRnE memory) and prints, for each access,
the slave's transaction counters and the data read.

    bursttest_bm.py > bm.tcl && env/kv260_xsdb.sh < bm.tcl

Each test: clear the counters (one 32-bit write to 0x20), the access, then
one 128-bit read of the counters into the result buffer. So every snapshot
counts that clear (AW) and the snapshot read itself (AR) once.
"""
from keystone import Ks, KS_ARCH_ARM64, KS_MODE_LITTLE_ENDIAN

CODE, RES, PAT = 0xFFFC0000, 0xFFFC1000, 0xFFFC2000
TESTS = [
    ("str w  (4 B)",   "str w9, [x0]"),
    ("str q  (16 B)",  "str q4, [x0]"),
    ("ldr q  (16 B)",  "ldr q0, [x0]"),
    ("ldp q  (32 B)",  "ldp q0, q1, [x0]"),
    ("ld1 x4 (64 B)",  "ld1 {v0.16b, v1.16b, v2.16b, v3.16b}, [x0]"),
    ("stp q  (32 B)",  "stp q5, q4, [x0]"),
    ("st1 x4 (64 B, to 0x40)", "st1 {v4.16b, v5.16b, v6.16b, v7.16b}, [x3]"),
    ("ldp x  (16 B)",  "ldp x10, x11, [x0]"),
]


def program():
    a = ["msr cptr_el3, xzr", "isb",
         "movz x0, #0xa000, lsl #16",
         "movz x1, #0x%x" % (RES & 0xffff), "movk x1, #0x%x, lsl #16" % (RES >> 16),
         "movz x2, #0x%x" % (PAT & 0xffff), "movk x2, #0x%x, lsl #16" % (PAT >> 16),
         "add x3, x0, #0x40",
         "ld1 {v4.16b, v5.16b, v6.16b, v7.16b}, [x2]",
         "ldr w9, [x2]"]
    for _, acc in TESTS:
        a += ["str wzr, [x0, #0x20]", "dsb sy", acc, "dsb sy",
              "ldr q16, [x0, #0x20]", "str q16, [x1], #16",
              "st1 {v0.16b, v1.16b, v2.16b, v3.16b}, [x1], #64"]
    a += ["movz x12, #0x600d", "str x12, [x1]", "dsb sy", "b ."]
    enc, _ = Ks(KS_ARCH_ARM64, KS_MODE_LITTLE_ENDIAN).asm("; ".join(a))
    return bytes(enc)


def main():
    code = program()
    words = [int.from_bytes(code[i:i + 4], "little") for i in range(0, len(code), 4)]
    pat = [(0x01010101 * (i + 1)) ^ 0xa5000000 for i in range(16)]
    t = ['targets -set -nocase -filter {name =~ "Cortex-A53 #0" && jtag_cable_serial =~ "XFL11V5BMUH4*"}',
         "catch {stop}", "rst -processor", "after 200",
         "mwr -force 0x%x {%s}" % (CODE, " ".join("0x%08x" % w for w in words)),
         "mwr -force 0x%x {%s}" % (PAT, " ".join("0x%08x" % w for w in pat)),
         "mwr -force 0x%x 0 %d" % (RES, len(TESTS) * 20 + 2),
         "rwr pc 0x%x" % CODE, "con", "after 1000", "catch {stop}",
         "proc rd {a} { return [mrd -force -value $a] }",
         "set r 0x%x" % RES]
    for i, (name, _) in enumerate(TESTS):
        t.append('set c [mrd -force -value [expr $r + %d] 4]' % (i * 80))
        t.append('set d [mrd -force -value [expr $r + %d] 16]' % (i * 80 + 16))
        t.append('puts [format "%%-24s AW %%u len %%u size %%u | AR %%u len %%u size %%u | data %%s" {%s} '
                 '[expr [lindex $c 0]-1] [expr [lindex $c 2]&0xff] [expr ([lindex $c 2]>>8)&7] '
                 '[expr [lindex $c 1]-1] [expr [lindex $c 3]&0xff] [expr ([lindex $c 3]>>8)&7] '
                 '[join [lmap x [lrange $d 0 7] {format %%08x $x}] " "]]' % name)
    t.append('puts [format "end marker 0x%%x  pc %%s" [rd [expr $r + %d]] [rrd pc]]' % (len(TESTS) * 80))
    t.append('puts "r0..r3 now: [lmap x [mrd -force -value 0xA0000000 4] {format %08x $x}]"')
    print("\n".join(t))


if __name__ == "__main__":
    main()
