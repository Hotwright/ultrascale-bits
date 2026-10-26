#!/usr/bin/env python3
"""design.features (as dump.tcl spells Vivado's values) -> design.nfeatures,
spelled as nextpnr's FASM writer emits them. A FASM feature segment cannot
start with a digit or hold a quote:

    <site>.IS_<pin>_INVERTED.1'b1  ->  <site>.IS_<pin>_INVERTED   (0: dropped)
    <site>.INIT_OUT.1              ->  <site>.INIT_OUT            (0: dropped)
    <site>.PRESELECT_I0.TRUE       ->  <site>.PRESELECT_I0        (FALSE: dropped)
    <site>.BUFGCE_DIVIDE.4         ->  <site>.BUFGCE_DIVIDE.D4
    <site>.CE_TYPE.ASYNC           ->  unchanged

    normalize.py [build]
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def norm(line):
    m = re.match(r"^(.*\.(IS_\w+_INVERTED|INIT_OUT|PRESELECT_I[01]))\.(.*)$", line)
    if m:
        return m.group(1) if m.group(3) in ("1'b1", "1", "TRUE") else None
    m = re.match(r"^(.*\.BUFGCE_DIVIDE)\.(\d+)$", line)
    if m:
        return "%s.D%s" % (m.group(1), m.group(2))
    return line


def main():
    build = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "build")
    for spec in sorted(glob.glob(os.path.join(build, "specimen_*"))):
        src = os.path.join(spec, "design.features")
        if not os.path.exists(src):
            continue
        out = [norm(l.strip()) for l in open(src) if l.strip()]
        open(os.path.join(spec, "design.nfeatures"), "w").write("".join(l + "\n" for l in sorted(set(out) - {None})))


if __name__ == "__main__":
    main()
