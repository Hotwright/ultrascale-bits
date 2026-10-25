#!/usr/bin/env python3
"""Per specimen: each clock's HROUTE track and CLOCK_ROOT, from roots.txt."""
import glob, os, re, collections
def clocks(spec):
    out = {}
    net = None
    for l in open(os.path.join(spec, "roots.txt")):
        m = re.match(r"NET (\S+) ROOT (\S*)", l)
        if m:
            net = m.group(1); out[net] = {"root": m.group(2), "k": None, "pips": []}
            continue
        out[net]["pips"].append(l.split()[1])
        m = re.search(r"CLK_BUFG_PS_(\d+)_CLK_OUT->>CLK_HROUTE", l)
        if m:
            out[net]["k"] = int(m.group(1))
    return out
