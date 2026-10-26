#!/usr/bin/env python3
"""Per-bit analysis of a multi-valued site attribute (BUFGCE_DIVIDE...), which
solve.py's set intersection cannot see when the value is binary-encoded.

For every instance of <site> with <attr> set, list the bits that are set in
some instances and clear in others, against the attribute's value.

    field.py <SITE_XnYm> <ATTR> [build]
"""
import collections, glob, json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "kv260_clk_char"))
import solve  # noqa: E402

site, attr = sys.argv[1], sys.argv[2]
build = sys.argv[3] if len(sys.argv) > 3 else os.path.join(HERE, "build")
grid = json.load(open(os.path.join(solve.PART_DIR, "tilegrid.json")))
rows = []
for spec in sorted(glob.glob(os.path.join(build, "specimen_*"))):
    f = os.path.join(spec, "design.nfeatures")
    if not os.path.exists(f):
        continue
    feats = [l.strip() for l in open(f)]
    for l in feats:
        m = re.match(r"^(CMT_L_\w+)\.%s\.%s\.(\w+)$" % (site, attr), l)
        if not m:
            continue
        tile = m.group(1)
        entry = grid[tile]["bits"]["CLB_IO_CLK"]
        bits = solve.config_bits(solve.tile_bits(solve.frames_of(spec), entry), entry)
        rows.append((m.group(2), bits, os.path.basename(spec)))
if not rows:
    sys.exit("no instances")
allb = set().union(*(r[1] for r in rows))
common = set.intersection(*(r[1] for r in rows))
vary = sorted(allb - common)
vals = sorted({r[0] for r in rows})
# bits whose state is a function of the value alone
for b in vary:
    per = collections.defaultdict(set)
    for v, bits, _ in rows:
        per[v].add(b in bits)
    if all(len(s) == 1 for s in per.values()) and len({next(iter(s)) for s in per.values()}) > 1:
        print("%s  %s" % (solve.bitname(b), " ".join("%s=%d" % (v, next(iter(per[v]))) for v in vals)))
print("%d instances: %s" % (len(rows), collections.Counter(r[0] for r in rows)))
