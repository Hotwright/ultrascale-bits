#!/usr/bin/env python3
"""Will every tile type this design uses get a frame base address?

A feature in a tile with no base address cannot be assembled at all. That is a
worse failure than a missing segbit and a much quieter one: fasm2bit places
nothing there, the bitstream comes out the right size, the round trip passes,
and the function is simply absent. On the XCK26 that nearly shipped a design
whose clock was never connected.

The failure is easy to walk into because 002-tilegrid's sub-fuzzers are named
after ZU3EG tile types but work by SITE type: each scans the grid for its site
and configures whichever tile holds it. So `rclk_pss_alto` looks inapplicable
on a die with no RCLK_PSS_ALTO, yet it is the only thing that addresses
RCLK_INTF_LEFT_TERM_ALTO here, because that is where this die keeps its
BUFG_PS sites. Judging a sub-fuzzer by its name, or by its namesake tile
type's instance count, gets this exactly wrong.

**The tilegrid is the ground truth and this tool prefers it.** Once 002 has
produced addresses, the only question that matters is which tile types the
design uses still lack one, and that is a lookup rather than an inference. Run
it after the fuzzers and believe the answer.

Before the fuzzers there is nothing to look up, so it falls back to predicting
from the sub-fuzzers -- and that prediction is a heuristic, labelled as one.
Tiles are reached three different ways and only the first is easy to see:

  * by SITE type: the fuzzer scans for a site and configures its tile. This is
    the case the tool reads accurately, and the one that misled me.
  * by TILE type: `cle` walks tile types directly. Nearly every other
    sub-fuzzer also lists CLEL_L/CLEL_R/CLEM, but as filler LUTs rather than
    as targets, so reading tile types as targets over-claims coverage.
  * by PROPAGATION: generate_full.py derives INT, PS8_INTF, RCLK_AMS_CFGIO and
    RCLK_XIPHY_OUTER_RIGHT from neighbours after the fuzzers run, so those
    look uncovered and are not.

So the prediction over-reports. Treat a flagged tile type as something to
check, never as a conclusion -- the first version of this tool confidently
flagged CLEL_R, CLEM and INT, which are the three things 002 handles best.

Usage:
  check_tilegrid_coverage.py DESIGN.fasm [--tilegrid PATH] [--fuzzers DIR]
  check_tilegrid_coverage.py --all       [--tilegrid PATH] [--fuzzers DIR]
"""
import argparse
import collections
import json
import os
import re
import sys

SITE_RE = re.compile(r"site_type\s*==\s*'([A-Z0-9_]+)'")
SITE_IN_RE = re.compile(r"site_type\s+in\s+\[([^\]]*)\]")
TILE_INST = re.compile(r"_X-?\d+Y-?\d+$")


def enabled_subfuzzers(fuzzdir):
    """Sub-fuzzer -> set of site types it configures, for the ENABLED ones."""
    mk = os.path.join(fuzzdir, "Makefile")
    with open(mk) as f:
        text = f.read()
    m = re.search(r"TILEGRID_TDB_DEPENDENCIES \+=(.*?)(?:\n\n|\n[A-Z])", text, re.S)
    listed = set(re.findall(r"(\w+)/\$\(BUILD_FOLDER\)", m.group(1))) if m else set()

    out = {}
    for sub in sorted(listed):
        sites = set()
        for fn in ("top.py", "generate.tcl", "generate.py"):
            p = os.path.join(fuzzdir, sub, fn)
            if not os.path.exists(p):
                continue
            with open(p) as f:
                src = f.read()
            sites |= set(SITE_RE.findall(src))
            for grp in SITE_IN_RE.findall(src):
                sites |= set(re.findall(r"'([A-Z0-9_]+)'", grp))
            # generate.tcl names the primitive it instantiates, which is the
            # site type for these fuzzers.
            sites |= set(re.findall(r"create_cell -reference ([A-Z][A-Z0-9_]+)", src))
        out[sub] = sites
    return out, listed


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("fasm", nargs="?")
    ap.add_argument("--all", action="store_true",
                    help="every tile type in the tilegrid, not just a design's")
    ap.add_argument("--tilegrid", default=os.path.join(
        os.environ.get("URAY_FAMILY_DIR", ""),
        os.environ.get("URAY_PART", ""), "tilegrid.json"))
    ap.add_argument("--fuzzers", default=None,
                    help="path to fuzzers/002-tilegrid")
    args = ap.parse_args()
    if not args.fasm and not args.all:
        ap.error("give a FASM file or --all")

    with open(args.tilegrid) as f:
        grid = json.load(f)
    fuzzdir = args.fuzzers or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "prjuray", "fuzzers", "002-tilegrid")
    subs, listed = enabled_subfuzzers(fuzzdir)
    addressed_total = sum(
        1 for v in grid.values() if (v.get("bits") or {}).get("CLB_IO_CLK"))
    measured = addressed_total > 0
    print(f"{args.tilegrid}: {len(grid)} tiles, {addressed_total} addressed")
    print(f"{fuzzdir}: {len(listed)} sub-fuzzer(s) enabled")
    if not measured:
        print("\nThis tilegrid holds no base addresses at all -- 002 has not"
              " finished, so there is")
        print("nothing to look up. Falling back to the static prediction,"
              " which OVER-REPORTS:")
        print("tile-type-driven and propagated tiles look uncovered and are"
              " not. See the header.")

    # site type -> the enabled sub-fuzzers that place it
    by_site = collections.defaultdict(list)
    for sub, sites in subs.items():
        for s in sites:
            by_site[s].append(sub)

    if args.all:
        # NULL is the absence of a tile, not a tile that failed to get an
        # address.
        wanted = sorted({t["type"] for t in grid.values()} - {"NULL"})
    else:
        wanted = set()
        with open(args.fasm) as f:
            for line in f:
                line = line.split("#")[0].strip()
                if line and not line.startswith("{") and "." in line:
                    wanted.add(TILE_INST.sub("", line.split(".")[0]))
        wanted = sorted(wanted)
        print(f"{args.fasm}: {len(wanted)} tile type(s) used")

    print()
    print(f"{'tile type':30s} {'inst':>5} {'addr':>5} {'sites':>6}  covered by")
    problems = []
    for ty in wanted:
        inst = [v for v in grid.values() if v["type"] == ty]
        if not inst:
            print(f"{ty:30s} {'0':>5}  -- not on this die")
            continue
        addressed = sum(1 for v in inst if (v.get("bits") or {}).get("CLB_IO_CLK"))
        site_types = collections.Counter()
        for v in inst:
            for st in (v.get("sites") or {}).values():
                site_types[st] += 1
        covering = sorted({s for st in site_types for s in by_site.get(st, [])})
        if addressed == len(inst):
            note = "addressed"
        elif measured and addressed:
            note = f"PARTIAL -- {len(inst) - addressed} instance(s) unaddressed"
            problems.append((ty, note))
        elif measured:
            # Ground truth: the fuzzers ran and produced nothing for this type.
            why = ("no sites, so no sub-fuzzer can reach it"
                   if not site_types else
                   "sites are " + ", ".join(sorted(site_types)) +
                   (f"; placed by {', '.join(covering)}" if covering
                    else "; NO ENABLED FUZZER places those"))
            note = f"UNADDRESSED -- {why}"
            problems.append((ty, note))
        elif not site_types:
            note = "no sites (predicted: would need fill_rclk_baseaddr.py)"
            problems.append((ty, note))
        elif covering:
            note = f"predicted via {', '.join(covering)}"
        else:
            orphan = ", ".join(sorted(site_types))
            note = f"predicted GAP: no enabled fuzzer places {orphan}"
            problems.append((ty, note))
        print(f"{ty:30s} {len(inst):5d} {addressed:5d} {len(site_types):6d}  {note}")

    if problems and measured and args.all:
        print("\nNote: prjuray's own ZU3EG database leaves about thirty"
              " site-less break and terminator")
        print("tile types unaddressed too. That is normal -- they carry no"
              " configuration for an")
        print("ordinary design. It only matters when a design actually uses"
              " one, which is why the")
        print("design-scoped mode is the one to trust.")
    if problems:
        head = ("tile type(s) have no base address:" if measured
                else "tile type(s) flagged by the static prediction"
                     " (over-reports -- check, do not conclude):")
        print(f"\n{len(problems)} {head}")
        for ty, note in problems:
            print(f"  {ty}: {note}")
        return 1
    print("\nevery tile type this design uses has a base address"
          if measured else "\nnothing flagged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
