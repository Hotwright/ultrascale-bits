#!/usr/bin/env python3
"""Fill the INT interface tiles that 002-tilegrid left without a window.

002 addresses only 95 of the XCK26's 480 INT_INTF_R_PCIE4 tiles (the Y%60
pattern is structural to the fuzzer, see SCOPE-K26.md), and until 2026-10-25
that looked harmless: the tile's routing muxes default to the IMUX path at
all-zero. It is not harmless. The tile has the same OUTPUTS_ENABLED bits as
INT_INTF_LEFT_TERM_PSS (01_21 02_27 03_24), and with them clear nothing that
enters the fabric through it gets there: kv260_icap_idcode read the ICAPE3 as
all-zero until they were set (Vivado sets them on the two tiles whose
LOGIC_OUTS the ICAP drives, designs/kv260_cfg_char).

The window is INT's, one frame column to the right:

    baseaddr = baseaddr(INT_X<x>Y<y>) + 0x100
    frames   = 4
    offset   = offset(INT_X<x>Y<y>), words = 3

The same holds one frame column to the LEFT of INT_X16 for the CMT column's
interface tiles, INT_INTF_L_CMT and INT_INTF_L_IO (002 solved none of
them). Column 0x34 has 4 minors in every row, and Vivado's MMCME4/PLLE4
LOCKED outputs set 01_21 02_27 03_24 there, on the row whose LOGIC_OUTS_CMT0
they leave by (designs/kv260_cmt_char, 2026-10-26):

    baseaddr = baseaddr(INT_X<x>Y<y>) - 0x100

--cross-validate checks that rule against every tile 002 did solve and
refuses to fill unless all of them agree.

    fill_int_intf_tilegrid.py tilegrid.json [--cross-validate] [-o out.json]
"""
import argparse, json, re, sys

INTF_RE = re.compile(r"^(INT_INTF_R_PCIE4|INT_INTF_L_CMT|INT_INTF_L_IO)_X(\d+)Y(\d+)$")
COLUMN = {"INT_INTF_R_PCIE4": 0x100, "INT_INTF_L_CMT": -0x100, "INT_INTF_L_IO": -0x100}


def predict(grid, kind, x, y):
    e = grid.get("INT_X%dY%d" % (x, y), {}).get("bits", {}).get("CLB_IO_CLK")
    if not e:
        return None
    return {"baseaddr": "0x%08X" % (int(e["baseaddr"], 16) + COLUMN[kind]), "frames": 4,
            "offset": e["offset"], "words": 3}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tilegrid")
    ap.add_argument("--cross-validate", action="store_true")
    ap.add_argument("-o", "--output")
    args = ap.parse_args()
    grid = json.load(open(args.tilegrid))
    right = wrong = filled = missing = 0
    for t, v in sorted(grid.items()):
        m = INTF_RE.match(t)
        if not m:
            continue
        p = predict(grid, m.group(1), int(m.group(2)), int(m.group(3)))
        have = v.get("bits", {}).get("CLB_IO_CLK")
        if have:
            if p and int(have["baseaddr"], 16) == int(p["baseaddr"], 16) and \
                    (have["frames"], have["offset"], have["words"]) == (p["frames"], p["offset"], p["words"]):
                right += 1
            else:
                wrong += 1
                print("WRONG %s: have %s, rule says %s" % (t, have, p), file=sys.stderr)
        elif p is None:
            missing += 1
        else:
            v.setdefault("bits", {})["CLB_IO_CLK"] = p
            filled += 1
    print("INT_INTF_R_PCIE4/L_CMT/L_IO: %d solved tiles predicted right, %d wrong; %d filled, %d without an INT window"
          % (right, wrong, filled, missing))
    if wrong:
        return 1
    if args.output and not args.cross_validate:
        json.dump(grid, open(args.output, "w"), indent=4, sort_keys=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
