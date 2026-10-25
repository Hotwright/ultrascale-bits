#!/usr/bin/env python3
"""Per specimen, the CONFIG_SITE bits Vivado set: everything in the
CFG_CONFIG_X35Y120 window (tilegrid.windows) that is not set in base, plus
the INT_INTF_R_PCIE4 OUTPUTS_ENABLED tiles. Frame-ECC halfwords are masked.

    analyze.py [build]
"""
import glob, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from diff_tile_bits import tile_bits  # noqa: E402
from find_frame_window import frames_of  # noqa: E402

GRID = os.path.join(ROOT, "prjuray/database/zynqusp/xck26-sfvc784-2LV-c/tilegrid.json")


def cfg_bits(spec, entry):
    bits = tile_bits(frames_of(os.path.join(spec, "design.bit")), entry)
    return {b for b in bits if not 90 <= b[1] // 16 <= 92}


def main():
    build = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "build")
    grid = json.load(open(GRID))
    entry = grid["CFG_CONFIG_X35Y120"]["bits"]["CLB_IO_CLK"]
    base = cfg_bits(os.path.join(build, "base"), entry)
    print("base: %s" % (" ".join("%02d_%04d" % b for b in sorted(base)) or "(none)"))
    for spec in sorted(glob.glob(os.path.join(build, "*"))):
        name = os.path.basename(spec)
        if name == "base" or not os.path.exists(os.path.join(spec, "design.bit")):
            continue
        b = cfg_bits(spec, entry)
        plus = " ".join("%02d_%04d" % x for x in sorted(b - base)) or "-"
        minus = " ".join("!%02d_%04d" % x for x in sorted(base - b))
        cells = open(os.path.join(spec, "design.cells")).read().split("\n") if os.path.exists(
            os.path.join(spec, "design.cells")) else []
        bel = " ".join(l.split()[-1] for l in cells if l.startswith("CELL"))
        print("%-18s %-28s %s %s" % (name, bel, plus, minus))


if __name__ == "__main__":
    main()
