#!/usr/bin/env python3
"""Apply db-corrections/ to the writable prjuray database overlay.

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
    rules = []
    for n, line in enumerate(open(path), 1):
        line = line.split("#")[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 3 or parts[1] != "drop-bit":
            sys.exit("%s:%d: expected '<feature> drop-bit <bit>', got %r" % (path, n, line))
        rules.append((parts[0], parts[2]))
    return rules


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
        if not os.path.exists(src):
            sys.exit("apply_db_corrections: no reference %s" % src)
        rules = read_rules(cf)

        out, applied = [], {k: 0 for k in rules}
        for line in open(src):
            p = line.split()
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

        if args.check:
            print("  %s: %d correction(s) would apply" % (dbname, sum(applied.values())))
            continue
        # Never write through the symlink: that is the read-only reference.
        if os.path.islink(dst) or os.path.exists(dst):
            os.unlink(dst)
        with open(dst, "w") as f:
            f.writelines(out)
        real = os.path.realpath(dst)
        if real.startswith(os.path.realpath(args.reference) + os.sep):
            sys.exit("apply_db_corrections: REFUSING -- %s resolves into the reference" % dst)
        print("  %s: %d correction(s) applied" % (dbname, sum(applied.values())))
    print("  %d bit correction(s) total" % total)


if __name__ == "__main__":
    main()
