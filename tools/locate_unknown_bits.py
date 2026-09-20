#!/usr/bin/env python3
"""Attribute the bits bit2fasm could not decode to the tiles that own them.

This is what turns a Vivado reference build into an answer about a specific
tile. `prjuray/utils/fasm_disassembler.py` handles a tile whose type has no
segbits file by returning early -- silently, unless --verbose. Those bits are
never marked solved, so they survive into the per-frame `remaining_bits` and
come out as `unknown_bit` annotations carrying frame, word and bit index but
NO tile name. And --verbose's `missing_segbits` warning fires once per tile
TYPE, not per instance, so it cannot tell you which instance was configured.

Hence this: a tile's CLB_IO_CLK entry defines a window -- frames
[baseaddr, baseaddr + frames), words [offset, offset + words) -- and every
unknown bit falls in exactly one. Mapping them back answers the question the
reference build exists to ask:

    does Vivado set any bit in RCLK_CLEM_CLKBUF_L_X15Y149?

If it does, the enable our FASM emits there is real and dropping it breaks the
clock. If it sets none, the feature is ours to stop emitting.

Note the dependency: a tile with no base address owns no window, so its bits
are attributed to nothing and it looks innocent. Run tools/fill_rclk_baseaddr.py
first -- on an unfilled tilegrid this tool cannot see the very tiles it is for.

Usage:
  bit2fasm.py --verbose ... > ref.fasm
  locate_unknown_bits.py ref.fasm [--tilegrid PATH] [--tile NAME]...
"""
import argparse
import collections
import json
import os
import re
import sys

UNKNOWN = re.compile(r'unknown_bit\s*=\s*"([0-9a-fA-F]+)_(\d+)_(\d+)"')


def load_windows(tilegrid):
    """(baseaddr, frames, offset, words) -> tile name, per bus."""
    out = []
    for name, t in tilegrid.items():
        for bus, b in (t.get("bits") or {}).items():
            if not all(k in b for k in ("baseaddr", "frames", "offset", "words")):
                continue
            out.append((int(b["baseaddr"], 0), b["frames"],
                        b["offset"], b["words"], name, t["type"]))
    return out


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("fasm", help="output of bit2fasm.py --verbose")
    ap.add_argument("--tilegrid", default=os.path.join(
        os.environ.get("URAY_FAMILY_DIR", ""),
        os.environ.get("URAY_PART", ""), "tilegrid.json"))
    ap.add_argument("--tile", action="append", default=[],
                    help="report only these tiles (repeatable)")
    args = ap.parse_args()

    with open(args.tilegrid) as f:
        grid = json.load(f)
    windows = load_windows(grid)
    print(f"{args.tilegrid}: {len(grid)} tiles, {len(windows)} with a"
          f" frame window")
    no_window = [n for n, t in grid.items()
                 if t["type"].startswith("RCLK_")
                 and not (t.get("bits") or {}).get("CLB_IO_CLK")]
    if no_window:
        print(f"  WARNING: {len(no_window)} RCLK tiles have no frame window."
              " Bits in them cannot be attributed;")
        print("           run tools/fill_rclk_baseaddr.py first."
              f" e.g. {no_window[0]}")

    bits = []
    with open(args.fasm) as f:
        for line in f:
            m = UNKNOWN.search(line)
            if m:
                bits.append((int(m.group(1), 16), int(m.group(2)),
                             int(m.group(3))))
    print(f"{args.fasm}: {len(bits)} undecoded bit(s)")
    if not bits:
        print("  nothing undecoded -- either everything is characterised or"
              " bit2fasm was run without --verbose")
        return 0

    per_tile = collections.Counter()
    unattributed = 0
    for frame, word, _bit in bits:
        for base, frames, off, words, name, _ty in windows:
            if base <= frame < base + frames and off <= word < off + words:
                per_tile[name] += 1
                break
        else:
            unattributed += 1

    if args.tile:
        print("\nrequested tiles:")
        for name in args.tile:
            n = per_tile.get(name, 0)
            known = name in grid
            win = known and (grid[name].get("bits") or {}).get("CLB_IO_CLK")
            state = ("no frame window -- cannot tell" if known and not win
                     else "not in the tilegrid" if not known
                     else f"{n} undecoded bit(s)")
            print(f"  {name:40s} {state}")
        return 0

    per_type = collections.Counter()
    for name, n in per_tile.items():
        per_type[grid[name]["type"]] += n
    print(f"\nundecoded bits by tile type ({unattributed} attributed to no"
          f" tile):")
    for ty, n in per_type.most_common(20):
        inst = sum(1 for name in per_tile if grid[name]["type"] == ty)
        print(f"  {n:7d}  in {inst:4d} instance(s)  {ty}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
