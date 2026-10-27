#!/usr/bin/env python3
"""Solve the DSP48E2 site features from the kv260_dsp_char specimens.

For every used DSP tile: its bits (ECC halfwords masked) and its features,
namespaced DSP_0 (even Y, the lower site) and DSP_1. A feature is
  <ATTR>.<VALUE>          an enum or register count (AREG.2, USE_SIMD.TWO24)
  <VEC>[k].<0|1>          bit k of MASK/PATTERN/RND
  <PIN>[k].<SIG|GND|VCC>  how a control pin bit is driven
  <PIN>[k].<state>.<INV|NOINV>  ... and its IS_<PIN>_INVERTED bit
A feature's bits are those set in every tile that has it and in no tile that
lacks it. Prints each feature's bits, then how well the union predicts every
tile.

    solve.py [build] [--json out]
"""
import argparse
import collections
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "kv260_clk_char"))
from solve import PART_DIR, config_bits, frames_of, tile_bits  # noqa: E402
sys.path.insert(0, HERE)
import gen  # noqa: E402

VECS = ("MASK", "PATTERN", "RND")


def site_tile(grid):
    out = {}
    for t, v in grid.items():
        if v["type"] == "DSP":
            for s in v["sites"]:
                out[s] = t
    return out


def features(params, pins):
    f = set()
    for k, v in params.items():
        v = v.strip('"')
        if k in VECS:
            n = int(v.split("'h")[1], 16)
            f |= {"%s[%d].%d" % (k, b, n >> b & 1) for b in range(48)}
        elif k.startswith("IS_"):
            continue
        else:
            f.add("%s.%s" % (k, v))
    for pin, w in gen.CTRL.items():
        inv = params.get("IS_%s_INVERTED" % pin)
        invbits = int(inv.split("'b")[1], 2) if inv else 0
        for b in range(w):
            name = "%s[%d]" % (pin, b) if w > 1 else pin
            st = pins.get(name, "SIG")
            f.add("%s.%s" % (name, st))
            if inv:
                f.add("%s.%s.%s" % (name, st, "INV" if invbits >> b & 1 else "NOINV"))
    f.add("CLK.INV" if int(params["IS_CLK_INVERTED"].split("'b")[1], 2) else "CLK.NOINV")
    return f


def load(build):
    grid = json.load(open(os.path.join(PART_DIR, "tilegrid.json")))
    s2t = site_tile(grid)
    tiles = []
    for spec in sorted(glob.glob(os.path.join(build, "specimen_*"))):
        if not os.path.exists(os.path.join(spec, "design.bit")):
            continue
        intent = json.load(open(os.path.join(spec, "intent.json")))
        pins = collections.defaultdict(dict)
        for line in open(os.path.join(spec, "cells.txt")):
            w = line.split()
            if w[0] == "PIN" and "/" not in w[1]:
                pins[w[1]][w[2]] = {"GROUND": "GND", "POWER": "VCC"}.get(w[3], "SIG")
        per_tile = collections.defaultdict(set)
        for cell, d in intent.items():
            y = int(d["site"].split("Y")[1])
            pre = "DSP_%d." % (y % 2)
            per_tile[s2t[d["site"]]] |= {pre + x for x in features(d["params"], pins[cell])}
        frames = frames_of(spec)
        for t, f in per_tile.items():
            e = grid[t]["bits"]["CLB_IO_CLK"]
            tiles.append((os.path.basename(spec), t, f, config_bits(tile_bits(frames, e), e)))
    return tiles


def solve(tiles):
    allf = set().union(*(f for _, _, f, _ in tiles))
    sol = {}
    for feat in sorted(allf):
        has = [b for _, _, f, b in tiles if feat in f]
        lacks = [b for _, _, f, b in tiles if feat not in f]
        if not has or not lacks:
            continue
        sol[feat] = sorted(set.intersection(*has) - set().union(*lacks))
    return sol


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("build", nargs="?", default=os.path.join(HERE, "build"))
    ap.add_argument("--json")
    args = ap.parse_args()
    tiles = load(args.build)
    print("%d tile instances from %d specimens" % (len(tiles), len({s for s, _, _, _ in tiles})))
    always = set.intersection(*(b for _, _, _, b in tiles))
    print("TILE.IN_USE (set in every used tile): %s" % " ".join("%02d_%03d" % b for b in sorted(always)))
    tiles = [(s, t, f, b - always) for s, t, f, b in tiles]
    sol = solve(tiles)
    for k, v in sol.items():
        if v:
            print("%-40s %s" % (k, " ".join("%02d_%03d" % b for b in v)))
    print("features without bits: %d of %d" % (sum(1 for v in sol.values() if not v), len(sol)))
    extra = missing = 0
    miss = collections.Counter()
    for spec, t, f, bits in tiles:
        pred = set().union(*(set(sol.get(x, [])) for x in f))
        extra += len(pred - bits)
        missing += len(bits - pred)
        miss.update(bits - pred)
    print("prediction: %d bits predicted but clear, %d set but unexplained" % (extra, missing))
    for b, n in miss.most_common(40):
        print("  unexplained %02d_%03d in %d tiles" % (b[0], b[1], n))
    if args.json:
        sol["TILE.IN_USE"] = sorted(always)
        json.dump({k: v for k, v in sol.items()}, open(args.json, "w"), indent=1)


if __name__ == "__main__":
    main()
