#!/usr/bin/env python3
"""Read a DRP register (16 bits at frame pair f/f+1, offset base..base+7)
out of each MMCM/PLL sample, next to drp.py's prediction.

    regs.py <slot MMCM|PLL0|PLL1> <frame> <base> [field...]
"""
import collections, glob, json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "kv260_clk_char"))
from solve import PART_DIR, config_bits, frames_of, tile_bits  # noqa
import drp, solve_drp  # noqa


def samples(build="build"):
    grid = json.load(open(os.path.join(PART_DIR, "tilegrid.json")))
    tiles = sorted((t for t, v in grid.items() if v["type"] == "CMT_L"), key=lambda t: int(t.split("Y")[-1]))
    for spec in sorted(glob.glob(os.path.join(build, "specimen_*"))):
        cells = solve_drp.props_of(spec)
        frames = frames_of(spec)
        for r, t in enumerate(tiles):
            e = grid[t]["bits"]["CLB_IO_CLK"]
            bits = config_bits(tile_bits(frames, e), e)
            yield spec, r, bits, cells


def reg(bits, f, base):
    return sum(1 << k for k in range(16) if (f + k % 2, base + k // 2) in bits)


if __name__ == "__main__":
    slot, f, base = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    for spec, r, bits, cells in samples():
        site = "MMCM_X0Y%d" % r if slot == "MMCM" else "PLL_X0Y%d" % (2 * r + int(slot[-1]))
        p = cells[site]
        m = p.get("CLKFBOUT_MULT_F", p.get("CLKFBOUT_MULT"))
        print("%s r%d M=%-8s D=%-4s BW=%-9s reg=%04x" % (os.path.basename(spec), r, m, p.get("DIVCLK_DIVIDE"),
                                                       p.get("BANDWIDTH", "-"), reg(bits, f, base)))
