#!/usr/bin/env python3
"""Give the site-less RCLK tiles a frame base address that 002-tilegrid cannot.

002-tilegrid learns a tile's base address by putting something in one of its
sites and seeing which frame changed. A tile type with no sites can never be
fuzzed that way, so prjuray fills those in by hand, in
fuzzers/002-tilegrid/generate_full.py -- and by hand means only the tile types
the ZU3EG has. `propagate_RCLK_bits_in_row` covers exactly RCLK_AMS_CFGIO and
`propagate_XIPHY_bits_in_column` exactly RCLK_XIPHY_OUTER_RIGHT.

The XCK26 is the ZU5EV, and it has RCLK tile types the ZU3EG does not:
RCLK_CLEM_CLKBUF_L (8 instances) and RCLK_RCLK_XIPHY_INNER_FT (4), both with
zero sites. Without a base address a feature in them can be neither assembled
by fasm2bit.py nor decoded by bit2fasm.py nor solved by any later fuzzer --
they are invisible, not merely uncharacterised. Two of the features our FASM
emits live in those tiles, on the clock spine.

The rule, derived from the data rather than assumed
---------------------------------------------------
prjuray's existing rule is `baseaddr + dx * 0x100`, and its own docstring
hedges it ("in some cases"). It is wrong: on the ZU3EG only 43 of 71 steps
along an RCLK row match, because grid_x counts tiles and not all tiles own a
frame column.

What does hold is that base address advances by exactly 0x100 per
COLUMN-OWNING tile as you walk a row left to right. Some types own one column,
some own none (NULL, and the RCLK_CBRK_M12BUF_* break tiles), and at least one
owns two.

So this script does not hardcode that table -- it cannot, since a type the
reference die lacks could never be tabulated in advance. Each pair of
consecutive known addresses in a row constrains how many columns the tiles
between them own, and the whole system is reduced once by exact Gaussian
elimination over rationals.

**It does not solve for individual widths, and trying to was a mistake.** The
system does not determine them: on the ZU3EG only 13 of 23 are pinned, because
types like RCLK_CLEL_R_L appear solely in pairs summing to 2 -- with
RCLK_BRAM_INTF_TD_L, with RCLK_CLEL_L_L, with RCLK_BRAM_INTF_L -- so 1+1 and
0+2 fit the data equally. An earlier version brute-forced one assignment that
fitted all 212 constraints and reported it as the answer, which looked like a
clean result and was really a coin flip.

An individual width is not what filling needs. It needs the SUM of widths
along a span from a known address to a target tile, and a sum is determined
exactly when its span vector lies in the row space of the constraints -- which
it often is while its parts are free. So the model answers spans, not widths.
The walk therefore accumulates past a tile whose own width is unknown rather
than stopping at it, and a second pass walks leftward from the anchor on the
other side. Those two changes took the fill from 12 tiles to 57.

Validation
----------
The model fits 212/212 constraints in-sample, which proves consistency and
nothing more.

--cross-validate is the test that matters, because it reproduces the actual
situation: it deletes every base address of one tile type, refits without
them, predicts them back, and compares. Over all 15 RCLK types and 215
addresses on the ZU3EG:

    107 predicted correctly, 0 predicted wrongly, 108 not predicted

**Zero wrong is the property to rely on**, and it is structural rather than
lucky: an address is assigned only where the span is pinned, so an
underdetermined stretch yields no prediction instead of a wrong one. A guessed
width would shift every address after it with nothing to show for it.

**The 108 are worth understanding before trusting a fill.** They are almost
all RCLK_INT_L (75) and RCLK_INT_R (24), which are the anchors nearly
everywhere: holding them out removes the very constraints that would pin them.
That is not the situation here.

**One thing holdout cannot test, by construction.** It can only hold out a
type that has addresses somewhere, and RCLK_CLEM_CLKBUF_L has none on any
characterised die -- that is the whole problem. So its fill is never validated
directly; what the holdout establishes is that the method is right for types
*in that position*, which is evidence by analogy rather than proof. The same
caveat applies to any type the reference die lacks, and to break tiles like
RCLK_CBRK_M12BUF_L that are never addressed anywhere.

What *is* the situation here is a site-less type sandwiched between anchors,
and those survive the holdout cleanly: RCLK_DSP_INTF_CLKBUF_L scores 3/3 and
RCLK_DSP_INTF_L 6/6. RCLK_CLEM_CLKBUF_L sits at grid dx=1 from an RCLK_INT_L
(32 sites, addressed directly by 002) and dx=2 from an RCLK_DSP_INTF_L, which
is the same shape. Whether it is actually pinned depends on those neighbours
carrying addresses on this die, which is knowable only once 002-tilegrid
finishes. If it is not pinned, the script fills nothing and says so -- it does
not invent an address.

Usage:
  fill_rclk_baseaddr.py --self-test [TILEGRID]       # fit and report
  fill_rclk_baseaddr.py --cross-validate [TILEGRID]  # hold out each type
  fill_rclk_baseaddr.py IN.json OUT.json             # fill and write
"""
import argparse
import collections
import os
import re
from fractions import Fraction
import json
import sys

STEP = 0x100
MAX_COLUMNS = 3  # RCLK_XIPHY_OUTER_RIGHT owns 3; that is the observed maximum.


def part_frame_counts(path):
    """bus -> {column index: frame_count}, from part.yaml.

    A filled entry needs `frames` as well as `baseaddr`, and `frames` is not
    something the span model can produce -- it is how many frames the tile's
    configuration column holds. part.yaml has exactly that, and the column
    index is carried in the base address itself.

    Verified on the ZU3EG: frames == frame_count[(baseaddr >> 8) & 0x3ff] for
    all 15712 tiles that carry a frame count, across both buses. Every row
    carries an identical column map on both dies, so the row field need not be
    decoded at all. The mask is 10 bits rather than the 7 the ZU3EG's 104
    columns would need, because the XCK26 has 134.
    """
    out, row, bus, col = {}, None, None, None
    with open(path) as f:
        for line in f:
            m = re.match(r"^  (\d+): !", line)
            if m:
                row = int(m.group(1))
                continue
            m = re.match(r"^      (\w+): !", line)
            if m:
                bus = m.group(1)
                out.setdefault(bus, {})
                continue
            m = re.match(r"^          (\d+): !", line)
            if m:
                col = int(m.group(1))
                continue
            m = re.match(r"^            frame_count: (\d+)", line)
            if m and row == 0:
                out[bus][col] = int(m.group(1))
    return out


BASEADDR_COLUMN_SHIFT = 8
BASEADDR_COLUMN_MASK = 0x3FF


def rclk_offset_words(grid):
    """The (offset, words) every RCLK tile shares, or None if they differ.

    Measured rather than assumed: on the ZU3EG all 215 addressed RCLK tiles
    carry (93, 3), while ordinary tiles vary by position within the column. If
    a die ever breaks that uniformity this returns None and the fill refuses,
    which is better than writing a plausible wrong offset.
    """
    seen = collections.Counter()
    for t in grid.values():
        if not t["type"].startswith("RCLK_"):
            continue
        b = (t.get("bits") or {}).get("CLB_IO_CLK")
        if b and "offset" in b and "words" in b:
            seen[(b["offset"], b["words"])] += 1
    if len(seen) != 1:
        return None, seen
    return next(iter(seen)), seen


def load_rows(grid):
    """grid_y -> [(grid_x, tile_name, type, baseaddr or None)], sorted by x."""
    rows = collections.defaultdict(list)
    for name, t in grid.items():
        b = (t.get("bits") or {}).get("CLB_IO_CLK")
        ba = int(b["baseaddr"], 0) if b and "baseaddr" in b else None
        rows[t["grid_y"]].append((t["grid_x"], name, t["type"], ba))
    for r in rows.values():
        r.sort()
    return rows


def constraints(rows):
    """How many columns the tiles between two known addresses own.

    The span is half-open on the left and CLOSED on the right: the destination
    tile's own width is part of the delta. Excluding it looks equivalent -- it
    just shifts every count by one -- but it is not, because a type that always
    carries its own address then never appears in any constraint and its width
    is left unknown. Closing the interval constrains those types too, which is
    most of them.
    """
    out, types = [], set()
    for r in rows.values():
        known = [i for i, (_, _, ty, ba) in enumerate(r)
                 if ba is not None and ty.startswith("RCLK_")]
        for i1, i2 in zip(known, known[1:]):
            d = r[i2][3] - r[i1][3]
            if d <= 0 or d % STEP:
                continue
            span = collections.Counter(r[i][2] for i in range(i1 + 1, i2 + 1))
            out.append((span, d // STEP))
            types |= set(span)
    return out, sorted(types)


class ColumnModel:
    """The constraint system, reduced once, answering spans rather than widths.

    Each constraint says: over the tiles between two known addresses, the
    widths sum to a known number of columns. That is a linear system in the
    per-type widths, and the obvious thing is to solve it for each width.

    It does not solve. On the ZU3EG only 13 of 23 widths are determined; the
    other ten appear solely in combinations. An earlier version brute-forced
    an assignment that fitted every constraint and reported it as the answer,
    which was wrong in a quiet way -- several different assignments fit the
    same data equally well, and picking one would have filled addresses on a
    coin flip.

    But an individual width is not what filling needs. It needs the SUM of
    widths along a span from a known address to a target tile, and a sum can
    be determined even when its parts are not: it is determined exactly when
    the span vector lies in the row space of the constraints. So this class
    reduces the system once and answers that question directly, which both
    avoids the guess and fills strictly more than solving per-type would.
    """

    def __init__(self, cons, types):
        self.types = sorted(types)
        idx = {t: k for k, t in enumerate(self.types)}
        n = len(self.types)
        rows = []
        for cnt, rhs in cons:
            row = [Fraction(0)] * (n + 1)
            row[-1] = Fraction(rhs)
            for t, v in cnt.items():
                row[idx[t]] += v
            if any(row[:n]):
                rows.append(row)
        # NULL is the absence of a tile, so pin it rather than leave it free.
        if "NULL" in idx:
            row = [Fraction(0)] * (n + 1)
            row[idx["NULL"]] = Fraction(1)
            rows.append(row)

        self.pivots = []          # (row index, column index)
        r = 0
        for c in range(n):
            piv = next((k for k in range(r, len(rows)) if rows[k][c]), None)
            if piv is None:
                continue
            rows[r], rows[piv] = rows[piv], rows[r]
            lead = rows[r][c]
            rows[r] = [x / lead for x in rows[r]]
            for k in range(len(rows)):
                if k != r and rows[k][c]:
                    f = rows[k][c]
                    rows[k] = [a - f * b for a, b in zip(rows[k], rows[r])]
            self.pivots.append((r, c))
            r += 1
            if r == len(rows):
                break
        self.rows = rows
        self.idx = idx
        self.n = n

    def span_columns(self, span):
        """Columns spanned by this multiset of tile types, or None if free."""
        vec = [Fraction(0)] * self.n
        for t, v in span.items():
            if t not in self.idx:
                return None          # a type the constraints never mention
            vec[self.idx[t]] += v
        acc = Fraction(0)
        for r, c in self.pivots:
            if vec[c]:
                f = vec[c]
                vec = [a - f * b for a, b in zip(vec, self.rows[r][:self.n])]
                acc += f * self.rows[r][-1]
        if any(vec):
            return None              # not in the row space: undetermined
        return acc if acc.denominator == 1 else None

    def width(self, tile_type):
        return self.span_columns(collections.Counter({tile_type: 1}))

    def fits(self, cons):
        ok = 0
        for cnt, rhs in cons:
            v = self.span_columns(cnt)
            if v is not None and v == rhs:
                ok += 1
        return ok


def solve(cons, types):
    """Back-compatible wrapper: the model plus how much of the data it fits."""
    m = ColumnModel(cons, types)
    return m.fits(cons), m


def rclk_rows(rows):
    """Only the rows the column model was fitted on.

    The model is derived from RCLK anchors, so it says nothing about an
    ordinary INT/CLEM row -- applying it there produced 846 spurious
    disagreements the first time round, which is how this filter got written.
    """
    return {y: r for y, r in rows.items()
            if any(ty.startswith("RCLK_") and ba is not None
                   for _, _, ty, ba in r)}


def fill(rows, model, report, contradictions=None):
    """Walk each row from every known address, assigning what the model pins.

    The walk accumulates the multiset of tile types crossed and asks the model
    how many columns that span is worth. A span whose value the constraints do
    not determine ends the walk: filling past it would place every later tile
    on a guess. `contradictions` collects the one thing that must block a
    write -- a derived address disagreeing with one already measured.
    """
    filled = 0
    if contradictions is None:
        contradictions = []
    undetermined = collections.Counter()
    for y, r in sorted(rclk_rows(rows).items()):
        for i, (x, name, ty, ba) in enumerate(r):
            if ba is None:
                continue
            span = collections.Counter()
            for j in range(i + 1, len(r)):
                xj, namej, tyj, baj = r[j]
                span[tyj] += 1
                d = model.span_columns(span)
                if baj is not None:
                    if d is not None and ba + int(d) * STEP != baj:
                        contradictions.append(
                            f"  row y={y}: {name} -> {namej} spans {int(d)}"
                            f" column(s), giving 0x{ba + int(d) * STEP:08x},"
                            f" but the tilegrid says 0x{baj:08x}")
                    break
                if d is None:
                    # NOT a reason to stop. An individual width is often free
                    # while a longer span containing it is pinned: on the
                    # ZU3EG RCLK_CLEL_R_L only ever appears in pairs summing
                    # to 2, so {CLEL_R_L} is undetermined but
                    # {CLEL_R_L, CLEM_L} is 2. Stopping here cost 60 walks and
                    # most of the fill.
                    undetermined[tyj] += 1
                    continue
                if tyj.startswith("RCLK_"):
                    r[j] = (xj, namej, tyj, ba + int(d) * STEP)
                    filled += 1
    # A second pass leftwards: a tile the forward walk could not pin may be
    # pinned by the span back to the anchor on its other side.
    for y, r in sorted(rclk_rows(rows).items()):
        for i in range(len(r) - 1, -1, -1):
            x, name, ty, ba = r[i]
            if ba is None:
                continue
            span = collections.Counter()
            for j in range(i - 1, -1, -1):
                xj, namej, tyj, baj = r[j]
                span[r[j + 1][2]] += 1
                d = model.span_columns(span)
                if baj is not None:
                    break
                if d is None:
                    continue
                if tyj.startswith("RCLK_"):
                    r[j] = (xj, namej, tyj, ba - int(d) * STEP)
                    filled += 1
    for t, n in undetermined.most_common():
        report.append(f"  span undetermined at {t} ({n} tiles left unfilled)")
    return filled


def cross_validate(rows):
    """Hold out one tile type's addresses at a time and predict them back."""
    present = collections.Counter(
        ty for r in rclk_rows(rows).values() for _, _, ty, ba in r
        if ba is not None and ty.startswith("RCLK_"))
    print(f"holding out each of {len(present)} RCLK tile types in turn\n")
    print(f"{'tile type':30s} {'held':>5} {'right':>6} {'wrong':>6} {'no pred':>8}")
    total_right = total_wrong = total_none = 0
    for held in sorted(present):
        blinded = {y: [(x, n, ty, None if ty == held else ba)
                       for x, n, ty, ba in r]
                   for y, r in rows.items()}
        cons, types = constraints(blinded)
        if not cons:
            continue
        _, m = solve(cons, types)
        # Keep the contradictions: a model refitted without one type can
        # disagree with anchors that remain, and discarding that would hide a
        # genuine failure behind a clean-looking holdout score.
        contra = []
        fill(blinded, m, [], contra)
        if contra:
            print(f"  ({held}: {len(contra)} contradiction(s) against"
                  " surviving anchors)")
        right = wrong = none = 0
        truth = {n: ba for r in rows.values() for _, n, ty, ba in r
                 if ty == held and ba is not None}
        got = {n: ba for r in blinded.values() for _, n, ty, ba in r
               if ty == held}
        for n, ba in truth.items():
            if got.get(n) is None:
                none += 1
            elif got[n] == ba:
                right += 1
            else:
                wrong += 1
        total_right += right; total_wrong += wrong; total_none += none
        flag = "  <-- WRONG" if wrong else ""
        print(f"{held:30s} {present[held]:5d} {right:6d} {wrong:6d}"
              f" {none:8d}{flag}")
    print(f"\n{'TOTAL':30s} {'':5s} {total_right:6d} {total_wrong:6d}"
          f" {total_none:8d}")
    print("\nA type with 0 right and all 'no pred' owns no column the model can"
          "\nsee -- it is skipped, not mispredicted, which is the safe failure.")
    return 1 if total_wrong else 0


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tilegrid", nargs="?")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--self-test", action="store_true",
                    help="fit and report only; write nothing")
    ap.add_argument("--part-yaml",
                    help="part.yaml for `frames` (default: beside the tilegrid)")
    ap.add_argument("--cross-validate", action="store_true",
                    help="hold out each tile type's addresses and predict them back")
    args = ap.parse_args()

    path = args.tilegrid or (
        "prjuray-db/zynqusp/xczu3eg-sbva484-1-e/tilegrid.json")
    with open(path) as f:
        grid = json.load(f)
    print(f"{path}: {len(grid)} tiles")

    rows = load_rows(grid)
    if args.cross_validate:
        return cross_validate(rows)
    cons, types = constraints(rows)
    if not cons:
        sys.exit("no RCLK rows with two or more known base addresses --"
                 " 002-tilegrid has not produced addresses yet")
    ok, model = solve(cons, types)
    print(f"column model fits {ok}/{len(cons)} constraints")
    unres = []
    for t in types:
        w = model.width(t)
        print(f"  {'?' if w is None else int(w)}  {t}")
        if w is None:
            unres.append(t)
    if unres:
        print(f"  ({len(unres)} individual width(s) undetermined by the data."
              " Spans containing them may still be.)")
    if ok < len(cons):
        print(f"  ({len(cons) - ok} constraint(s) unexplained -- see below)")

    report, contradictions = [], []
    rr = rclk_rows(rows)
    print(f"RCLK rows: {sorted(rr)}")
    before = sum(1 for r in rr.values() for _, _, _, ba in r if ba is not None)
    filled = fill(rows, model, report, contradictions)
    print(f"\nknown addresses: {before}; would fill {filled} more")
    for line in report[:10]:
        print(line)
    if len(report) > 10:
        print(f"  ... {len(report) - 10} more notes")
    if contradictions:
        print(f"\nCONTRADICTIONS ({len(contradictions)}) -- the model"
              " disagrees with addresses the tilegrid already holds:")
        for line in contradictions[:10]:
            print(line)

    # Name what this was built for, so a run on the target die says plainly
    # whether the two tile types came out with an address.
    for want in ("RCLK_CLEM_CLKBUF_L", "RCLK_RCLK_XIPHY_INNER_FT"):
        got = [(n, ba) for r in rows.values() for _, n, ty, ba in r
               if ty == want]
        have = sum(1 for _, ba in got if ba is not None)
        print(f"{want}: {len(got)} instances, {have} with an address")

    if args.self_test or not args.out:
        if not args.self_test:
            print("\n(no output file given -- nothing written)")
        return 1 if contradictions else 0

    if contradictions:
        print("\nrefusing to write: a derived address contradicts a measured"
              " one, so the column model is wrong for this die.")
        return 1

    # A filled entry must look like a measured one. Database.grid(),
    # fasm_assembler and bit2fasm all expect frames/offset/words beside
    # baseaddr; writing baseaddr alone would produce a tilegrid that fails on
    # exactly the tiles this exists to fix.
    part_yaml = args.part_yaml or os.path.join(os.path.dirname(path), "part.yaml")
    if not os.path.exists(part_yaml):
        print(f"\nrefusing to write: no {part_yaml}, so `frames` cannot be"
              " derived")
        return 1
    fc = part_frame_counts(part_yaml)
    ow, seen = rclk_offset_words(grid)
    if ow is None:
        print(f"\nrefusing to write: addressed RCLK tiles do not agree on"
              f" (offset, words): {dict(seen)}")
        return 1
    offset, words = ow
    print(f"part.yaml: {sum(len(v) for v in fc.values())} columns;"
          f" RCLK (offset, words) = ({offset}, {words})")

    written = 0
    for r in rows.values():
        for _, name, ty, ba in r:
            if ba is None:
                continue
            bits = grid[name].setdefault("bits", {})
            if "CLB_IO_CLK" in bits:
                continue
            col = (ba >> BASEADDR_COLUMN_SHIFT) & BASEADDR_COLUMN_MASK
            frames = fc.get("CLB_IO_CLK", {}).get(col)
            if frames is None:
                print(f"  {name}: no frame_count for column {col} -- skipped")
                continue
            bits["CLB_IO_CLK"] = {
                "baseaddr": f"0x{ba:08X}",
                "frames": frames,
                "offset": offset,
                "words": words,
            }
            written += 1
    print(f"filled {written} tile(s) with a complete CLB_IO_CLK entry")
    with open(args.out, "w") as f:
        json.dump(grid, f, indent=2, sort_keys=True)
    print(f"\nwrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
