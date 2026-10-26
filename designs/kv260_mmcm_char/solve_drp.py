#!/usr/bin/env python3
"""Locate each MMCM/PLL DRP field bit in the CMT_L frames.

For every specimen under build/ and each of the four CMT_L tiles, drp.py
computes the register fields of the tile's MMCM and two PLLs from the
properties Vivado reports (cells.txt; the generator's unrounded values from
intent.json where they agree). A field bit is located at the tile bit that
equals it -- or its complement -- in every sample. The three sites of a tile
are solved separately (MMCM, the even PLL, the odd PLL).

Counters whose output is not connected are left out of their own solve: the
xc7 writer does not program them, and whether Vivado does is a question this
answers separately (--unconnected).

    solve_drp.py [build] [--json out.json] [--unconnected]
"""
import argparse
import collections
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "kv260_clk_char"))
from solve import PART_DIR, bitname, config_bits, frames_of, tile_bits  # noqa: E402
import drp  # noqa: E402


def props_of(spec):
    cells = collections.defaultdict(dict)
    for line in open(os.path.join(spec, "cells.txt")):
        site, prop, val = line.split(None, 2)
        cells[site][prop] = val.strip()
    intent = json.load(open(os.path.join(spec, "intent.json")))
    # intent keys mmcm<r> / pll<q> are placed at MMCM_X0Y<r> / PLL_X0Y<q>
    for name, p in intent.items():
        site = ("MMCM_X0Y%s" if name.startswith("mmcm") else "PLL_X0Y%s") % name.lstrip("mpcl")
        for k, v in p.items():
            got = cells[site].get(k)
            if isinstance(v, float) and got is not None:
                try:
                    if abs(float(got) - v) < 0.002:
                        cells[site][k] = repr(v)
                except ValueError:
                    pass
    return cells


def connected(props, counter):
    return counter in ("CLKFBOUT", "DIVCLK", "LOCK", "FILTER") or props.get("PIN.%s" % counter) == "1"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("build", nargs="?", default=os.path.join(HERE, "build"))
    ap.add_argument("--json")
    ap.add_argument("--unconnected", action="store_true",
                    help="solve with unconnected counters included instead")
    args = ap.parse_args()
    grid = json.load(open(os.path.join(PART_DIR, "tilegrid.json")))
    tiles = sorted((t for t, v in grid.items() if v["type"] == "CMT_L"), key=lambda t: int(t.split("Y")[-1]))
    assert len(tiles) == 4, tiles

    # slot -> [(bits, {feature: value}, {counters known})]
    samples = collections.defaultdict(list)
    specs = sorted(s for s in glob.glob(os.path.join(args.build, "specimen_*"))
                   if os.path.exists(os.path.join(s, "cells.txt")) and os.path.exists(os.path.join(s, "design.bit")))
    for spec in specs:
        cells = props_of(spec)
        frames = frames_of(spec)
        for r, t in enumerate(tiles):
            entry = grid[t]["bits"]["CLB_IO_CLK"]
            bits = config_bits(tile_bits(frames, entry), entry)
            for slot, site, kind in (("MMCM", "MMCM_X0Y%d" % r, "MMCM"),
                                     ("PLL0", "PLL_X0Y%d" % (2 * r), "PLL"),
                                     ("PLL1", "PLL_X0Y%d" % (2 * r + 1), "PLL")):
                p = cells[site]
                f = drp.fields(kind, p)
                known = {c.split(".")[0] for c in f if args.unconnected or connected(p, c.split(".")[0])}
                samples[slot].append((bits, f, known))
    print("%d specimens" % len(specs))

    solution = {}
    for slot, ss in samples.items():
        allbits = set().union(*(s[0] for s in ss))
        sig = collections.defaultdict(set)
        for i, s in enumerate(ss):
            for b in s[0]:
                sig[b].add(i)
        feats = sorted(ss[0][1])
        stats = collections.Counter()
        sol = {}
        print("\n=== %s: %d samples, %d tile bits seen" % (slot, len(ss), len(allbits)))
        for f in feats:
            counter = f.split(".")[0]
            K = {i for i, s in enumerate(ss) if counter in s[2]}
            ones = {i for i in K if ss[i][1][f]}
            if not K or not ones or ones == K:
                stats["constant"] += 1
                sol[f] = ("const", int(bool(ones)), len(K))
                continue
            pos = sorted(b for b in allbits if sig[b] & K == ones)
            neg = sorted(b for b in allbits if K - sig[b] == ones)
            if len(pos) + len(neg) == 1:
                stats["solved"] += 1
                sol[f] = ("bit", bitname(pos[0]) if pos else "!" + bitname(neg[0]), len(K))
            elif not pos and not neg:
                stats["none"] += 1
                sol[f] = ("none", None, len(K))
            else:
                stats["ambiguous"] += 1
                sol[f] = ("ambig", [bitname(b) for b in pos] + ["!" + bitname(b) for b in neg], len(K))
        for f in feats:
            kind, val, n = sol[f]
            if kind != "bit":
                print("  %-28s %-6s %s (n=%d)" % (f, kind, val, n))
        print("  -- %s" % dict(stats))
        solution[slot] = sol
    if args.json:
        json.dump(solution, open(args.json, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
