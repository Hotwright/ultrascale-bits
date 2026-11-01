#!/usr/bin/env python3
"""Flatten a nextpnr-himbaechel (xilinx) routed JSON into plain route records
for RouteCheck.java:

    N <net name>
    R <x> <y> <wire>            a wire the route starts from (no uphill pip)
    P <x> <y> <dst> <src>       a tile pip (tile at grid x,y) the route uses
    S <x> <y> <site.pin>        a site-internal pip, recorded but not checked

Grid x,y is nextpnr's tile coordinate, which is Vivado's GRID_POINT_X/Y.
usage: extract_routes.py routed.json routes.txt
"""
import json, re, sys
d = json.load(open(sys.argv[1]))
m = d["modules"][list(d["modules"])[0]]
out = open(sys.argv[2], "w")
tile_re = re.compile(r"X(\d+)Y(\d+)$")
nnets = npips = 0
for name, v in m["netnames"].items():
    r = v.get("attributes", {}).get("ROUTING")
    if not r: continue
    parts = r.split(";")
    recs = []
    for i in range(0, len(parts) - 2, 3):
        wire, pip = parts[i], parts[i + 1]
        if not pip:
            t, w = wire.split("/", 1); mm = tile_re.match(t)
            recs.append("R %s %s %s" % (mm.group(1), mm.group(2), w)); continue
        pp = pip.split("/")
        mm = tile_re.match(pp[0])
        if len(pp) != 3 or "." in pp[1] or "." in pp[2]:
            recs.append("S %s %s %s" % (mm.group(1), mm.group(2), "/".join(pp[1:]))); continue
        recs.append("P %s %s %s %s" % (mm.group(1), mm.group(2), pp[1], pp[2])); npips += 1
    out.write("N %s\n" % name); out.write("\n".join(recs) + "\n"); nnets += 1
print("nets %d, tile pips %d" % (nnets, npips))
