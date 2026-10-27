#!/usr/bin/env python3
"""Effective DSP48E2 features, verified against every specimen, and the
segbits_dsp add-feature lines they solve to.

solve.py found how Vivado writes each attribute (kv260_dsp_char, 2026-10-27;
build2 is a DATA_TIES=1 batch that ties the data buses as well);
this restates it as the features nextpnr will emit, with Vivado's
normalisation applied:

  MASK[k]                written as 1 when USE_PATTERN_DETECT is NO_PATDET
  SEL_MASK.<v>           only with PATDET (MASK otherwise)
  ZADREG / ZDREG         set when ADREG / DREG is 0 in effect: the register
                         counts only when USE_MULT is not NONE and AMULTSEL
                         or BMULTSEL is AD
  ACASCREG_EQ_AREG       set when ACASCREG equals AREG (likewise B)
  ZINV_<pin>[k]          an invertible pin (ALUMODE, CARRYIN, INMODE, OPMODE,
                         RST*): !IS_INVERTED when the pin is a signal; for a
                         tied pin the constant itself, tie ^ IS_INVERTED
  CARRYINSEL_TIE0/1[k]   a tied CARRYINSEL bit
  D_TIE0/1[k]            a tied D bit (D_TIE1 has no bits for D[3], D[13],
                         D[23]); a tied A, B or C bit sets nothing here.
                         Vivado routes these constants all the same, and
                         feeds every tied invertible pin from VCC
  ZINV_CLK               !IS_CLK_INVERTED
  OUT_ROW<r> (tile)      INT row r of the tile carries a used output (one bit
                         in each of minors 1-3); out_rows.txt says which pin
                         leaves on which row. No other bit marks a DSP in use

Features are named per tile-relative site (DSP48E2_X0Y0 is the lower, even
global Y). Prints, for every specimen tile, whether the features predict the
bits exactly, then (with --emit) the add-feature lines.

    emit_dsp.py [build ...] [--emit out.corrections]
"""
import argparse
import collections
import os
import pickle
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "kv260_clk_char"))
from solve import PART_DIR, config_bits, frames_of, tile_bits  # noqa: E402
sys.path.insert(0, HERE)
import gen  # noqa: E402

# Output site pin -> INT row in the tile, per site position: a used output
# sets OUT_ROW<row> (a tile feature: one bit in each of minors 1-3). Its bits
# come from the single-pin specimen (gen_outmap.py); the random specimens use
# all of P, so they cannot tell the rows apart.
OUT_ROWS = {}
for _line in open(os.path.join(HERE, "out_rows.txt")):
    if _line.strip() and not _line.startswith("#"):
        _y, _pin, _row = _line.split()
        OUT_ROWS[(int(_y), _pin)] = int(_row)
KNOWN = {"OUT_ROW%d" % r: [(1, r * 48 + 21), (2, r * 48 + 27), (3, r * 48 + 24)] for r in range(5)}

INV_PINS = {"ALUMODE": 4, "CARRYIN": 1, "INMODE": 5, "OPMODE": 9, "RSTA": 1, "RSTALLCARRYIN": 1, "RSTALUMODE": 1,
            "RSTB": 1, "RSTC": 1, "RSTCTRL": 1, "RSTD": 1, "RSTINMODE": 1, "RSTM": 1, "RSTP": 1}
ENUM_KEEP = ["ALUMODEREG", "CARRYINREG", "CARRYINSELREG", "CREG", "INMODEREG", "MREG", "OPMODEREG", "PREG",
             "AMULTSEL", "BMULTSEL", "PREADDINSEL", "A_INPUT", "B_INPUT", "AUTORESET_PATDET",
             "AUTORESET_PRIORITY", "SEL_PATTERN", "USE_MULT", "USE_SIMD", "USE_WIDEXOR", "XORSIMD", "AREG", "BREG"]


def vbits(v, w=48):
    v = v.strip('"')
    base = 16 if "'h" in v else 2
    return int(v.split("'")[1][1:], base)


def effective(p, pins):
    """{feature name: on?} for one DSP, as nextpnr will write it."""
    q = {k: v.strip('"') for k, v in p.items()}
    f = {}
    for k in ENUM_KEEP:
        # A FASM name component cannot start with a digit: AREG_2, not AREG.2.
        f[("%s_%s" if q[k][0].isdigit() else "%s.%s") % (k, q[k])] = True
    f["ACASCREG_EQ_AREG"] = q["ACASCREG"] == q["AREG"]
    f["BCASCREG_EQ_BREG"] = q["BCASCREG"] == q["BREG"]
    patdet = q["USE_PATTERN_DETECT"] == "PATDET"
    f["SEL_MASK.%s" % (q["SEL_MASK"] if patdet else "MASK")] = True
    preadd = q["USE_MULT"] != "NONE" and (q["AMULTSEL"] == "AD" or q["BMULTSEL"] == "AD")
    f["ZADREG"] = not (preadd and q["ADREG"] == "1")
    f["ZDREG"] = not (preadd and q["DREG"] == "1")
    mask, pat, rnd = vbits(q["MASK"]), vbits(q["PATTERN"]), vbits(q["RND"])
    for k in range(48):
        f["MASK[%d]" % k] = (not patdet) or bool(mask >> k & 1)
        f["PATTERN[%d]" % k] = bool(pat >> k & 1)
        f["RND[%d]" % k] = bool(rnd >> k & 1)
    for pin, w in INV_PINS.items():
        inv = vbits(q["IS_%s_INVERTED" % pin])
        for b in range(w):
            name = "%s[%d]" % (pin, b) if w > 1 else pin
            st = pins.get(name, "SIG")
            i = bool(inv >> b & 1)
            f["ZINV_%s" % name] = (not i) if st == "SIG" else ((st == "VCC") != i)
    for b in range(3):
        st = pins.get("CARRYINSEL[%d]" % b, "SIG")
        f["CARRYINSEL_TIE0[%d]" % b] = st == "GND"
        f["CARRYINSEL_TIE1[%d]" % b] = st == "VCC"
    for pin, w in gen.DATA.items():
        for b in range(w):
            st = pins.get("%s[%d]" % (pin, b), "SIG")
            f["%s_TIE0[%d]" % (pin, b)] = st == "GND"
            f["%s_TIE1[%d]" % (pin, b)] = st == "VCC"
    f["ZINV_CLK"] = not vbits(q["IS_CLK_INVERTED"])
    return f


def load(build):
    import glob
    import json
    grid = json.load(open(os.path.join(PART_DIR, "tilegrid.json")))
    s2t = {s: t for t, v in grid.items() if v["type"] == "DSP" for s in v["sites"]}
    out = []
    for spec in sorted(glob.glob(os.path.join(build, "specimen_*"))):
        if not os.path.exists(os.path.join(spec, "design.bit")):
            continue
        intent = json.load(open(os.path.join(spec, "intent.json")))
        cells = os.path.join(spec, "cells.txt")
        # Vivado writes cells.txt after the bitstream: skip a specimen still
        # being written.
        if not os.path.exists(cells) or open(cells).read().count("\nCELL ") + 1 < 9 * len(intent) \
                or not open(cells).read().endswith("\n"):
            continue
        pins = collections.defaultdict(dict)
        for line in open(cells):
            w = line.split()
            if w[0] == "PIN" and "/" not in w[1]:
                pins[w[1]][w[2]] = {"GROUND": "GND", "POWER": "VCC"}.get(w[3], "SIG")
        per_tile = collections.defaultdict(dict)
        for cell, d in intent.items():
            y = int(d["site"].split("Y")[1])
            pre = "DSP48E2_X0Y%d." % (y % 2)
            for k, v in effective(d["params"], pins[cell]).items():
                per_tile[s2t[d["site"]]][pre + k] = v
            # gen.py XORs every bit of P into the Pmod.
            f = per_tile[s2t[d["site"]]]
            for r in range(5):
                f.setdefault("OUT_ROW%d" % r, False)
            for b in range(48):
                f["OUT_ROW%d" % OUT_ROWS[(y % 2, "P%d" % b)]] = True
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
            print("%s %s: known OUT_ROW bits missing: %s" % (spec, t, sorted(known - bits)))
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
    # does not explain (AREG.0 implies ACASCREG_EQ_AREG): every bit is then
    # claimed by one feature.
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
    for (k, b), n in miss.most_common(20):
        print("   %s %02d_%03d in %d tiles" % (k, b[0], b[1], n))
    if args.emit:
        db.update(KNOWN)
        with open(args.emit, "w") as fo:
            for n in sorted(db):
                if db[n]:
                    fo.write("DSP.%s add-feature %s\n" % (n, " ".join("%02d_%02d" % b for b in db[n])))
        print("wrote %s: %d features" % (args.emit, sum(1 for v in db.values() if v)))


if __name__ == "__main__":
    main()
