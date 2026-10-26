#!/usr/bin/env python3
"""Tile bits left over once every predicted DRP register bit is removed.

Prints the residual bits of each CMT_L sample in the MMCM/PLL area, how
often each is set, and, for the varying ones, the cell property values
that explain them (a property=value set exactly when the bit is).
"""
import collections, json, sys
import drp, regs

regmap = json.load(open("regmap.json"))
AREA = range(0, 2752)      # PLLs and MMCM: frame offsets below the clock row


def covered():
    out = set()
    for slot, m in regmap.items():
        for reg, (f, base) in m.items():
            out |= {(f + k % 2, base + k // 2) for k in range(16)}
    return out


def main():
    cov = covered()
    samples = []
    for spec, r, bits, cells in regs.samples():
        res = {b for b in bits if b[0] < 4 and b[1] in AREA and b not in cov}
        props = {}
        for slot, site in (("MMCM", "MMCM_X0Y%d" % r), ("PLL0", "PLL_X0Y%d" % (2 * r)), ("PLL1", "PLL_X0Y%d" % (2 * r + 1))):
            for k, v in cells[site].items():
                props["%s.%s" % (slot, k)] = v
        samples.append((res, props))
    n = len(samples)
    cnt = collections.Counter(b for s in samples for b in s[0])
    print("%d samples; residual bits: %d always set, %d varying" %
          (n, sum(1 for c in cnt.values() if c == n), sum(1 for c in cnt.values() if c < n)))
    print("always:", " ".join("%02d_%d" % b for b in sorted(b for b, c in cnt.items() if c == n)))
    skip = ("NAME", "HIERARCHICALNAME", "LINE_NUMBER", "ID", "FILE_NAME", "FILE_NAMES")
    for b in sorted(b for b, c in cnt.items() if c < n):
        on = {i for i, s in enumerate(samples) if b in s[0]}
        expl = []
        keys = set().union(*(s[1] for s in samples))
        for k in sorted(keys):
            if k.split(".", 1)[1] in skip:
                continue
            vals = collections.defaultdict(set)
            for i, s in enumerate(samples):
                vals[s[1].get(k)].add(i)
            for v, idx in vals.items():
                if idx == on:
                    expl.append("%s=%s" % (k, v))
                elif idx == set(range(n)) - on:
                    expl.append("!%s=%s" % (k, v))
        print("  %02d_%-5d %3d/%d  %s" % (b[0], b[1], len(on), n, " ".join(expl[:6]) or "?"))


if __name__ == "__main__":
    main()
