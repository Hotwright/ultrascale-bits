#!/usr/bin/env python3
"""Apply db-corrections/ to the writable prjuray database overlay.

Two ops: `drop-bit` removes a mis-solved bit from a feature, and `add-feature`
appends a feature the reference never solved (characterised against Vivado,
with the evidence in the .corrections file). A file made only of add-feature
lines may name a segbits file the reference does not have at all.

prjuray-db is the reference we validate against and is READ ONLY. When a
fuzzer has demonstrably mis-solved a bit, the correction lives here as data --
with its evidence in the .corrections file -- and is applied into
prjuray/database/, replacing that entry's symlink with a corrected real copy.
mk_uray_overlay.sh calls this after linking, so it survives a re-link and never
writes through to the reference.

This FAILS rather than warns when a correction no longer applies. A db update
that fixes something upstream must be noticed, not silently absorbed.
"""
import argparse
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def read_rules(path):
    rules, adds = [], []
    for n, line in enumerate(open(path), 1):
        line = line.split("#")[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) == 3 and parts[1] == "drop-bit":
            rules.append((parts[0], parts[2]))
        elif len(parts) >= 3 and parts[1] == "add-feature":
            adds.append((parts[0], parts[2:]))
        else:
            sys.exit("%s:%d: expected '<feature> drop-bit <bit>' or "
                     "'<feature> add-feature <bit>...', got %r" % (path, n, line))
    return rules, adds


def ensure_tile_type(overlay_fam, reference_fam, tile_type):
    """prjuray registers a tile type only through tile_types/tile_type_<T>.json.

    In the overlay tile_types/ is a symlink to the reference. To add a type the
    reference lacks, it becomes a real directory of per-file links first, so
    the reference is still never written. The stub carries no pips or wires:
    fasm2bit and bit2fasm need only the segbits.
    """
    tdir = os.path.join(overlay_fam, "tile_types")
    if os.path.islink(tdir):
        os.unlink(tdir)
        os.mkdir(tdir)
        src = os.path.join(reference_fam, "tile_types")
        for f in os.listdir(src):
            os.symlink(os.path.join(src, f), os.path.join(tdir, f))
    path = os.path.join(tdir, "tile_type_%s.json" % tile_type)
    if not os.path.exists(path):
        with open(path, "w") as f:
            f.write('{"tile_type": "%s", "pips": {}, "sites": [], "wires": {}}\n' % tile_type)
        print("  tile_types: added stub %s" % os.path.basename(path))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--reference", default=os.path.join(ROOT, "prjuray-db"))
    ap.add_argument("--overlay", default=os.path.join(ROOT, "prjuray", "database"))
    ap.add_argument("--corrections", default=os.path.join(ROOT, "db-corrections"))
    ap.add_argument("--check", action="store_true",
                    help="report what would change and write nothing")
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(args.corrections, "*", "*.corrections")))
    if not files:
        print("  no corrections to apply")
        return
    total = 0
    for cf in files:
        family = os.path.basename(os.path.dirname(cf))
        dbname = os.path.basename(cf)[: -len(".corrections")] + ".db"
        src = os.path.join(args.reference, family, dbname)
        dst = os.path.join(args.overlay, family, dbname)
        rules, adds = read_rules(cf)
        if not os.path.exists(src):
            # A tile type the reference never fuzzed (CMT_L, absent from the
            # ZU3EG) starts from nothing, so there is nothing to drop from.
            if rules:
                sys.exit("apply_db_corrections: no reference %s to drop bits from" % src)
            src = os.devnull
            if not args.check:
                ensure_tile_type(os.path.join(args.overlay, family),
                                 os.path.join(args.reference, family),
                                 dbname[len("segbits_"):-len(".db")].upper())

        out, applied = [], {k: 0 for k in rules}
        new_features = {f for f, _ in adds}
        for line in open(src):
            p = line.split()
            if p and p[0] in new_features:
                sys.exit("apply_db_corrections: %s already has %s -- the reference now solves it, "
                         "re-check the correction against the reference before removing it"
                         % (dbname, p[0]))
            if p:
                for feature, bit in rules:
                    if p[0] == feature and bit in p[1:]:
                        p = [p[0]] + [b for b in p[1:] if b != bit]
                        applied[(feature, bit)] += 1
                        line = " ".join(p) + "\n"
            out.append(line)

        for (feature, bit), n in applied.items():
            if n == 0:
                sys.exit("apply_db_corrections: %s no longer has %s on %s -- the correction is "
                         "stale, re-check it against the reference before removing it"
                         % (dbname, bit, feature))
            total += n
        for feature, bits in adds:
            out.append(" ".join([feature] + bits) + "\n")
        total += len(adds)
        n_applied = sum(applied.values()) + len(adds)

        if args.check:
            print("  %s: %d correction(s) would apply" % (dbname, n_applied))
            continue
        # Never write through the symlink: that is the read-only reference.
        if os.path.islink(dst) or os.path.exists(dst):
            os.unlink(dst)
        with open(dst, "w") as f:
            f.writelines(out)
        real = os.path.realpath(dst)
        if real.startswith(os.path.realpath(args.reference) + os.sep):
            sys.exit("apply_db_corrections: REFUSING -- %s resolves into the reference" % dst)
        print("  %s: %d correction(s) applied" % (dbname, n_applied))
    print("  %d bit correction(s) total" % total)


if __name__ == "__main__":
    main()
