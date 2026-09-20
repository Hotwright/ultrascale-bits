#!/usr/bin/env python3
"""Audit 002-tilegrid's .tdb files before add_tdb.py consumes them.

add_tdb.py is unforgiving in a way that hides its own diagnosis. It feeds every
address token to int(x, 16) and asserts `frame % 0x100 == 0`, so a single bad
line out of 13920 aborts the whole tilegrid build with either

    ValueError: invalid literal for int() with base 16: '<const0>'
    AssertionError: Unaligned frame at 0x00001FF8

neither of which names the file or the tile. Worse, the two failures want
opposite fixes, and both are *expected* at low rates:

  <const0>        segmatch could not solve the tag because it was never 1 in
                  any specimen (segmatch.cc: `if (!count1)`). With N random
                  specimens that happens with probability 2**-N per tile, so
                  over 13920 CLE tiles at N=15 you expect ~0.4 of them. Also
                  <const1> and "<K candidates>" when several bits still fit.

  unaligned       segmatch solved the tag to a *wrong* bit. The tag's
                  DFRAME/DWORD deltas then land the base off a 0x100 boundary,
                  which is the only reason we ever notice.

This tool reports both per sub-fuzzer, and - the part that matters - says
whether each broken tile is RECOVERABLE, meaning the other tiles of its column
agree unanimously on a base address. A column of ~235 tiles voting one way is
far better evidence than the single fuzzed bit that was lost.

Exit code is 1 only if something is broken AND not recoverable.
"""
import argparse, collections, json, os, re, sys

TILE_RE = re.compile(r"^(?P<type>.+)_X(?P<x>\d+)Y(?P<y>\d+)$")
ROW_FIELD = 0xC0000          # frame row (clock region); not part of the column


def parse(path):
    """Yield (tile, x, y, base|None, problem|None) for each line of a .tdb."""
    for line in open(path):
        tag, _, addr = line.strip().partition(" ")
        if not tag:
            continue
        tile = tag.split(".")[0]
        m = TILE_RE.match(tile)
        if not m:
            continue
        x, y = int(m.group("x")), int(m.group("y"))
        if not addr or addr.startswith("<"):
            yield tile, x, y, None, addr or "<empty>"
            continue
        try:
            frame = int(addr.split("_")[0], 16)
        except ValueError:
            yield tile, x, y, None, "unparsable %r" % addr
            continue
        # Mirror add_tdb.load_db's delta handling EXACTLY, AUTO_FRAME included.
        # An earlier version of this tool applied only DFRAME and duly declared
        # every AUTO_FRAME tag unaligned - 765 false positives, because
        # AUTO_FRAME is precisely the instruction to round the frame down to a
        # 0x100 boundary, so such a tag can never be unaligned.
        for part in tag.split(".")[1:]:
            if part == "AUTO_FRAME":
                frame -= frame % 0x100
                continue
            k, _, v = part.partition(":")
            if k == "DFRAME":
                frame -= int(v, 16)
        if frame % 0x100:
            yield tile, x, y, None, "unaligned 0x%x" % frame
            continue
        yield tile, x, y, frame, None


def audit(build_dir, verbose=False):
    tdbs = sorted(f for f in os.listdir(".")
                  if os.path.isfile(os.path.join(f, build_dir,
                                                 "segbits_tilegrid.tdb")))
    # Column votes are pooled across ALL sub-fuzzers: the INT columns are split
    # between clel_int and clem_int, so neither alone sees a whole column.
    votes = collections.defaultdict(collections.Counter)   # (type,x) -> base
    problems = []
    rows = []
    for sub in tdbs:
        path = os.path.join(sub, build_dir, "segbits_tilegrid.tdb")
        ok = bad = 0
        for tile, x, y, base, why in parse(path):
            ttype = TILE_RE.match(tile).group("type")
            if base is None:
                problems.append((sub, tile, ttype, x, y, why)); bad += 1
            else:
                votes[(ttype, x)][base & ~ROW_FIELD] += 1; ok += 1
        rows.append((sub, ok + bad, ok, bad))

    print("%-24s %7s %7s %7s" % ("sub-fuzzer", "lines", "ok", "broken"))
    for sub, n, ok, bad in rows:
        print("%-24s %7d %7d %7d%s" % (sub, n, ok, bad, "  <--" if bad else ""))

    if not problems:
        print("\nno unsolved or mis-solved tags; add_tdb.py will not choke")
        return 0

    recoverable, orphan = [], []
    for sub, tile, ttype, x, y, why in problems:
        v = votes.get((ttype, x))
        if v and len(v) == 1:
            base, n = v.most_common(1)[0]
            recoverable.append((tile, why, base, n))
        else:
            orphan.append((tile, ttype, x, why, len(v) if v else 0))

    print("\n%d broken tag(s): %d recoverable from their column, %d not"
          % (len(problems), len(recoverable), len(orphan)))
    if verbose:
        for tile, why, base, n in recoverable[:20]:
            print("  OK   %-16s %-20s column base 0x%05x (%d tiles agree)"
                  % (tile, why, base, n))
    if orphan:
        cols = collections.Counter((t, x) for _, t, x, _, _ in orphan)
        print("\nNOT recoverable - no unanimous column base:")
        for (ttype, x), n in sorted(cols.items()):
            print("  %-12s column X%-3d %4d tile(s) - the whole column is "
                  "unsolved" % (ttype, x, n))
        print("\nThese need a base address from the column-owning model "
              "(tools/fill_rclk_baseaddr.py), not from their own column.")
    return 1 if orphan else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build-dir", default=None,
                    help="build_<part> (default: from $URAY_PART)")
    ap.add_argument("--fuzzer-dir", default=None,
                    help="002-tilegrid directory (default: cwd)")
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    bd = a.build_dir or ("build_" + os.environ.get("URAY_PART", ""))
    if not bd or bd == "build_":
        sys.exit("need --build-dir or $URAY_PART")
    if a.fuzzer_dir:
        os.chdir(a.fuzzer_dir)
    sys.exit(audit(bd, a.verbose))


if __name__ == "__main__":
    main()
