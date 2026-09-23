#!/usr/bin/env python3
"""Compare two FASM files by feature CLASS per tile type.

The point of this is the test tools/check_fasm_vs_uraydb.py structurally
cannot do. That one proves `emitted is a subset of known`, so a feature we
fail to write is invisible to it. Diffing against a Vivado-built reference is
the only way to see an omission.

What it does NOT do is compare features, let alone bytes. Two builds of the
same Verilog place cells on different slices, route over different tracks, and
permute each LUT's INIT by whichever input pins the packer chose -- all legal,
all different. Comparing instances would report thousands of differences that
mean nothing.

So it compares CLASSES: a feature with its tile instance replaced by the tile
TYPE and every numeric index replaced by `*`. `CLEM_X23Y149.AFF.INIT.V0` and
`CLEM_X9Y100.HFF.INIT.V0` are both `CLEM:*FF.INIT.V0`. That is invariant under
placement and routing, and it is exactly the granularity at which "Vivado
writes a kind of feature we never write" becomes visible.

Routing pips are bucketed harder still -- every `PIP.<dst>.<src>` in a tile
type collapses to one `PIP.*` class. They have to be. A pip name carries so
much position (`INODE_W_1_FT1`, `BOUNCE_W_13_FT0`) that even after collapsing
digits, two routes of the same net share almost no pip classes, so leaving
them fine-grained fills the verdict with hundreds of differences that only say
"the router chose differently". Which pip classes a tile type uses is not a
correctness claim; whether we configure that tile type at all is. Pass
--pip-detail to see them anyway, as a separate section that does not affect the
exit code.

Read the "only in <reference>" section first. Those are the candidate bugs:
site configuration we never write. "only in ours" is usually benign (nextpnr
writing an explicit default Vivado leaves implicit) but is worth a look.
Counts are reported as an order of magnitude, not a number, because they
legitimately differ.

Usage: diff_fasm_classes.py <reference.fasm> <ours.fasm> [--tilegrid PATH]
"""
import argparse
import json
import os
import re
import sys
from collections import Counter


def load_tilegrid(path):
    """tile instance name -> tile type. Empty dict if we have no tilegrid."""
    if not path or not os.path.exists(path):
        return {}
    with open(path) as f:
        grid = json.load(f)
    return {name: info["type"] for name, info in grid.items() if "type" in info}


# A tile instance name ends in _X<n>Y<n>; the type is what precedes it. This is
# the fallback when there is no tilegrid.json, and it is right for every tile
# name prjuray emits -- but the tilegrid is authoritative, so prefer it.
TILE_SUFFIX = re.compile(r"_X-?\d+Y-?\d+$")
# Site instances inside a feature path (SLICE_X12Y149, IOB_X0Y3, BUFCE_LEAF_X0Y2)
# and bit indices (INIT[43]) are per-instance noise.
SITE_INST = re.compile(r"_X-?\d+Y-?\d+")
INDEX = re.compile(r"\[\d+(?::\d+)?\]")
# Standalone numbers inside a feature path: IMUX16, CLK_HDISTR_L7, BYP_ALT4.
# Collapsing these is what makes "Vivado uses a distribution track we never
# touch" read as agreement rather than as a difference -- which is what we
# want here, since the track choice is the router's.
NUMBER = re.compile(r"(?<=[A-Z_])\d+")
# The UltraScale+ CLE has one slice with eight LUTs and sixteen FFs named A..H.
# Which letter a cell lands on is the packer's choice -- the same difference
# that makes LUT INIT bits differ between two legal builds. So `BFF.INIT` and
# `CFF.INIT` are one class, and the question the diff answers becomes "does a
# kind of CLE feature exist that we never write", which is the correctness
# question. `ABCDFF`/`EFGHFF` are the two control halves, and which half a FF
# is packed into is equally the packer's choice, so they collapse too; their
# features (CEUSED, SRUSED, CLKINV) never collide with the per-FF ones (INIT,
# SRVAL) so nothing real is lost.
CLE_LETTER = [
    (re.compile(r"^(?:ABCD|EFGH)FF2?\."), "CTRLFF."),
    (re.compile(r"^[A-H]FF2?\."), "FF."),
    (re.compile(r"^[A-H]\d?LUT\."), "LUT."),
    (re.compile(r"^(FFMUX|OUTMUX|CARRY_MUX)[A-H]"), r"\1"),
]


def classify(line, types, pip_detail=False):
    """`TILE_X1Y2.FOO3.BAR[7]` -> `('TILE', 'FOO*.BAR[*]')`, or None."""
    line = line.split("#")[0].strip()
    if not line:
        return None
    line = line.split()[0].rstrip("=").strip()
    if "." not in line:
        return None
    tile, feature = line.split(".", 1)
    ttype = types.get(tile) or TILE_SUFFIX.sub("", tile)
    feature = SITE_INST.sub("_X*Y*", feature)
    feature = INDEX.sub("[*]", feature)
    # Before NUMBER: these rules are anchored on spellings like `AFF2` that
    # the digit collapse would turn into `AFF*` and make unmatchable.
    if ttype.startswith("CLE"):
        for rx, repl in CLE_LETTER:
            new = rx.sub(repl, feature)
            if new != feature:
                feature = new
                break
    feature = NUMBER.sub("*", feature)
    if feature.startswith("PIP.") and not pip_detail:
        feature = "PIP.*"
    return ttype, feature


def magnitude(n):
    """Counts differ legitimately; only the order of magnitude is meaningful."""
    if n == 0:
        return "0"
    if n < 10:
        return "<10"
    if n < 100:
        return "<100"
    if n < 1000:
        return "<1k"
    return f"~{n // 1000}k"


def read(path, types, pip_detail=False):
    counts = Counter()
    with open(path) as f:
        for line in f:
            c = classify(line, types, pip_detail)
            if c:
                counts[c] += 1
    return counts


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reference", help="FASM from a Vivado bitstream (bit2fasm.py)")
    ap.add_argument("ours", help="FASM from the open flow")
    ap.add_argument("--tilegrid", default=os.path.join(
        os.environ.get("URAY_FAMILY_DIR", ""),
        os.environ.get("URAY_PART", ""), "tilegrid.json"))
    ap.add_argument("--pip-detail", action="store_true",
                    help="also list individual pip classes (does not affect exit code)")
    args = ap.parse_args()

    types = load_tilegrid(args.tilegrid)
    print(f"tilegrid: {len(types)} tiles"
          if types else "tilegrid: none, falling back to name suffixes")

    ref = read(args.reference, types)
    ours = read(args.ours, types)
    print(f"reference {args.reference}: {sum(ref.values())} features, "
          f"{len(ref)} classes")
    print(f"ours      {args.ours}: {sum(ours.values())} features, "
          f"{len(ours)} classes")

    only_ref = sorted(set(ref) - set(ours))
    only_ours = sorted(set(ours) - set(ref))
    both = sorted(set(ref) & set(ours))

    # Tile types absent from one side entirely are reported separately: they
    # mean a whole block was not ported (BRAM, DSP, PLL), not a missing bit.
    ref_tt, ours_tt = {t for t, _ in ref}, {t for t, _ in ours}
    if ref_tt - ours_tt:
        print(f"\n### tile types only Vivado configures ({len(ref_tt - ours_tt)})")
        for t in sorted(ref_tt - ours_tt):
            print(f"  {t}")
    if ours_tt - ref_tt:
        print(f"\n### tile types only we configure ({len(ours_tt - ref_tt)})")
        for t in sorted(ours_tt - ref_tt):
            print(f"  {t}")

    print(f"\n### classes ONLY in the reference -- candidate omissions "
          f"({len(only_ref)})")
    for t, f in only_ref:
        print(f"  {magnitude(ref[(t, f)]):>5}  {t}:{f}")

    print(f"\n### classes only in ours ({len(only_ours)})")
    for t, f in only_ours:
        print(f"  {magnitude(ours[(t, f)]):>5}  {t}:{f}")

    print(f"\n### in both ({len(both)})")
    for t, f in both:
        print(f"  {magnitude(ref[(t, f)]):>5} {magnitude(ours[(t, f)]):>5}  {t}:{f}")

    if args.pip_detail:
        dref = read(args.reference, types, pip_detail=True)
        dours = read(args.ours, types, pip_detail=True)
        pips = lambda c: {k for k in c if k[1].startswith("PIP.")}
        pr, po = pips(dref), pips(dours)
        print(f"\n### pip classes only in the reference ({len(pr - po)}) "
              f"-- informational, routing is the router's choice")
        for t, f in sorted(pr - po):
            print(f"  {magnitude(dref[(t, f)]):>5}  {t}:{f}")
        print(f"\n### pip classes only in ours ({len(po - pr)})")
        for t, f in sorted(po - pr):
            print(f"  {magnitude(dours[(t, f)]):>5}  {t}:{f}")

    # Exit non-zero on a candidate omission so a caller can gate on it. Only
    # the reference-only side does: extra features are not a missing bit.
    return 1 if only_ref else 0


if __name__ == "__main__":
    sys.exit(main())
