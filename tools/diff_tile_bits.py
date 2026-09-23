#!/usr/bin/env python3
"""Compare two bitstreams bit for bit inside named tiles.

This is the `required subset of emitted` test, and it is the only check in this
tree that has ever found a missing feature. The others cannot:

  * tools/check_fasm_vs_uraydb.py proves emitted subset of known. A feature we
    never write is invisible to it by construction.
  * the round trip in designs/make_bitstream.sh is closed loop -- same
    tilegrid, same segbits on both sides -- so a feature we never write is
    never missed, and a wrong base address decodes back to the same wrong
    tile and passes.

Comparing against Vivado is only meaningful where both tools were forced to
the same placement. Logic tiles are not: the two packers put different cells in
different slices, so a diff there is noise. IO tiles ARE, because the XDC LOCs
every pad to a package pin, so the same tile holds the same eight outputs in
both bitstreams. That is why this takes an explicit --tile list rather than
sweeping the die.

Either side may be a prjuray `.frames` file (address, comma-separated 32-bit
words) or the output of `bitread -o` (`.frame 0x...` headers followed by
whitespace-separated words); the format is detected from the first line.

Exits non-zero if any named tile differs.
"""
import argparse
import json
import sys


def load(path):
    """-> {frame address: [32-bit words]}, from either supported format."""
    with open(path) as f:
        text = f.read()
    frames, cur, words = {}, None, []
    if ".frame" in text.split("\n", 1)[0]:
        for line in text.split("\n"):
            line = line.strip()
            if line.startswith(".frame"):
                if cur is not None:
                    frames[cur] = words
                cur, words = int(line.split()[1], 16), []
            elif line:
                words += [int(w, 16) for w in line.split()]
        if cur is not None:
            frames[cur] = words
    else:
        for line in text.split("\n"):
            line = line.strip()
            if not line:
                continue
            addr, _, rest = line.partition(" ")
            frames[int(addr, 16)] = [int(w, 16) for w in rest.split(",") if w.strip()]
    return frames


def tile_bits(frames, entry):
    """The set of (frame offset, bit offset) set inside one tile's window.

    prjuray's tilegrid offsets are in 16-BIT words while a frame is 93 32-bit
    ones (prjuray-tools/prjuray/bitstream.py: WORD_SIZE_BITS = 16,
    FRAME_WORD_COUNT = 93 * 2), so an offset of 99 against a 93-word frame is
    correct, not corruption. The packing is fasm2bit.py:40,53.
    """
    base = int(entry["baseaddr"], 16)
    out = set()
    for fo in range(entry["frames"]):
        fw = frames.get(base + fo)
        if not fw:
            continue
        for bo in range(entry["words"] * 16):
            bitidx = entry["offset"] * 16 + bo
            w16, b16 = bitidx // 16, bitidx % 16
            w32, b32 = w16 // 2, b16 + (w16 & 1) * 16
            if w32 < len(fw) and (fw[w32] >> b32) & 1:
                out.add((fo, bo))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reference", help="the bitstream to match, e.g. Vivado's")
    ap.add_argument("ours")
    ap.add_argument("--tilegrid", required=True)
    ap.add_argument("--tile", action="append", default=[], required=True,
                    help="tile instance to compare; repeatable")
    ap.add_argument("--segbits", help="a segbits_<type>.db to name the differing bits")
    args = ap.parse_args()

    tg = json.load(open(args.tilegrid))
    ref, ours = load(args.reference), load(args.ours)
    print("%s: %d frames; %s: %d frames"
          % (args.reference, len(ref), args.ours, len(ours)))

    owners = {}
    if args.segbits:
        for line in open(args.segbits):
            p = line.split()
            for b in p[1:]:
                fo, bo = b.lstrip("!").split("_")
                owners.setdefault((int(fo), int(bo)), []).append(
                    ("!" if b.startswith("!") else "") + p[0])

    bad = 0
    for name in args.tile:
        entry = tg.get(name)
        if entry is None:
            print("  %s: not in the tilegrid" % name)
            bad += 1
            continue
        bits = entry.get("bits", {}).get("CLB_IO_CLK")
        if not bits or "baseaddr" not in bits:
            print("  %s: no frame window -- cannot compare" % name)
            bad += 1
            continue
        a, b = tile_bits(ref, bits), tile_bits(ours, bits)
        only_ref, only_ours = sorted(a - b), sorted(b - a)
        print("  %-34s reference %3d bits, ours %3d, common %3d"
              % (name, len(a), len(b), len(a & b)))
        if not only_ref and not only_ours:
            continue
        bad += 1
        for label, bits_ in (("MISSING (reference sets, we do not)", only_ref),
                             ("EXTRA   (we set, reference does not)", only_ours)):
            for fo, bo in bits_:
                who = owners.get((fo, bo))
                print("    %s %02d_%d%s"
                      % (label, fo, bo, "  " + ", ".join(who) if who else ""))
    if bad:
        sys.exit("%d tile(s) differ" % bad)
    print("OK: every named tile is bit-identical")


if __name__ == "__main__":
    main()
