#!/usr/bin/env python3
"""Per-mux analysis of the CMT_L clock muxes, whose selects may be encoded
(CLK_CMT_MUX_16_ENC_*, _24_ENC_*), which solve.py's set intersection cannot
see.

A mux is a destination wire with more than one pip into it. In every CMT_L
instance the mux is either unused or selects one source (the label). A bit
belongs to the mux when its state is a function of the label (the same in
every instance with that label), it differs between labels or from the
unused state, and it is clear whenever the mux is unused.

    mux.py [--dst REGEX] [--min N] [build]   -> mux_solution.json
"""
import argparse, collections, glob, json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "kv260_clk_char"))
import solve  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("build", nargs="?", default=os.path.join(HERE, "build"))
ap.add_argument("--dst", default=".")
ap.add_argument("--json", default=os.path.join(HERE, "mux_solution.json"))
ap.add_argument("--min", type=int, default=2, help="instances a label needs to choose the field")
args = ap.parse_args()

grid = json.load(open(os.path.join(solve.PART_DIR, "tilegrid.json")))
cmts = sorted(t for t, v in grid.items() if v["type"] == "CMT_L")
inst = []  # (pips {dst: src}, bits)
for spec in sorted(glob.glob(os.path.join(args.build, "specimen_*"))):
    f = os.path.join(spec, "design.nfeatures")
    if not os.path.exists(f):
        continue
    feats = collections.defaultdict(dict)
    for l in open(f):
        m = re.match(r"^(CMT_L_\w+)\.PIP\.(\S+?)\.(\S+?)(\.FWD|\.REV)?$", l.strip())
        if m:
            feats[m.group(1)][m.group(2)] = m.group(3)
    frames = solve.frames_of(spec)
    for t in cmts:
        e = grid[t]["bits"]["CLB_IO_CLK"]
        inst.append((feats.get(t, {}), solve.config_bits(solve.tile_bits(frames, e), e)))

dsts = sorted({d for p, _ in inst for d in p if re.search(args.dst, d)})
out = {}
for d in dsts:
    labels = [p.get(d) for p, _ in inst]
    used = [i for i, l in enumerate(labels) if l]
    unused = [i for i, l in enumerate(labels) if not l]
    bylabel = collections.defaultdict(list)
    for i in used:
        bylabel[labels[i]].append(i)
    # A label seen once cannot tell its select bits from whatever else that
    # instance had; only labels seen twice or more choose the field.
    solid = [i for ix in bylabel.values() if len(ix) >= args.min for i in ix]
    if not solid:
        continue
    cand = set().union(*(inst[i][1] for i in solid))
    cand -= set().union(*(inst[i][1] for i in unused)) if unused else set()
    field = []
    for b in sorted(cand):
        ok = all(len({b in inst[i][1] for i in ix}) == 1 for ix in bylabel.values() if len(ix) >= args.min)
        if ok:
            field.append(b)
    pat = {}
    for l, ix in bylabel.items():
        pat[l] = ([solve.bitname(b) for b in field if b in inst[ix[0]][1]], len(ix))
    out[d] = {l: {"bits": v[0], "n": v[1]} for l, v in pat.items()}
    print("%s  (%d used, %d unused) field %s" % (d, len(used), len(unused), " ".join(map(solve.bitname, field))))
    for l, (bits, n) in sorted(pat.items()):
        print("    %-45s %3d  %s" % (l, n, " ".join(bits) or "-"))
json.dump(out, open(args.json, "w"), indent=1, sort_keys=True)
