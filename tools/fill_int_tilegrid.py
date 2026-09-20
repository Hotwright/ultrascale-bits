#!/usr/bin/env python3
"""Fill the INT tiles that 002-tilegrid left without a base address.

On the XCK26, clel_int and clem_int between them solve 10232 of the die's 10320
INT tiles. The 88 they miss are not scattered - they sit at exactly four Y
values:

    Y31, Y91, Y151   15 columns each (the DSP-adjacent ones)   45 tiles
    Y239             all 43 columns (the die's top row)         43 tiles

and two of them, INT_X0Y239 and INT_X7Y151, are used by the reference designs,
so fasm2bit refuses those files until this is filled. (The ZU3EG reference
database has no such gap - all 5940 of its INT tiles are solved - so this is a
property of our run, not of prjuray.)

Nothing here is guessed. A tile's base address splits into a row field (which
clock region) and a column field, and both are available from measurements
elsewhere in the same fuzzer output:

  column field   RCLK_INT_L / RCLK_INT_R sit in the SAME frame column as the
                 INT tiles beside them - that is why add_tdb.py gives them
                 INT's own frames/words. rclk_int solved all 43 columns with
                 zero broken tags, and on the 41 columns where both are solved
                 the two agree 41/41. So the column field is measured, and it
                 covers X34 and X42, whose INT tiles are unsolved end to end.

  row field      a function of Y alone, read off the solved tiles.

  frames/words/offset
                 a function of Y alone (verified: at every one of the 238
                 solved Y values, all 43 columns agree on the same triple).
                 Y31/Y91/Y151 are solved in the other 28 columns, so they are
                 read off directly. Y239 is solved nowhere on this die, and is
                 taken from the read-only ZU3EG reference, where the last row
                 of EVERY clock region has offset 183 (Y59, Y119 and Y179 all
                 do) - consistent with our own Y238 being 180.

--cross-validate hides each solved INT tile in turn and predicts it from the
rest. Anything less than 100% right means the model is wrong and the fill is
refused.
"""
import argparse, collections, json, os, re, sys

INT_RE = re.compile(r"^INT_X(\d+)Y(\d+)$")
RCLK_RE = re.compile(r"^RCLK_INT_[LR]_X(\d+)Y(\d+)$")
ROW_MASK = 0xC0000          # clock-region field of the frame address
COL_MASK = ~ROW_MASK


def load(grid):
    """(column base by X, row field by Y, geometry by Y, solved INT tiles)."""
    colbase = collections.defaultdict(collections.Counter)
    rowfield = collections.defaultdict(collections.Counter)
    geom = collections.defaultdict(collections.Counter)
    solved = {}
    for name, v in grid.items():
        bits = v.get("bits") or {}
        m = INT_RE.match(name) or RCLK_RE.match(name)
        if not m or not bits:
            continue
        x, y = int(m.group(1)), int(m.group(2))
        for blk, b in bits.items():
            base = b["baseaddr"] if isinstance(b["baseaddr"], int) \
                else int(str(b["baseaddr"]), 0)
            colbase[x][base & COL_MASK] += 1
            if INT_RE.match(name):
                rowfield[y][base & ROW_MASK] += 1
                geom[y][(blk, b["frames"], b["words"], b["offset"])] += 1
                solved[name] = (x, y, blk, base, b["frames"], b["words"],
                                b["offset"])
    return colbase, rowfield, geom, solved


def unanimous(counter, what):
    if not counter:
        return None, "%s: no data" % what
    if len(counter) > 1:
        return None, "%s: CONFLICT %s" % (
            what, {hex(k) if isinstance(k, int) else k: v
                   for k, v in counter.items()})
    return counter.most_common(1)[0][0], None


def region_of(y, rowfield):
    """Row field for a Y with no solved tile, from the region layout."""
    known = sorted(rowfield)
    if not known:
        return None, "no solved INT rows at all"
    rows_per = None
    # Infer the region height from where the row field changes.
    edges = [y2 for y1, y2 in zip(known, known[1:])
             if unanimous(rowfield[y1], "")[0] != unanimous(rowfield[y2], "")[0]]
    if edges:
        heights = {e for e in edges}
        first = min(heights)
        rows_per = first
    if not rows_per:
        return None, "cannot infer clock-region height"
    fields = sorted({unanimous(rowfield[k], "")[0] for k in known})
    idx = y // rows_per
    if idx >= len(fields):
        # the die has more regions than we saw solved; extend the arithmetic
        step = fields[1] - fields[0] if len(fields) > 1 else None
        if step is None:
            return None, "only one region seen; cannot extend"
        return fields[0] + idx * step, None
    return fields[idx], None


def reference_geometry(ref_path, y, rows_per):
    """(frames, words, offset) for a Y solved nowhere here, from the reference."""
    if not ref_path or not os.path.exists(ref_path):
        return None, "no reference database given"
    ref = json.load(open(ref_path))
    want = y % rows_per                      # position within its clock region
    acc = collections.Counter()
    for name, v in ref.items():
        m = INT_RE.match(name)
        if not m or not (v.get("bits") or {}):
            continue
        ry = int(m.group(2))
        if ry % rows_per != want:
            continue
        for blk, b in v["bits"].items():
            acc[(blk, b["frames"], b["words"], b["offset"])] += 1
    val, err = unanimous(acc, "reference Y%%%d==%d" % (rows_per, want))
    return val, err


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tilegrid", help="tilegrid_tdb.json to read")
    ap.add_argument("-o", "--output", help="write the filled grid here")
    ap.add_argument("--reference", help="read-only reference tilegrid.json "
                    "(used only for a Y solved nowhere on this die)")
    ap.add_argument("--cross-validate", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()

    grid = json.load(open(a.tilegrid))
    colbase, rowfield, geom, solved = load(grid)
    print("solved INT tiles %d, columns with a base %d, Y values solved %d"
          % (len(solved), len(colbase), len(geom)))

    # Every Y must agree on its geometry across all columns, or the model that
    # geometry depends only on Y is false and nothing here is trustworthy.
    bad = [y for y, c in geom.items() if len(c) > 1]
    if bad:
        sys.exit("geometry is NOT a function of Y alone at Y%s - refusing"
                 % bad[:5])
    rows_per = None
    edges = sorted(rowfield)
    for y1, y2 in zip(edges, edges[1:]):
        if unanimous(rowfield[y1], "")[0] != unanimous(rowfield[y2], "")[0]:
            rows_per = y2
            break
    print("clock-region height: %s rows" % rows_per)

    if a.cross_validate:
        right = wrong = 0
        for name, (x, y, blk, base, fr, wd, off) in sorted(solved.items()):
            cb, e1 = unanimous(
                collections.Counter({k: v for k, v in colbase[x].items()}),
                "col")
            rf, e2 = unanimous(rowfield[y], "row")
            if e1 or e2:
                continue
            if (cb | rf) == base:
                right += 1
            else:
                wrong += 1
                if wrong <= 5:
                    print("  WRONG %s: predicted 0x%05X, measured 0x%05X"
                          % (name, cb | rf, base))
        print("cross-validate: %d right, %d wrong" % (right, wrong))
        if wrong:
            sys.exit("model disagrees with measurement - refusing to fill")

    # Fill.
    filled, refused = [], []
    for name, v in grid.items():
        m = INT_RE.match(name)
        if not m or (v.get("bits") or {}):
            continue
        x, y = int(m.group(1)), int(m.group(2))
        cb, e1 = unanimous(colbase[x], "column X%d" % x)
        if e1:
            refused.append((name, e1)); continue
        if y in rowfield:
            rf, e2 = unanimous(rowfield[y], "row Y%d" % y)
        else:
            rf, e2 = region_of(y, rowfield)
        if e2:
            refused.append((name, e2)); continue
        if y in geom:
            g, e3 = unanimous(geom[y], "geometry Y%d" % y)
            src = "this die"
        else:
            g, e3 = reference_geometry(a.reference, y, rows_per)
            src = "reference"
        if e3:
            refused.append((name, e3)); continue
        blk, fr, wd, off = g
        v["bits"] = {blk: {"baseaddr": "0x%08X" % (cb | rf),
                           "frames": fr, "offset": off, "words": wd}}
        filled.append((name, cb | rf, off, src))

    print("filled %d INT tile(s), refused %d" % (len(filled), len(refused)))
    by = collections.Counter(src for _, _, _, src in filled)
    print("  geometry source: %s" % dict(by))
    if a.verbose:
        for name, base, off, src in filled[:10]:
            print("  %-16s base 0x%08X offset %-4d (%s)" % (name, base, off, src))
    for name, why in refused[:10]:
        print("  REFUSED %s: %s" % (name, why))

    if a.output:
        json.dump(grid, open(a.output, "w"), sort_keys=True, indent=4,
                  separators=(",", ": "))
        print("wrote %s" % a.output)
    return 1 if refused else 0


if __name__ == "__main__":
    sys.exit(main())
