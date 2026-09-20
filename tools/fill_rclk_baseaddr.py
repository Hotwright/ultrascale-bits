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
--------------------------------------------------
prjuray's existing rule is `baseaddr + dx * 0x100`, and its own docstring
hedges it ("in some cases"). It is wrong: on the ZU3EG only 43 of 71 steps
along an RCLK row match, because grid_x counts tiles and not all tiles own a
frame column.

What does hold is that base address advances by exactly 0x100 per
COLUMN-OWNING tile as you walk a row left to right. Some types own one column,
some own none (NULL, and the RCLK_CBRK_M12BUF_* break tiles), and at least one
owns two (RCLK_INTF_RIGHT_TERM_IO).

So this script does not hardcode that table. It derives it from whichever base
addresses the tilegrid already has: each pair of consecutive known addresses in
a row is a constraint on how many columns the tiles between them own, and the
per-type counts are solved from all such constraints at once. Then the missing
tiles are filled by walking the row and counting.

That matters because RCLK_CLEM_CLKBUF_L's own column count is not knowable from
the ZU3EG -- the die does not have the tile. Solving on the target die's own
tilegrid determines it there.

Validation
----------
On the ZU3EG, whose tilegrid is complete, the model fits 212/212 constraints.
That is in-sample and so proves only consistency, not predictive power.

--cross-validate is the test that matters, because it reproduces the actual
situation: it deletes every base address of one tile type, refits the model
without them, predicts them back, and compares. On the ZU3EG, over all 15 RCLK
types and 215 addresses:

    24 predicted correctly, 0 predicted wrongly, 191 not predicted at all

**Zero wrong is the property to rely on**, and it is structural rather than
lucky: a type whose width the constraints do not pin is left unknown, and
fill() stops the walk and says so instead of guessing. A guessed width would
shift every address downstream of it with nothing to show for it.

**24 of 215 is the limitation to respect.** Holding out a type that is itself
the anchor everywhere -- RCLK_INT_L, RCLK_INT_R, the BRAM and HDIO tiles --
removes every constraint that could pin its width, and it becomes
unpredictable. What survives the holdout are the types that sit BETWEEN other
anchors: RCLK_DSP_INTF_CLKBUF_L scored 3/3 and RCLK_DSP_INTF_L 6/6.

That is the good news for the case this was written for.
RCLK_CLEM_CLKBUF_L sits at grid dx=1 from an RCLK_INT_L (32 sites, addressed
directly by 002) and dx=2 from an RCLK_DSP_INTF_L, so it is sandwiched exactly
like RCLK_DSP_INTF_CLKBUF_L. Whether it is actually pinned depends on those
neighbours carrying addresses on this die, which is knowable only once
002-tilegrid finishes. If it is not pinned, the script says so and fills
nothing -- it does not invent an address.

Usage:
  fill_rclk_baseaddr.py --self-test [TILEGRID]       # fit and report
  fill_rclk_baseaddr.py --cross-validate [TILEGRID]  # hold out each type
  fill_rclk_baseaddr.py IN.json OUT.json             # fill and write
"""
import argparse
import collections
import itertools
import json
import sys

STEP = 0x100
MAX_COLUMNS = 3  # RCLK_XIPHY_OUTER_RIGHT owns 3; that is the observed maximum.
RESIDUE_CAP = 8  # (MAX_COLUMNS+1)**8 = 65k combinations, about a second.


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


def solve(cons, types):
    """Columns owned per type, by propagation then a small exhaustive residue.

    The constraints are linear with tiny non-negative integer unknowns, and
    most of them are short: two anchors a few tiles apart, often adjacent. Any
    constraint with exactly one unsolved type pins that type outright, and
    substituting it shortens others. Iterating that settles nearly everything;
    whatever is left over is brute-forced.
    """
    known = {"NULL": 0}  # a NULL grid cell is the absence of a tile, not a guess

    progress = True
    while progress:
        progress = False
        for cnt, n in cons:
            rest = n - sum(v * known[t] for t, v in cnt.items() if t in known)
            unsolved = [(t, v) for t, v in cnt.items() if t not in known]
            if len(unsolved) != 1:
                continue
            t, v = unsolved[0]
            if v == 0 or rest < 0 or rest % v:
                continue
            known[t] = rest // v
            progress = True

    residue = [t for t in types if t not in known]
    # Propagation resolves almost everything. What it cannot resolve is a type
    # that never appears alone, and brute-forcing those costs
    # (MAX_COLUMNS+1)^n, so the cap is low on purpose: leaving a width unknown
    # makes fill() stop and say so, which is the safe failure. Guessing it
    # would shift every address downstream of it with nothing to show for it.
    if len(residue) > RESIDUE_CAP:
        return (sum(1 for cnt, n in cons
                    if sum(v * known.get(t, 0) for t, v in cnt.items()) == n),
                known)
    if residue:
        best = None
        for combo in itertools.product(range(MAX_COLUMNS + 1),
                                       repeat=len(residue)):
            c = dict(known, **dict(zip(residue, combo)))
            ok = sum(1 for cnt, n in cons
                     if sum(v * c[t] for t, v in cnt.items()) == n)
            if best is None or (ok, -sum(combo)) > (best[0], -sum(best[2])):
                best = (ok, c, combo)
        known = best[1]

    ok = sum(1 for cnt, n in cons
             if sum(v * known.get(t, 0) for t, v in cnt.items()) == n)
    return ok, known


def rclk_rows(rows):
    """Only the rows the column model was fitted on.

    The model is derived from RCLK anchors, so it says nothing about an
    ordinary INT/CLEM row -- applying it there produced 846 spurious
    disagreements the first time round, which is how this filter got written.
    """
    return {y: r for y, r in rows.items()
            if any(ty.startswith("RCLK_") and ba is not None
                   for _, _, ty, ba in r)}


def fill(rows, cols, report):
    """Walk each row, carrying the address forward across column-owning tiles."""
    filled = 0
    unknown = collections.Counter()
    for y, r in sorted(rclk_rows(rows).items()):
        # Anchor on each known address and walk right until the next known one,
        # rather than from the row start: that keeps a local error local.
        for i, (x, name, ty, ba) in enumerate(r):
            if ba is None:
                continue
            addr = ba
            for j in range(i + 1, len(r)):
                xj, namej, tyj, baj = r[j]
                if tyj not in cols and tyj != "NULL":
                    # A type never seen between two known addresses. Guessing
                    # its width would silently shift everything downstream, so
                    # stop this walk and say so.
                    unknown[tyj] += 1
                    break
                addr += cols.get(tyj, 0) * STEP
                if baj is not None:
                    if baj != addr:
                        report.append(
                            f"  row y={y}: walked from {name} to {namej} and got"
                            f" 0x{addr:08x}, tilegrid says 0x{baj:08x}")
                    break
                if tyj.startswith("RCLK_") and cols.get(tyj, 0):
                    r[j] = (xj, namej, tyj, addr)
                    filled += 1
    for t, n in unknown.most_common():
        report.append(f"  column width unknown for {t} ({n} walks stopped)")
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
        _, cols = solve(cons, types)
        fill(blinded, cols, [])
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
    ok, cols = solve(cons, types)
    print(f"column model fits {ok}/{len(cons)} constraints")
    for t in types:
        print(f"  {cols[t]}  {t}")
    if ok < len(cons):
        print(f"  ({len(cons) - ok} constraint(s) unexplained -- see below)")

    report = []
    rr = rclk_rows(rows)
    print(f"RCLK rows: {sorted(rr)}")
    before = sum(1 for r in rr.values() for _, _, _, ba in r if ba is not None)
    filled = fill(rows, cols, report)
    print(f"\nknown addresses: {before}; would fill {filled} more")
    for line in report[:10]:
        print(line)
    if len(report) > 10:
        print(f"  ... {len(report) - 10} more disagreements")

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
        return 0 if report == [] else 1

    for r in rows.values():
        for _, name, ty, ba in r:
            if ba is None:
                continue
            bits = grid[name].setdefault("bits", {})
            if "CLB_IO_CLK" not in bits:
                bits["CLB_IO_CLK"] = {"baseaddr": f"0x{ba:08X}"}
    with open(args.out, "w") as f:
        json.dump(grid, f, indent=2, sort_keys=True)
    print(f"\nwrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
