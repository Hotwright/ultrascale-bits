#!/usr/bin/env python3
"""Solve the clock-crossing segbits from the specimens char.tcl built.

For every tile of a studied type in every specimen we have the features Vivado
used there (design.features) and the bits set in the tile's window
(design.bit, through bitread). A feature's bits are those set in every
instance that has it and in no instance that lacks it. Features that always
appear together share their bits; they are reported as one group, and the
caller decides which spelling nextpnr emits.

Then the check that matters: in every instance, every set bit must be
explained by the features present there. An unexplained bit means a feature
we did not model, and the solution is not trustworthy until it is gone.

    solve.py [--types CMT_L,RCLK_CLEM_CLKBUF_L] [build]
"""
import argparse
import collections
import glob
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from diff_tile_bits import load, tile_bits  # noqa: E402

PART_DIR = os.path.join(ROOT, "prjuray/database/zynqusp/xck26-sfvc784-2LV-c")
BITREAD = os.path.join(ROOT, "prjuray/third_party/prjuray-tools/build/tools/bitread")


def frames_of(spec):
    out = os.path.join(spec, "design.frames")
    if not os.path.exists(out):
        subprocess.run([BITREAD, "--architecture", "UltraScalePlus",
                        "--part_file", os.path.join(PART_DIR, "part.yaml"),
                        "-o", out, os.path.join(spec, "design.bit")],
                       check=True, stdout=subprocess.DEVNULL)
    return load(out)


def config_bits(bits, entry):
    """Drop the frame-ECC halfwords (90-92 in a 186-halfword US+ frame).

    xcframes2bit recomputes them and bitread masks them, so a bit there is a
    function of the whole frame, never a feature's own. Inside CMT_L's window
    (offset 84) that is relative bits 96-143.
    """
    off = entry["offset"]
    return {b for b in bits if not 90 <= off + b[1] // 16 <= 92}


def bitname(b):
    return "%02d_%02d" % b


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("build", nargs="?", default=os.path.join(HERE, "build"))
    ap.add_argument("--types", default="CMT_L,RCLK_CLEM_CLKBUF_L")
    ap.add_argument("--json", help="write the solution here")
    ap.add_argument("--features", default="design.features",
                    help="per-specimen feature file name (kv260_cmt_char writes design.nfeatures)")
    args = ap.parse_args()
    types = args.types.split(",")
    grid = json.load(open(os.path.join(PART_DIR, "tilegrid.json")))
    tiles = {t: v for t, v in grid.items()
             if v["type"] in types and "CLB_IO_CLK" in v.get("bits", {})}

    # instances[type] = [(specimen, tile, {features}, {bits})]
    instances = collections.defaultdict(list)
    specs = sorted(s for s in glob.glob(os.path.join(args.build, "specimen_*"))
                   if os.path.getsize(os.path.join(s, args.features)
                                      if os.path.exists(os.path.join(s, args.features)) else os.devnull))
    for spec in specs:
        feats = collections.defaultdict(set)
        for line in open(os.path.join(spec, args.features)):
            tile, _, feat = line.strip().partition(".")
            feats[tile].add(feat)
        frames = frames_of(spec)
        for t, v in tiles.items():
            entry = v["bits"]["CLB_IO_CLK"]
            instances[v["type"]].append((os.path.basename(spec), t, feats.get(t, set()),
                                         config_bits(tile_bits(frames, entry), entry)))
    print("%d specimens" % len(specs))

    solution, ok = {}, True
    for tt in types:
        inst = instances[tt]
        allf = sorted(set().union(*(i[2] for i in inst)))
        # group features that occur in exactly the same instances
        groups = collections.defaultdict(list)
        for f in allf:
            groups[frozenset(k for k, i in enumerate(inst) if f in i[2])].append(f)
        sol = {}
        for where, fs in groups.items():
            cand = set.intersection(*(inst[k][3] for k in where))
            for k, i in enumerate(inst):
                if k not in where:
                    cand -= i[3]
            sol[tuple(sorted(fs))] = (sorted(cand), len(where))
        print("\n=== %s: %d instances, %d features, %d groups" % (tt, len(inst), len(allf), len(groups)))
        for fs, (bits, n) in sorted(sol.items(), key=lambda kv: kv[0]):
            print("  %-3d %-70s %s" % (n, " = ".join(fs), " ".join(map(bitname, bits)) or "(none)"))
        # every set bit explained?
        unexplained = collections.Counter()
        for spec, t, fs, bits in inst:
            expl = set()
            for g, (gb, _) in sol.items():
                if fs.issuperset(g):
                    expl |= set(gb)
            for b in bits - expl:
                unexplained[b] += 1
                ok = False
        if unexplained:
            print("  UNEXPLAINED bits (instances): " +
                  " ".join("%s(%d)" % (bitname(b), n) for b, n in sorted(unexplained.items())))
        else:
            print("  every set bit is explained")
        solution[tt] = {" ".join(fs): [bitname(b) for b in bits] for fs, (bits, _) in sol.items()}
    if args.json:
        json.dump(solution, open(args.json, "w"), indent=1, sort_keys=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
