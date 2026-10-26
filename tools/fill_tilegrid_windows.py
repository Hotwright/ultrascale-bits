#!/usr/bin/env python3
"""Write the hand-derived frame windows of db-corrections/<family>/tilegrid.windows
into a tilegrid.json (see that file for the evidence behind each line).

    fill_tilegrid_windows.py tilegrid.json windows-file [-o out.json]

A tile that already has a CLB_IO_CLK window must agree with the line, or the
fill is refused: 002 found something we did not expect. A line ending in
"widens" may replace 002's window with a larger one at the same base address
that contains it (CMT_L: 002 saw only the clock row).
"""
import argparse, json, sys


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tilegrid")
    ap.add_argument("windows")
    ap.add_argument("-o", "--output")
    args = ap.parse_args()
    grid = json.load(open(args.tilegrid))
    filled = 0
    for line in open(args.windows):
        line = line.split("#", 1)[0].split()
        if not line:
            continue
        widens = line[-1] == "widens"
        if widens:
            line = line[:-1]
        tile, base, frames, offset, words = line
        want = {"baseaddr": "0x%08X" % int(base, 16), "frames": int(frames),
                "offset": int(offset), "words": int(words)}
        if tile not in grid:
            print("no tile %s in %s" % (tile, args.tilegrid), file=sys.stderr)
            return 1
        have = grid[tile].get("bits", {}).get("CLB_IO_CLK")
        inside = have and int(have["baseaddr"], 16) == int(base, 16) and have["frames"] <= want["frames"] \
            and want["offset"] <= have["offset"] and have["offset"] + have["words"] <= want["offset"] + want["words"]
        if have and not (widens and inside) and (int(have["baseaddr"], 16), have["frames"], have["offset"],
                                                 have["words"]) != (int(base, 16), want["frames"], want["offset"],
                                                                    want["words"]):
            print("%s: tilegrid has %s, windows file says %s" % (tile, have, want), file=sys.stderr)
            return 1
        grid[tile].setdefault("bits", {})["CLB_IO_CLK"] = want
        filled += 1
    print("%d window(s) from %s" % (filled, args.windows))
    if args.output:
        json.dump(grid, open(args.output, "w"), indent=4, sort_keys=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
