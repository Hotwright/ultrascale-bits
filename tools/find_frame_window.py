#!/usr/bin/env python3
"""Find where a primitive's configuration lives: diff two whole bitstreams.

The two designs must be identical except for the primitive under study (or
one of its attributes). Every frame that differs is listed with its decoded
frame address and the words that changed; words inside a known tile window
are attributed to that tile, and the rest are reported as UNCLAIMED, which
is where a tile without a tilegrid window (CFG_CONFIG, DSP, URAM...) shows
up. The frame-ECC halfwords (90-92) are ignored: they follow any change.

    find_frame_window.py A.frames B.frames [--tilegrid tilegrid.json]

Either input may be a bitread `-o` dump or a .bit (run through bitread).
"""
import argparse
import collections
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from diff_tile_bits import load  # noqa: E402

PART_DIR = os.path.join(ROOT, "prjuray/database/zynqusp/xck26-sfvc784-2LV-c")
BITREAD = os.path.join(ROOT, "prjuray/third_party/prjuray-tools/build/tools/bitread")
ECC_WORDS = (45, 46)  # halfwords 90-92 sit in words 45 and 46 (low half)


def frames_of(path):
    if path.endswith(".bit"):
        out = path[:-4] + ".frames"
        if not os.path.exists(out):
            subprocess.run([BITREAD, "--architecture", "UltraScalePlus",
                            "--part_file", os.path.join(PART_DIR, "part.yaml"),
                            "-o", out, path], check=True, stdout=subprocess.DEVNULL)
        path = out
    return load(path)


def far(a):
    """UltraScale+ FAR: block type [26:24], row [23:18], column [17:8], minor [7:0]."""
    return "type %d row %d col %d minor %d" % ((a >> 24) & 7, (a >> 18) & 63, (a >> 8) & 1023, a & 255)


def ecc_mask(w, v):
    if w == 45:
        return 0          # halfwords 90 and 91
    if w == 46:
        return v & 0xFFFF0000  # keep halfword 93, drop 92
    return v


def windows(grid):
    """{base address: [(first frame, frames, offset, words, tile)]}"""
    out = collections.defaultdict(list)
    for t, v in grid.items():
        e = v.get("bits", {}).get("CLB_IO_CLK")
        if e:
            out[int(e["baseaddr"], 16)].append((e["frames"], e["offset"], e["words"], t))
    return out


def owner(win, addr, word):
    col = addr & ~0xFF
    minor = addr & 0xFF
    for frames, off, words, t in win.get(col, ()):
        if minor < frames and off <= word < off + words:
            return t
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--tilegrid", default=os.path.join(PART_DIR, "tilegrid.json"))
    ap.add_argument("--all", action="store_true", help="also list words claimed by known tiles")
    args = ap.parse_args()
    A, B = frames_of(args.a), frames_of(args.b)
    win = windows(json.load(open(args.tilegrid)))
    claimed = collections.Counter()
    unclaimed = collections.defaultdict(list)  # column base -> [(minor, word, xor)]
    for addr in sorted(set(A) | set(B)):
        fa, fb = A.get(addr, []), B.get(addr, [])
        n = max(len(fa), len(fb))
        for w in range(n):
            va = fa[w] if w < len(fa) else 0
            vb = fb[w] if w < len(fb) else 0
            x = ecc_mask(w, va ^ vb)
            if not x:
                continue
            t = owner(win, addr, w)
            if t:
                claimed[t] += bin(x).count("1")
                if args.all:
                    print("  %08x %s  w%-3d %08x  %s" % (addr, far(addr), w, x, t))
            else:
                unclaimed[addr & ~0xFF].append((addr & 0xFF, w, x, va, vb))
    for t, n in sorted(claimed.items()):
        print("claimed  %-28s %d bit(s)" % (t, n))
    for col, rows in sorted(unclaimed.items()):
        minors = sorted({r[0] for r in rows})
        words = sorted({r[1] for r in rows})
        print("UNCLAIMED column %08x (%s): minors %d-%d, words %d-%d, %d word(s)"
              % (col, far(col), minors[0], minors[-1], words[0], words[-1], len(rows)))
        for minor, w, x, va, vb in rows:
            bits = [w * 32 + i for i in range(32) if x >> i & 1]
            print("    minor %-3d word %-3d %08x -> %08x  bits %s" % (minor, w, va, vb, bits))
    return 0


if __name__ == "__main__":
    sys.exit(main())
