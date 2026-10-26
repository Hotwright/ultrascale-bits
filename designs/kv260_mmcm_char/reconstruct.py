#!/usr/bin/env python3
"""Rebuild every CMT_L tile of every specimen from features and compare.

Predicted bits = the MMCM/PLL site features computed from the cell
properties (drp.registers() at regmap.json, IN_USE, the attribute bits,
ROW_MID by row) + the segbits of every pip/wire feature Vivado used
(design.nfeatures, as nextpnr spells them), from the overlay's segbits_cmt_l.db with drp.corrections
and the pruned input-pip lines (--pipfile) in place of what the overlay has.

Prints, over all tiles, the bits predicted but clear (extra) and set but
not predicted (missing), with the features present when they occur.
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
import drp  # noqa: E402
import solve_drp  # noqa: E402

SEGBITS = os.path.join(PART_DIR, "..", "segbits_cmt_l.db")
SITES = (("MMCM", "MMCM", "MMCM_X0Y0", "MMCM_X0Y%d", lambda r: r),
         ("PLL0", "PLL", "PLL_X0Y0", "PLL_X0Y%d", lambda r: 2 * r),
         ("PLL1", "PLL", "PLL_X0Y1", "PLL_X0Y%d", lambda r: 2 * r + 1))


def parse_bit(s):
    f, o = s.lstrip("!").split("_")
    return (int(f), int(o)), s.startswith("!")


def load_db(paths):
    db = {}
    for p in paths:
        for line in open(p):
            line = line.split("#")[0].split()
            if not line:
                continue
            if len(line) >= 3 and line[1] == "add-feature":
                feat, bits = line[0], line[2:]
            elif len(line) >= 2 and line[1] != "drop-bit":
                feat, bits = line[0], line[1:]
            else:
                continue
            db[feat] = {parse_bit(b)[0] for b in bits if not b.startswith("!")}
    return db


def site_bits(db, slot, kind, rel, row, props):
    out = set()
    pre = "CMT_L.%s." % rel
    out |= db[pre + "IN_USE"]
    regs = drp.registers(kind, props)
    for reg, val in regs.items():
        for k in range(16):
            if val >> k & 1:
                out |= db["%s%s[%d]" % (pre, reg.replace(".", "_"), k)]

    def flag(name, on):
        if on:
            out.update(db[pre + name])
    inv = lambda p: props.get("IS_%s_INVERTED" % p, "1'b0").endswith("1")
    flag("IS_RST_INVERTED", inv("RST"))
    flag("ZINV_PWRDWN", not inv("PWRDWN"))
    flag("STARTUP_WAIT", props.get("STARTUP_WAIT") == "TRUE")
    if kind == "MMCM":
        flag("IS_CLKINSEL_INVERTED", inv("CLKINSEL"))
        flag("ZINV_PSEN", not inv("PSEN"))
        flag("ZINV_PSINCDEC", not inv("PSINCDEC"))
    mid = row in (1, 2)
    flag("ROW_MID[0]", mid)
    if kind == "MMCM":
        flag("ROW_MID[1]", mid or props.get("PIN.CLKIN2_USED") == "0")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("build", nargs="?", default=os.path.join(HERE, "build"))
    ap.add_argument("--pipfile", help="add-feature lines replacing the overlay's for those features")
    args = ap.parse_args()
    db = load_db([SEGBITS, os.path.join(HERE, "drp.corrections")] + ([args.pipfile] if args.pipfile else []))
    grid = json.load(open(os.path.join(PART_DIR, "tilegrid.json")))
    tiles = sorted((t for t, v in grid.items() if v["type"] == "CMT_L"), key=lambda t: int(t.split("Y")[-1]))
    extra, missing = collections.Counter(), collections.Counter()
    ctx = collections.defaultdict(collections.Counter)
    unknown = collections.Counter()
    ntiles = 0
    for spec in sorted(glob.glob(os.path.join(args.build, "specimen_*"))):
        cells = solve_drp.props_of(spec)
        feats = collections.defaultdict(set)
        for line in open(os.path.join(spec, "design.nfeatures")):
            t, _, f = line.strip().partition(".")
            feats[t].add(f)
        frames = frames_of(spec)
        for r, t in enumerate(tiles):
            e = grid[t]["bits"]["CLB_IO_CLK"]
            actual = config_bits(tile_bits(frames, e), e)
            pred = set()
            for slot, kind, rel, absn, idx in SITES:
                pred |= site_bits(db, slot, kind, rel, r, cells[absn % idx(r)])
            for f in feats[t]:
                key = "CMT_L." + f
                if key + ".V1" in db:       # nextpnr writes WIRE.<w>.USED.V1
                    key += ".V1"
                if key in db:
                    pred |= db[key]
                elif not f.split(".")[-1] in ("IN_USE",) and ".PIP." not in "." + f and not f.startswith("WIRE"):
                    pass
                elif key not in db and f.startswith("PIP"):
                    unknown[f] += 1
            ntiles += 1
            for b in pred - actual:
                extra[b] += 1
            for b in actual - pred:
                missing[b] += 1
                for f in feats[t]:
                    ctx[b][f] += 1
    print("%d tiles; %d extra bits, %d missing bits (distinct)" % (ntiles, len(extra), len(missing)))
    for b, n in sorted(extra.items(), key=lambda x: -x[1])[:20]:
        print("  extra   %02d_%-5d %d" % (b[0], b[1], n))
    for b, n in sorted(missing.items(), key=lambda x: -x[1])[:40]:
        top = [f for f, c in ctx[b].most_common(40) if c == n][:3]
        print("  missing %02d_%-5d %3d  %s" % (b[0], b[1], n, " | ".join(top)))
    print("pip features with no segbits: %d distinct" % len(unknown))
    for f, n in unknown.most_common(15):
        print("  %4d %s" % (n, f))


if __name__ == "__main__":
    main()
