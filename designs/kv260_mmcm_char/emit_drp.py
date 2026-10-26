#!/usr/bin/env python3
"""Write the MMCM/PLL site features as segbits_cmt_l add-feature lines.

  CMT_L.<site>.<REG>[k]         bit k of a DRP register (regmap.json,
                                verify_regs.py: every register of every
                                sample predicted exactly)
  CMT_L.<site>.IN_USE           the bits every used site sets and no unused
                                one does (this build vs kv260_cmt_char)
  CMT_L.<site>.<attribute>      single-bit attributes (residual.py)
  CMT_L.<site>.ROW_MID[k]       a location bit (see below)

<site> is MMCM_X0Y0, PLL_X0Y0 or PLL_X0Y1, tile-relative. Register names
use '_' for drp.registers()' '.' (CLKOUT0.REG1 -> CLKOUT0_REG1).

ROW_MID: the register at MMCM offset 1824 / PLL offset 0 is 0x88 (in
IN_USE) plus bits that follow the CMT row, not the design's parameters: a
PLL sets bit 1 in the two middle CMTs (rows 1, 2) in every specimen of
kv260_mmcm_char and kv260_cmt_char; the MMCM sets bit 1 there too (one
exception, cmt_char specimen 003, whose clock root is a row higher) and
bit 2 in every cmt_char specimen (CLKIN2 unused) but only in rows 1-2 in
this build (CLKIN2 used). Inferred, not understood: the writer follows the
majority rule.

    emit_drp.py [build] > out.corrections
"""
import collections
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "kv260_clk_char"))
from solve import PART_DIR, config_bits, frames_of, tile_bits  # noqa: E402
import regs  # noqa: E402

SITES = {"MMCM": "MMCM_X0Y0", "PLL0": "PLL_X0Y0", "PLL1": "PLL_X0Y1"}
PLL1 = 672      # PLL_X0Y1 sits 672 offsets above PLL_X0Y0
ATTRS = {
    "MMCM": [("IS_RST_INVERTED", (0, 2640)), ("ZINV_PSINCDEC", (0, 2641)), ("IS_CLKINSEL_INVERTED", (0, 2642)),
             ("STARTUP_WAIT", (0, 2655)), ("ZINV_PWRDWN", (1, 2640)), ("ZINV_PSEN", (1, 2641))],
    "PLL0": [("IS_RST_INVERTED", (0, 576)), ("STARTUP_WAIT", (0, 591)), ("ZINV_PWRDWN", (1, 576))],
}
ATTRS["PLL1"] = [(n, (f, o + PLL1)) for n, (f, o) in ATTRS["PLL0"]]
ROW_MID = {"MMCM": [(1, 1824), (0, 1825)], "PLL0": [(1, 0)], "PLL1": [(1, PLL1)]}


def region(b):
    return "PLL0" if b[1] < PLL1 else "PLL1" if b[1] < 2 * PLL1 else "MMCM"


def bitname(b):
    return "%02d_%02d" % b


def in_use(build):
    """Bits set in every used site here and in no unused one in cmt_char."""
    used = [{b for b in bits if b[0] < 4} for _, _, bits, _ in regs.samples(build)]
    always = set.intersection(*used)
    grid = json.load(open(os.path.join(PART_DIR, "tilegrid.json")))
    tiles = sorted((t for t, v in grid.items() if v["type"] == "CMT_L"), key=lambda t: int(t.split("Y")[-1]))
    seen_unused = collections.defaultdict(set)
    for spec in sorted(glob.glob(os.path.join(HERE, "..", "kv260_cmt_char", "build", "specimen_*"))):
        if not os.path.exists(os.path.join(spec, "design.bit")):
            continue
        locs = open(os.path.join(spec, "loc.txt")).read().split()
        frames = frames_of(spec)
        for r, t in enumerate(tiles):
            e = grid[t]["bits"]["CLB_IO_CLK"]
            bits = {b for b in config_bits(tile_bits(frames, e), e) if b[0] < 4}
            for slot, site in (("MMCM", "MMCM_X0Y%d" % r), ("PLL0", "PLL_X0Y%d" % (2 * r)),
                               ("PLL1", "PLL_X0Y%d" % (2 * r + 1))):
                if site not in locs:
                    seen_unused[slot] |= {b for b in bits if region(b) == slot}
    regmap = json.load(open(os.path.join(HERE, "regmap.json")))
    out = {}
    for slot in SITES:
        cov = {(f + k % 2, base + k // 2) for f, base in regmap[slot].values() for k in range(16)}
        attr = {b for _, b in ATTRS[slot]} | set(ROW_MID[slot])
        out[slot] = sorted(b for b in always if region(b) == slot and b not in seen_unused[slot]
                           and b not in cov and b not in attr)
    return out


def main():
    build = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "build")
    regmap = json.load(open(os.path.join(HERE, "regmap.json")))
    iu = in_use(build)
    print("# MMCM / PLL sites (designs/kv260_mmcm_char: 40 random specimens, every")
    print("# MMCME4_ADV and PLLE4_ADV used with random parameters; emit_drp.py).")
    for slot, site in SITES.items():
        print("# %s" % site)
        print("CMT_L.%s.IN_USE add-feature %s" % (site, " ".join(map(bitname, iu[slot]))))
        for name, b in ATTRS[slot]:
            print("CMT_L.%s.%s add-feature %s" % (site, name, bitname(b)))
        for k, b in enumerate(ROW_MID[slot]):
            print("CMT_L.%s.ROW_MID[%d] add-feature %s" % (site, k, bitname(b)))
        for reg, (f, base) in sorted(regmap[slot].items()):
            for k in range(16):
                print("CMT_L.%s.%s[%d] add-feature %s" % (site, reg.replace(".", "_"), k,
                                                          bitname((f + k % 2, base + k // 2))))


if __name__ == "__main__":
    main()
