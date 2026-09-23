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

Windows are NOT disjoint, so a bit can have more than one owner. On the ZU3EG
13908 (frame, word) cells are claimed twice, every one of them PSS_ALTO
overlapping an INT or RCLK_INT_L -- the PS interface tile covers the same bits
as the interconnect tiles beneath it. An earlier version took the first match
and moved on, which silently picked one owner by dictionary order. Every owner
is now reported and the ambiguity counted, because for the question this tool
answers, "some other tile may account for these bits" is the difference
between a conclusion and a guess.

Usage:
  bit2fasm.py --verbose ... > ref.fasm
  locate_unknown_bits.py ref.fasm [--tilegrid PATH] [--tile NAME]...
  locate_unknown_bits.py --self-test [--tilegrid PATH]

Run --self-test before trusting a result. A bug in the regex or the window
arithmetic reports zero bits, and zero is a meaningful answer here -- it reads
as "Vivado set nothing in that tile", which is the opposite conclusion. The
self-test plants bits at the window edges and just outside them, so an
off-by-one in either direction fails it.
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


def self_test(tilegrid_path):
    """Plant bits with a known answer and check they are attributed to it."""
    import subprocess
    import tempfile
    with open(tilegrid_path) as f:
        grid = json.load(f)
    subject = next((n for n, t in grid.items()
                    if t["type"] == "RCLK_INTF_LEFT_TERM_ALTO"
                    and (t.get("bits") or {}).get("CLB_IO_CLK")), None)
    if subject is None:
        sys.exit("self-test: no addressed RCLK_INTF_LEFT_TERM_ALTO to use")
    b = grid[subject]["bits"]["CLB_IO_CLK"]
    base, frames, off, words = (int(b["baseaddr"], 0), b["frames"],
                                b["offset"], b["words"])
    # Three inside, at both edges and the interior; two just outside, one by a
    # word and one by a frame. Edges are where an inclusive/exclusive slip shows.
    inside = [(base, off), (base + frames - 1, off + words - 1), (base + 1, off + 1)]
    outside = [(base, off - 1), (base + frames, off)]
    lines = [f'{{ unknown_bit = "{f:08x}_{w}_{i}" }}'
             for i, (f, w) in enumerate(inside + outside)]
    with tempfile.NamedTemporaryFile("w", suffix=".fasm", delete=False) as fh:
        fh.write("\n".join(lines) + "\n")
        path = fh.name
    out = subprocess.run(
        [sys.executable, os.path.abspath(__file__), path,
         "--tilegrid", tilegrid_path, "--tile", subject],
        capture_output=True, text=True).stdout
    os.unlink(path)
    print(out.rstrip())
    want = f"{len(inside)} undecoded bit(s)"
    if want not in out:
        sys.exit(f"\nself-test FAILED: expected '{want}' for {subject}")
    if "2 attributed to no tile" in out:
        sys.exit("\nself-test FAILED: outside bits were attributed")
    print(f"\nself-test OK: {len(inside)} planted inside the window were"
          f" attributed to {subject},")
    print(f"              {len(outside)} planted outside it were not")
    return 0


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("fasm", nargs="?", help="output of bit2fasm.py --verbose")
    ap.add_argument("--tilegrid", default=os.path.join(
        os.environ.get("URAY_FAMILY_DIR", ""),
        os.environ.get("URAY_PART", ""), "tilegrid.json"))
    ap.add_argument("--tile", action="append", default=[],
                    help="report only these tiles (repeatable)")
    ap.add_argument("--self-test", action="store_true",
                    help="plant bits with a known answer and verify them")
    args = ap.parse_args()

    if args.self_test:
        return self_test(args.tilegrid)
    if not args.fasm:
        ap.error("a FASM file is required unless --self-test is given")

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
    shared_with = collections.defaultdict(collections.Counter)
    unattributed = ambiguous = 0
    for frame, word, _bit in bits:
        owners = [(name, ty) for base, frames, off, words, name, ty in windows
                  if base <= frame < base + frames
                  and off <= word < off + words]
        if not owners:
            unattributed += 1
            continue
        if len(owners) > 1:
            ambiguous += 1
        for name, _ty in owners:
            per_tile[name] += 1
            for other, _oty in owners:
                if other != name:
                    shared_with[name][other] += 1

    if ambiguous:
        print(f"  {ambiguous} bit(s) fall in more than one tile's window and"
              " are counted for each")

    if args.tile:
        print("\nrequested tiles:")
        for name in args.tile:
            n = per_tile.get(name, 0)
            known = name in grid
            win = known and (grid[name].get("bits") or {}).get("CLB_IO_CLK")
            if not known:
                state = "not in the tilegrid"
            elif not win:
                state = "no frame window -- run fill_rclk_baseaddr.py, cannot tell"
            elif n == 0:
                state = "0 undecoded bits -- Vivado set nothing we cannot explain"
            else:
                state = f"{n} undecoded bit(s)"
            print(f"  {name:44s} {state}")
            for other, k in shared_with.get(name, collections.Counter()).most_common(3):
                print(f"      {k} of them also lie in {other}"
                      " -- ambiguous, not proof")
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
