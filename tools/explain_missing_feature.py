#!/usr/bin/env python3
"""Why is a feature missing from prjuray-db: coverage gap, or solved negative?

When check_fasm_vs_uraydb.py reports an emitted feature as unknown, there are
two completely different reasons, and they call for opposite responses:

  SOLVED NEGATIVE -- the fuzzer did reach this tile type and solved other bits
    in it, but not this feature. The feature most likely has no bit here and we
    are over-emitting. Dropping it with --filter is correct.

  COVERAGE GAP -- the fuzzer never characterised this tile type at all. On a
    different die it may not even exist. Nothing is known; dropping the feature
    is a guess, and if the bit is real the design is silently broken.

prjuray-db was characterised on the ZU3EG. The XCK26 is the ZU5EV, a larger
die with tile types the ZU3EG does not have, so the second case is not
hypothetical. Telling them apart is a matter of looking, not reasoning: does
the reference die's tilegrid contain the tile type, and does a segbits file
exist for it?

For a coverage gap the script also names characterised siblings -- tile types
that DO have bits for the feature family -- ranked by shared name prefix. That
is the analogy to argue from, and it names the fuzzer to re-run. It is a
heuristic and nothing more: it ranks by name, so read the whole short list
rather than trusting the first row.

A COVERAGE GAP is not automatically a bug. A pip whose destination wire has
fan-in 1 is unconditional wiring and needs no bit at all, whichever tile type
it is in; counting dst_wire fan-in in the tile_type JSON settles those. This
script does not do that -- it only distinguishes "nothing is known" from
"something is known and it says no".

Usage:
  explain_missing_feature.py FEATURE...           # e.g. RCLK_CLEM_CLKBUF_L.WIRE.CLK_HDISTR_L7.USED.V1
  explain_missing_feature.py --from-filter FILE   # the "dropped" lines check_fasm_vs_uraydb.py printed
"""
import argparse
import glob
import json
import os
import re
import sys
from collections import Counter

DB = os.environ.get("URAY_FAMILY_DIR", "")
TILE_SUFFIX = re.compile(r"_X-?\d+Y-?\d+$")


def reference_tilegrid():
    """The tilegrid of the die prjuray-db was actually characterised on."""
    for path in sorted(glob.glob(os.path.join(DB, "*", "tilegrid.json"))):
        part = os.path.basename(os.path.dirname(path))
        # Skip the part we are building for: its tilegrid says nothing about
        # what the fuzzers covered.
        if part == os.environ.get("URAY_PART"):
            continue
        with open(path) as f:
            grid = json.load(f)
        return part, Counter(v["type"] for v in grid.values() if "type" in v)
    return None, Counter()


def segbits(tile_type):
    """Feature -> line count for a tile type, or None if never characterised."""
    path = os.path.join(DB, f"segbits_{tile_type.lower()}.db")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return [line.split()[0] for line in f if line.strip()]


def family(feature):
    """`WIRE.CLK_HDISTR_L7.USED.V1` -> `WIRE.CLK_HDISTR`: the comparable class."""
    f = re.sub(r"\d+", "", feature)
    return ".".join(f.split(".")[:2]).rstrip("_")


def origins(tile_type):
    path = os.path.join(DB, f"segbits_{tile_type.lower()}.origin_info.db")
    if not os.path.exists(path):
        return set()
    with open(path) as f:
        return {line.split()[1] for line in f if len(line.split()) > 1}


def siblings(tile_type, fam, all_types):
    """Characterised tile types with bits in this family, best prefix first."""
    out = []
    for t in all_types:
        bits = segbits(t)
        if not bits:
            continue
        n = sum(1 for b in bits if family(b.split(".", 1)[1]) == fam
                if "." in b)
        if n:
            common = len(os.path.commonprefix([t, tile_type]))
            out.append((common, n, t))
    return sorted(out, reverse=True)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("features", nargs="*")
    ap.add_argument("--from-filter", help="file of dropped feature lines")
    args = ap.parse_args()

    if not DB:
        sys.exit("URAY_FAMILY_DIR is unset -- source env/uray_env.sh first")

    feats = list(args.features)
    if args.from_filter:
        with open(args.from_filter) as f:
            for line in f:
                m = re.search(r"([A-Z0-9_]+_X-?\d+Y-?\d+\.\S+)", line)
                if m:
                    feats.append(m.group(1))
    if not feats:
        sys.exit("no features given")

    ref_part, ref_counts = reference_tilegrid()
    print(f"reference die: {ref_part or '(none found)'}\n")

    all_types = sorted({os.path.basename(p)[len("segbits_"):-len(".db")].upper()
                        for p in glob.glob(os.path.join(DB, "segbits_*.db"))
                        if "origin_info" not in p})

    # Collapse instances: the verdict is per tile type and feature family.
    seen = {}
    for feat in feats:
        tile, feature = feat.split(".", 1)
        seen.setdefault((TILE_SUFFIX.sub("", tile), family(feature)), []).append(feat)

    verdicts = Counter()
    for (ttype, fam), examples in sorted(seen.items()):
        print(f"{ttype}  {fam}.*   ({len(examples)} feature(s))")
        bits = segbits(ttype)
        on_ref = ref_counts.get(ttype, 0)
        if bits is None:
            v = "COVERAGE GAP"
            print(f"  no segbits_{ttype.lower()}.db -- never characterised")
            print(f"  instances on {ref_part}: {on_ref}"
                  + ("  <- the reference die does not have this tile type at all,"
                     " which is why" if on_ref == 0 else ""))
            if on_ref == 0:
                print("     the fuzzers could not have solved it. Re-running them"
                      " on THIS die can.")
            sib = siblings(ttype, fam, all_types)
            if sib:
                print(f"  characterised tile types with {fam}.* bits"
                      f" (ranked by shared name prefix -- a heuristic):")
                fz = set()
                for _, n, t in sib[:3]:
                    print(f"    {n:4d}  {t}")
                    fz |= origins(t)
                print("  -> the feature is probably REAL here; verify before"
                      " trusting the analogy")
                if fz:
                    print(f"  re-run: {', '.join(sorted(fz))}")
            else:
                print(f"  no characterised tile type has {fam}.* bits."
                      " If this is a PIP, check its destination wire's fan-in:")
                print("     fan-in 1 means unconditional wiring and no bit is"
                      " needed anywhere.")
        else:
            n = sum(1 for b in bits if "." in b
                    and family(b.split(".", 1)[1]) == fam)
            if n:
                v = "PRESENT"
                print(f"  {ttype} has {n} {fam}.* bits -- the specific feature is"
                      " missing, not the family; check the exact name")
            else:
                v = "SOLVED NEGATIVE"
                print(f"  segbits_{ttype.lower()}.db exists ({len(bits)} bits,"
                      f" instances on {ref_part}: {on_ref}) but 0 in {fam}.*")
                fz = origins(ttype)
                print(f"  solved by: {', '.join(sorted(fz)) or '(unknown)'}"
                      " -- that fuzzer reached this tile type and found no such")
                print("     bit, so we are over-emitting. Dropping it is correct.")
        verdicts[v] += 1
        print(f"  => {v}\n")

    for v, n in verdicts.most_common():
        print(f"{n:3d}  {v}")
    return 1 if verdicts["COVERAGE GAP"] else 0


if __name__ == "__main__":
    sys.exit(main())
