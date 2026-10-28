#!/usr/bin/env python3
"""Write ps_stage.vh: a falling-edge register on every M_AXI_HPM0_FPD signal
axi.v uses, in both directions, one FDRE_1 per bit, each pinned (BEL) to a
flip-flop beside the INT row where its PS8 pin crosses into the fabric
(ps_rows.txt).

  out  PL->PS: <sig>_n is the copy of <sig> the PS8 pin is driven from.
  in   PS->PL: <sig> is the capture of the PS8 pin, wired as <sig>_p.

The PS samples our outputs and launches its own on the rising edge. A
falling-edge register on each side keeps every pin half a cycle away from
that edge, and is otherwise transparent: what the logic sees, and what the
PS sees, at each rising edge is what it would be without the stage. Pinning
keeps those routes a few local hops in every build. nextpnr has no
UltraScale+ timing model; without this the routes ran up to 74 pips and
the PS and the logic each caught some bits of the other's next value.

Flip-flops are taken nearest first: X161 (the slice beside INT X160), then
X164 and X168, a row away costing as much as a column away.

    gen_ps_stage.py > ps_stage.vh
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
COLS = (161, 164, 168)
BELS = ["%sFF%s" % (h, r) for r in ("", "2") for h in "ABCDEFGH"]

sigs = []
for line in open(os.path.join(HERE, "ps_rows.txt")):
    if line.startswith("#") or not line.strip():
        continue
    d, name, pin, row = line.split()
    sigs.append((int(row), d, name))

free = {(x, y): list(BELS) for x in COLS for y in range(120, 175)}
for row, d, name in sorted(sigs):
    x, y = min((k for k in free if free[k]), key=lambda k: (abs(k[1] - row) + 2 * COLS.index(k[0]), k))
    bel = "X%dY%d/SLICE_X0Y0.%s" % (x, y, free[(x, y)].pop(0))
    m = re.match(r"(\w+)(?:\[(\d+)\])?$", name)
    base, idx = m.group(1), m.group(2)
    bit = "[%s]" % idx if idx else ""
    inst = "%s_%s%s" % ("o" if d == "out" else "i", base, "_" + idx if idx else "")
    dn, qn = (name, base + "_n" + bit) if d == "out" else (base + "_p" + bit, name)
    print('    (* BEL = "%s" *) FDRE_1 %s (.C(clk), .CE(1\'b1), .R(1\'b0), .D(%s), .Q(%s));'
          % (bel, inst, dn, qn))
