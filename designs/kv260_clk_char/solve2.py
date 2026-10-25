#!/usr/bin/env python3
"""CMT_L re-solve with the root as a feature.

Per CMT_L instance (one per clock-region row of column X1), features are:
  XING<k>        the HROUTE<k> crossing (Y180 only: the PS's row)
  HD<k>.LOCAL    HDISTR<k> used in this row by a clock rooted in X1<row>
  HD<k>.REMOTE   HDISTR<k> used in this row by a clock rooted elsewhere
The HDISTR track of a clock in a row comes from its RCLK_INT_L leaf pips.
"""
import collections, glob, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import solve, ctx

ROWS = {"CMT_L_X16Y0": (0, 29), "CMT_L_X16Y60": (1, 89), "CMT_L_X16Y120": (2, 149), "CMT_L_X16Y180": (3, 209)}

def instances():
    grid = json.load(open(os.path.join(solve.PART_DIR, "tilegrid.json")))
    out = []
    for s in sorted(glob.glob(os.path.join(solve.HERE, "build", "specimen_*"))):
        if not os.path.exists(os.path.join(s, "roots.txt")):
            continue
        fr = solve.frames_of(s)
        cl = ctx.clocks(s)
        feats_cmt = collections.defaultdict(set)
        for line in open(os.path.join(s, "design.features")):
            t, _, f = line.strip().partition(".")
            feats_cmt[t].add(f)
        for t, (ry, rclk) in ROWS.items():
            fs = set()
            for f in feats_cmt.get(t, ()):
                m = re.match(r"PIP\.CLK_HROUTE_1_(\d+)\.", f)
                if m:
                    fs.add("XING%d" % int(m.group(1)))
            # HDISTR<k> present per CMT_L's own wire list; the clock (and so
            # its root) is the one with a leaf on track k in this RCLK row.
            for f in feats_cmt.get(t, ()):
                m = re.match(r"WIRE\.CLK_HDISTR_0_(\d+)\.USED", f)
                if not m:
                    continue
                k = int(m.group(1))
                roots = {c["root"] for c in cl.values()
                         if any(re.match(r"RCLK_\w+_X\d+Y%d/.*CLK_HDISTR_FT0_%d->>" % (rclk, k), p)
                                for p in c["pips"])}
                nets = [c for c in cl.values()
                        if any(re.match(r"RCLK_\w+_X\d+Y%d/.*CLK_HDISTR_FT0_%d->>" % (rclk, k), p)
                               for p in c["pips"])]
                if len(nets) != 1:
                    fs.add("HD%d.UNKNOWN" % k)
                    continue
                # the root spine column: where this row's BUFCE_ROW is
                cols = sorted({int(re.match(r"RCLK_\w+?_X(\d+)Y", p).group(1)) for p in nets[0]["pips"]
                               if "BUFCE_ROW" in p and "Y%d/" % rclk in p})
                fs.add("HD%d.C%s%s" % (k, ",".join(map(str, cols)) or "none", ".PSROW" if ry == 3 else ""))
            entry = grid[t]["bits"]["CLB_IO_CLK"]
            out.append((os.path.basename(s), t, fs, solve.config_bits(solve.tile_bits(fr, entry), entry)))
    return out

def main():
    inst = instances()
    allf = sorted(set().union(*(i[2] for i in inst)))
    sol = {}
    for f in allf:
        where = [i for i in inst if f in i[2]]
        cand = set.intersection(*(i[3] for i in where))
        sol[f] = cand
    # a bit belongs to f if it is set wherever f is, and (OR) never set unless
    # one of the features claiming it is present
    claim = collections.defaultdict(set)
    for f, bs in sol.items():
        for b in bs:
            claim[b].add(f)
    for b, fs in list(claim.items()):
        if any(b in i[3] and not (i[2] & fs) for i in inst):
            del claim[b]
    final = collections.defaultdict(set)
    for b, fs in claim.items():
        for f in fs:
            final[f].add(b)
    unexp = collections.Counter()
    for s, t, fs, bits in inst:
        e = set().union(*(final[f] for f in fs)) if fs else set()
        for b in bits - e:
            unexp[(t, b)] += 1
        # over-claim: a feature's bit missing where the feature is present
    for f in sorted(allf, key=lambda f: (re.sub(r"\d+", "", f), int(re.findall(r"\d+", f)[0]))):
        n = sum(1 for i in inst if f in i[2])
        print("  %-14s n=%-3d %s" % (f, n, " ".join("%02d_%02d" % b for b in sorted(final[f]))))
    print("unexplained (tile, bit): %d distinct" % len(unexp))
    for (t, b), n in sorted(unexp.items())[:40]:
        print("   %s %02d_%02d x%d" % (t, b[0], b[1], n))
    json.dump({f: ["%02d_%02d" % b for b in sorted(final[f])] for f in allf},
              open(os.path.join(solve.HERE, "build", "solution2.json"), "w"), indent=1)

if __name__ == "__main__":
    main()
