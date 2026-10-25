#!/usr/bin/env python3
"""Diff each characterisation tile against its baseline, bit by bit.

Usage: analyze_char.py <reference dir>   (needs ref.frames and variants.json)

Bits of INIT_A/INIT_B/SRVAL_A/SRVAL_B are masked out of the diffs (they are
random per tile) and solved separately: for every 18-bit or 36-bit value,
which parameter bit lands on which prjuray feature bit.
"""
import json
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
R = os.path.abspath(os.path.join(HERE, "../.."))
sys.path.insert(0, os.path.join(R, "tools"))
from diff_tile_bits import load, tile_bits  # noqa: E402

ref = sys.argv[1]
grid = json.load(open(os.path.join(R, "prjuray/database/zynqusp/xck26-sfvc784-2LV-c/tilegrid.json")))
variants = json.load(open(os.path.join(HERE, "variants.json")))
frames = load(os.path.join(ref, "ref.frames"))

# prjuray segbits: feature -> list of (bit, value)
seg = defaultdict(list)
for line in open(os.path.join(R, "prjuray-db/zynqusp/segbits_bram.db")):
    f, *bits = line.split()
    for b in bits:
        neg = b.startswith("!")
        fo, bo = b.lstrip("!").split("_")
        seg[f].append(((int(fo), int(bo)), not neg))
bit_names = defaultdict(list)
for f, bl in seg.items():
    for b, v in bl:
        if v:
            bit_names[b].append(f)

vecbits = {}  # (half, param, idx) -> bit
for f, bl in seg.items():
    m = re.match(r"BRAM\.RAMB18E2_([LU])\.(INIT_A|INIT_B|SRVAL_A|SRVAL_B)\[(\d+)\]$", f)
    if m:
        vecbits[(m.group(1), m.group(2), int(m.group(3)))] = bl[0][0]
mask = set(vecbits.values())


def bits_of(tile):
    return tile_bits(frames, grid[tile]["bits"]["CLB_IO_CLK"])


def pval(s):
    w, h = s.split("'h")
    return int(h, 16)


tb = {}
for v in variants:
    tb.setdefault(v["tile"], bits_of(v["tile"]))

# Baselines: per half kind
by_label = {(v["half"], v["label"]): v for v in variants}
print("== baseline stability (masked)")
for h in ("L", "U", "36"):
    a, b = by_label[(h, "base")], by_label[(h, "base2")]
    d = (tb[a["tile"]] - mask) ^ (tb[b["tile"]] - mask)
    print(f"  {h}: base vs base2 differ in {len(d)} bit(s) {sorted(d)}")


def name(b):
    return "/".join(bit_names.get(b, [])) or "?"


print("== variants vs base (masked)")
for v in variants:
    if v["label"] in ("base", "base2") or v["half"] not in ("L", "U", "36"):
        continue
    base = by_label[(v["half"], "base")]
    plus = sorted((tb[v["tile"]] - mask) - (tb[base["tile"]] - mask))
    minus = sorted((tb[base["tile"]] - mask) - (tb[v["tile"]] - mask))
    print(f"  {v['half']:>2} {v['label']:<22} +{[(b, name(b)) for b in plus]}  -{[(b, name(b)) for b in minus]}")

both = [v for v in variants if v["label"] == "both"]
if both:
    t = both[0]["tile"]
    lb, ub = tb[by_label[("L", "base")]["tile"]], tb[by_label[("U", "base")]["tile"]]
    print("== both halves vs union of lone halves:",
          sorted(((tb[t] - mask) ^ ((lb | ub) - mask))))

print("== INIT_A/INIT_B/SRVAL_A/SRVAL_B bit order")
for p in ("INIT_A", "INIT_B", "SRVAL_A", "SRVAL_B"):
    for kind in ("18", "36"):
        vs = [v for v in variants if (v["half"] == "36") == (kind == "36")]
        width = 36 if kind == "36" else 18
        mapping = {}
        for pb in range(width):
            cands = None
            for v in vs:
                halves = ("L", "U") if kind == "36" else (v["half"],)
                bitv = (pval(v["params"][p]) >> pb) & 1
                c = set()
                for h in halves:
                    for i in range(18):
                        if ((vecbits[(h, p, i)] in tb[v["tile"]]) == bool(bitv)):
                            c.add((h if kind == "36" else "", i))
                cands = c if cands is None else cands & c
            mapping[pb] = sorted(cands)
        print(f"  {p} ({kind}):", {k: (c[0] if len(c) == 1 else c) for k, c in mapping.items()})
