#!/usr/bin/env python3
"""Check drp.registers() against every sample, register by register.

Each register sits at a frame pair f/f+1 and 8 offsets base..base+7 (bit k
at frame f + k % 2, offset base + k // 2). The location of every register is
taken from solution.json (solve_drp.py), checked to be consistent across its
solved bits, then all 16 bits of every register are compared in every
sample. Prints the register map and the mismatches; --unconnected also
checks counters whose output is not connected.
"""
import collections, json, os, re, sys
import drp, regs, solve_drp

LOCK23 = {"MMCM": {"LOCK2": (0, 2072), "LOCK3": (0, 2080)},
          "PLL0": {"LOCK2": (0, 152), "LOCK3": (0, 160)},
          "PLL1": {"LOCK2": (0, 824), "LOCK3": (0, 832)}}


def field_reg_bits(kind):
    """feature -> (register, bit) by toggling one field bit at a time."""
    base = drp.fields(kind, {"CLKFBOUT_MULT_F": "10", "CLKFBOUT_MULT": "10"})
    out = {}
    orig = drp.fields
    for feat in base:
        def patched(k, p, feat=feat):
            f = orig(k, p)
            f[feat] ^= 1
            return f
        drp.fields = patched
        a = drp.registers(kind, {"CLKFBOUT_MULT_F": "10", "CLKFBOUT_MULT": "10"})
        drp.fields = orig
        b = drp.registers(kind, {"CLKFBOUT_MULT_F": "10", "CLKFBOUT_MULT": "10"})
        for r in a:
            if a[r] != b[r]:
                out[feat] = (r, (a[r] ^ b[r]).bit_length() - 1)
    return out


def main():
    unconnected = "--unconnected" in sys.argv
    solution = json.load(open("solution.json"))
    maps = {}
    for slot, kind in (("MMCM", "MMCM"), ("PLL0", "PLL"), ("PLL1", "PLL")):
        frb = field_reg_bits(kind)
        loc = collections.defaultdict(set)
        for feat, (k, v, n) in solution[slot].items():
            if k != "bit" or feat not in frb:
                continue
            fr, off = map(int, v.lstrip("!").split("_"))
            reg, bit = frb[feat]
            loc[reg].add((fr - bit % 2, off - bit // 2))
        m = {}
        for reg, ls in sorted(loc.items()):
            if len(ls) != 1:
                print("%s %s: inconsistent %s" % (slot, reg, sorted(ls)))
            m[reg] = min(ls)
        # LOCK2/LOCK3: their varying fields (LockFBDly, LockRefDly) are always
        # equal, so the solve cannot place them; the constant low ten bits
        # can (UnlockCnt 0x001 in LOCK2, LockSatHigh 0x3E9 in LOCK3).
        m.update(LOCK23[slot])
        maps[slot] = m
        print("%s: %s" % (slot, " ".join("%s=%02d_%d" % (r, f, b) for r, (f, b) in sorted(m.items(), key=lambda x: x[1]))))
    bad = collections.Counter()
    total = collections.Counter()
    for spec, r, bits, cells in regs.samples():
        for slot, kind, site in (("MMCM", "MMCM", "MMCM_X0Y%d" % r), ("PLL0", "PLL", "PLL_X0Y%d" % (2 * r)),
                                 ("PLL1", "PLL", "PLL_X0Y%d" % (2 * r + 1))):
            p = cells[site]
            pred = drp.registers(kind, p)
            for reg, (f, base) in maps[slot].items():
                c = reg.split(".")[0]
                if not unconnected and not solve_drp.connected(p, c) and c.startswith("CLKOUT"):
                    continue
                act = regs.reg(bits, f, base)
                total[slot, reg] += 1
                if act != pred[reg]:
                    bad[slot, reg] += 1
                    if bad[slot, reg] <= 2:
                        print("  %s %s r%d %s %s: got %04x want %04x" % (os.path.basename(spec), slot, r, site, reg,
                                                                      act, pred[reg]))
    print("mismatching registers: %d of %d checks" % (sum(bad.values()), sum(total.values())))
    for k, v in sorted(bad.items()):
        print("  %s %s: %d / %d" % (k[0], k[1], v, total[k]))
    json.dump({s: {r: list(l) for r, l in m.items()} for s, m in maps.items()}, open("regmap.json", "w"), indent=1)


if __name__ == "__main__":
    main()
