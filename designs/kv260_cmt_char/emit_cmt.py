#!/usr/bin/env python3
"""CMT_L segbits from the kv260_cmt_char solutions, as db-corrections lines.

  pips:  mux_solution.json (mux.py): every <dst> <- <src> seen in at least
         --min instances, with the bits its select sets (an empty select
         gets no line; nextpnr drops bitless pips as documented).
  sites: solve.py --json: a group holding exactly one site feature (one
         <SITE>.<ATTR>[.<value>]) and nothing else, seen --min times.
         BUFGCE_DIVIDE comes from field.py's encoding: DIVIDE-1 in 3 bits.

Then the check that matters: for every CMT_L instance of every specimen,
predict its bits from Vivado's features and these lines, and compare inside
the bits any line claims. Bits outside every line (MMCM/PLL registers) are
not judged here.

    emit_cmt.py mux_solution.json solve.json [build] > cmt.corrections
"""
import argparse, collections, glob, json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "kv260_clk_char"))
import solve  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("mux")
ap.add_argument("sol")
ap.add_argument("build", nargs="?", default=os.path.join(HERE, "build"))
ap.add_argument("--min", type=int, default=2)
ap.add_argument("--skip", default=r"^PIP\.CLK_HROUTE_1_",
                help="features already in segbits_cmt_l.corrections")
args = ap.parse_args()

feat = {}  # CMT_L feature (tile-relative) -> [bits]
for dst, labels in json.load(open(args.mux)).items():
    for src, v in labels.items():
        name = "PIP.%s.%s" % (dst, src)
        if v["n"] >= args.min and v["bits"] and not re.search(args.skip, name):
            feat[name] = v["bits"]
sol = json.load(open(args.sol))["CMT_L"]
counts = {}
for g, bits in sol.items():
    fs = g.split()
    sites = [f for f in fs if not f.startswith(("PIP.", "WIRE."))]
    if len(fs) == 1 and len(sites) == 1 and bits and "BUFGCE_DIVIDE" not in fs[0]:
        feat[fs[0]] = bits
# BUFGCE_DIVIDE = DIVIDE-1 in three bits (field.py, 2026-10-26): bit 0 and
# bit 2 at <m>_1545 / <m>_1546, bit 1 at <m'>_1546, per site.
DIV = {0: ("06_1545", "07_1546", "06_1546"), 1: ("04_1545", "05_1546", "04_1546"),
       2: ("09_1545", "08_1546", "09_1546"), 3: ("11_1545", "10_1546", "11_1546")}
for j, (b0, b1, b2) in DIV.items():
    for n in range(1, 9):
        v = n - 1
        bits = [b for k, b in enumerate((b0, b1, b2)) if v >> k & 1]
        if bits:
            feat["BUFGCE_DIV_X0Y%d.BUFGCE_DIVIDE.D%d" % (j, n)] = bits

# check: predicted vs actual over the claimed bits
claimed = {tuple(map(int, b.split("_"))) for bs in feat.values() for b in bs}
grid = json.load(open(os.path.join(solve.PART_DIR, "tilegrid.json")))
cmts = sorted(t for t, v in grid.items() if v["type"] == "CMT_L")
miss = collections.Counter(); extra = collections.Counter(); n = 0
for spec in sorted(glob.glob(os.path.join(args.build, "specimen_*"))):
    f = os.path.join(spec, "design.nfeatures")
    if not os.path.exists(f):
        continue
    fs = collections.defaultdict(set)
    for l in open(f):
        t, _, rest = l.strip().partition(".")
        fs[t].add(rest)
    frames = solve.frames_of(spec)
    for t in cmts:
        e = grid[t]["bits"]["CLB_IO_CLK"]
        have = solve.config_bits(solve.tile_bits(frames, e), e) & claimed
        want = {tuple(map(int, b.split("_"))) for x in fs.get(t, ()) for b in feat.get(x, ())}
        for b in have - want:
            miss[b] += 1
        for b in want - have:
            extra[b] += 1
        n += 1
print("# %d features; checked over %d CMT_L instances: %d bit(s) set but not predicted, %d predicted but clear"
      % (len(feat), n, sum(miss.values()), sum(extra.values())), file=sys.stderr)
for what, c in (("set, not predicted", miss), ("predicted, clear", extra)):
    if c:
        print("#   %s: %s" % (what, " ".join("%s(%d)" % (solve.bitname(b), k) for b, k in c.most_common(25))),
              file=sys.stderr)
for k in sorted(feat):
    print("CMT_L.%s add-feature %s" % (k, " ".join(sorted(feat[k]))))
