#!/usr/bin/env python3
"""Effective URAM288 features, verified against every specimen, and the
segbits_uram add-feature lines they solve to (as kv260_dsp_char/emit_dsp.py).

Features, named per tile-relative site (URAM288_X0Y0..3, site Y mod 4):

  IN_USE                 the site's own in-use bits (three, in minor 4)
  OUT_<s>_ROW<r> (tile)  INT row r of the tile carries a used output of
                         side s (A: port A outputs, to INT_INTF_R_X30; B:
                         port B, to INT_INTF_L_X31); out_rows.txt says which
                         pin leaves on which row
  <ENUM>.<value>         every enum value; the defaults solve to no bits
  AUTO_SLEEP_LATENCY[k], SELF_ADDR_<p>[k]
                         the binary value
  ZSELF_MASK_<p>[k]      the mask bit inverted (set where the mask is 0)
  IS_<pin>_INVERTED      the inversion in effect: IS_INVERTED when the pin
                         is a signal; a tied pin is fed from VCC (as on the
                         DSP) and this bit makes the constant: !tie ^ IS_INV
  <pin>_TIE0/1[k]        a tied pin (hypothesis; none solves to a bit)

AVG_CONS_INACTIVE_CYCLES sets no bits (a simulation attribute).

Prints, for every specimen tile, whether the features predict the bits
exactly, then (with --emit) the add-feature lines.

    emit_uram.py [build ...] [--emit out.corrections]
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

INV_PINS = gen.INVS
# Output pin -> (side, INT row in the tile) per site position: a used output
# sets OUT_<side>_ROW<row> (a tile feature) in minors 1-3 (A) or 6-8 (B).
OUT_ROWS = {}
for _line in open(os.path.join(HERE, "out_rows.txt")):
    if _line.strip() and not _line.startswith("#"):
        _y, _pin, _side, _row = _line.split()
        OUT_ROWS[(int(_y), _pin)] = (_side, int(_row))
# Their bits, from the single-pin specimens (gen_outmap.py) rather than the
# random ones, which always use both sides together: one per INT row in each
# of three minors.
KNOWN = {"OUT_%s_ROW%d" % (side, r): [(m, r * 48 + o) for m, o in mo]
         for side, mo in (("A", ((1, 21), (2, 27), (3, 24))), ("B", ((6, 21), (7, 27), (8, 24))))
         for r in range(15)}
INTS = {"AUTO_SLEEP_LATENCY": 4}
VECS = {"SELF_ADDR_A": 11, "SELF_ADDR_B": 11}
ZVECS = {"SELF_MASK_A": 11, "SELF_MASK_B": 11}


def vbits(v):
    v = v.strip('"')
    if "'" not in v:
        return int(v)
    base = {"h": 16, "b": 2, "d": 10}[v.split("'")[1][0]]
    return int(v.split("'")[1][1:], base)


def effective(p, pins):
    """{feature name: on?} for one URAM, as nextpnr will write it."""
    q = {k: v.strip('"') for k, v in p.items()}
    # A tile can have some of its four sites in use: bits every used site
    # sets are the site's own, and the tile's own IN_USE is what every tile sets.
    f = {"IN_USE": True}
    for k in gen.ENUMS:
        f["%s.%s" % (k, q[k])] = True
    for k, w in list(INTS.items()) + list(VECS.items()):
        v = vbits(q[k])
        for b in range(w):
            f["%s[%d]" % (k, b)] = bool(v >> b & 1)
    for k, w in ZVECS.items():
        v = vbits(q[k])
        for b in range(w):
            f["Z%s[%d]" % (k, b)] = not (v >> b & 1)
    for pin in INV_PINS:
        st = pins.get(pin, "SIG")
        i = bool(vbits(q["IS_%s_INVERTED" % pin]))
        f["IS_%s_INVERTED" % pin] = i if st == "SIG" else ((st == "VCC") == i)
    for pin, w in list(gen.CTRL.items()) + list(gen.DATA.items()):
        if pin in INV_PINS:
            continue
        for b in range(w):
            name = "%s[%d]" % (pin, b) if w > 1 else pin
            st = pins.get(name, "SIG")
            f["%s_TIE0%s" % (pin, "[%d]" % b if w > 1 else "")] = st == "GND"
            f["%s_TIE1%s" % (pin, "[%d]" % b if w > 1 else "")] = st == "VCC"
    return f


def load(build):
    grid = json.load(open(os.path.join(PART_DIR, "tilegrid.json")))
    s2t = {s: t for t, v in grid.items() if v["type"].startswith("URAM_URAM") for s in v["sites"]}
    out = []
    for spec in sorted(glob.glob(os.path.join(build, "specimen_*"))):
        cells = os.path.join(spec, "cells.txt")
        if not os.path.exists(os.path.join(spec, "design.bit")) or not os.path.exists(cells):
            continue
        intent = json.load(open(os.path.join(spec, "intent.json")))
        text = open(cells).read()
        # Vivado writes cells.txt after the bitstream: skip one still being written.
        if text.count("CELL ") < len(intent) or not text.endswith("\n"):
            continue
        pins = collections.defaultdict(dict)
        for line in text.splitlines():
            w = line.split()
            if w and w[0] == "PIN" and "/" not in w[1]:
                pins[w[1]][w[2]] = {"GROUND": "GND", "POWER": "VCC"}.get(w[3], "SIG")
        per_tile = collections.defaultdict(dict)
        for cell, d in intent.items():
            y = int(d["site"].split("Y")[1])
            pre = "URAM288_X0Y%d." % (y % 4)
            for k, v in effective(d["params"], pins[cell]).items():
                per_tile[s2t[d["site"]]][pre + k] = v
            # gen.py XORs every DOUT_A/DOUT_B bit into the Pmod.
            f = per_tile[s2t[d["site"]]]
            for side in "AB":
                for r in range(15):
                    f.setdefault("OUT_%s_ROW%d" % (side, r), False)
                for b in range(72):
                    f["OUT_%s_ROW%d" % OUT_ROWS[(y % 4, "DOUT_%s%d" % (side, b))]] = True
        frames = frames_of(spec)
        for t, f in per_tile.items():
            e = grid[t]["bits"]["CLB_IO_CLK"]
            out.append((os.path.basename(spec), t, f, config_bits(tile_bits(frames, e), e)))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("build", nargs="*", default=[os.path.join(HERE, "build")])
    ap.add_argument("--emit")
    args = ap.parse_args()
    tiles = [t for b in args.build for t in load(b)]
    # Take the known features' bits out first; they must all be there.
    for i, (spec, t, f, bits) in enumerate(tiles):
        known = {b for n, v in f.items() if v and n in KNOWN for b in KNOWN[n]}
        if not known <= bits:
            print("%s %s: known OUT_ bits missing: %s" % (spec, t, sorted(known - bits)))
        tiles[i] = (spec, t, {n: v for n, v in f.items() if n not in KNOWN}, bits - known)
    always = set.intersection(*(b for _, _, _, b in tiles))
    names = sorted(set().union(*(f.keys() for _, _, f, _ in tiles)))
    db = {"IN_USE": sorted(always)}
    for n in names:
        on = [b for _, _, f, b in tiles if f.get(n)]
        off = [b for _, _, f, b in tiles if n in f and not f[n]]
        if not on:
            continue
        db[n] = sorted(set.intersection(*on) - always - (set().union(*off) if off else set()))
    # A feature that is on whenever another is keeps only the bits the other
    # does not explain (every site feature implies the site's IN_USE): every
    # bit is then claimed by one feature.
    implied = {}
    for n in db:
        if n == "IN_USE" or not db[n]:
            continue
        on = [f for _, _, f, _ in tiles if f.get(n)]
        implied[n] = [g for g in db if g not in (n, "IN_USE") and db[g] and all(f.get(g) for f in on)
                      and set(db[g]) <= set(db[n])]
    for n, gs in implied.items():
        for g in gs:
            db[n] = sorted(set(db[n]) - set(db[g]))
    bad = 0
    miss = collections.Counter()
    for spec, t, f, bits in tiles:
        pred = set(always).union(*(set(db.get(n, [])) for n, v in f.items() if v))
        if pred != bits:
            bad += 1
            miss.update(("missing", b) for b in bits - pred)
            miss.update(("extra", b) for b in pred - bits)
    print("%d tile instances, %d predicted exactly, %d not" % (len(tiles), len(tiles) - bad, bad))
    for (k, b), n in miss.most_common(30):
        print("   %s %02d_%03d in %d tiles" % (k, b[0], b[1], n))
    if args.emit:
        db.update(KNOWN)
        with open(args.emit, "w") as fo:
            for n in sorted(db):
                if db[n]:
                    fo.write("URAM.%s add-feature %s\n" % (n, " ".join("%02d_%02d" % b for b in db[n])))
        print("wrote %s: %d features" % (args.emit, sum(1 for v in db.values() if v)))


if __name__ == "__main__":
    main()
