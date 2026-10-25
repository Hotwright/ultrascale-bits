#!/usr/bin/env python3
"""Write specimen designs for the clock-crossing characterisation.

Each specimen has a handful of PS PL clocks, each through a BUFG_PS pinned to
a chosen (row, index). BUFG_PS_<k> drives HROUTE<k> and nothing else, so the
pin picks the horizontal track. Every clock clocks a small counter pblocked
into one clock region east of the CMT_L column at X16, so the clock has to
cross it (and, for the X2 regions, the RCLK_CLEM_CLKBUF_L column at X22).
Vivado picks the root and the HDISTR track; char.tcl dumps what it picked.

    gen.py <outdir> <count> [seed [first index]]
"""
import json
import os
import random
import sys

# Only the PS's own clock row: PLCLK reaches no other row's BUFG_PS, and a
# fabric-driven BUFG_PS is limited to one per clock region. So the HROUTE
# crossing characterised is CMT_L_X16Y180's; HDISTR is seen in every region.
ROW = 209
# Mostly east of X16 (the crossing), some west of it: a clock rooted in X0
# still runs its HROUTE up to the CMT_L column, and only those specimens
# separate "HROUTE_0_k is used" from "HROUTE_0_k crosses".
REGIONS = ["X%dY%d" % (x, y) for x in (0, 1, 1, 2) for y in range(4)]


def specimen(rng, path):
    n = rng.randint(6, 12)
    used, clocks = set(), []
    while len(clocks) < n:
        row, k = ROW, rng.randrange(24)
        if (row, k) in used:
            continue
        used.add((row, k))
        clocks.append({"row": row, "k": k, "plclk": rng.randrange(4),
                       "region": rng.choice(REGIONS)})
    v = ["module top (output wire [7:0] pmod);",
         "    wire [3:0] plclk;",
         "    PS8 ps8_i (.PLCLK(plclk));",
         "    wire [%d:0] msb;" % (n - 1)]
    for i, c in enumerate(clocks):
        v += ["    wire clk%d;" % i,
              "    (* DONT_TOUCH = \"TRUE\" *) BUFG_PS bufg%d (.I(plclk[%d]), .O(clk%d));" % (i, c["plclk"], i),
              "    (* DONT_TOUCH = \"TRUE\" *) reg [7:0] ctr%d = 8'd0;" % i,
              "    always @(posedge clk%d) ctr%d <= ctr%d + 1'b1;" % (i, i, i),
              "    assign msb[%d] = ctr%d[7];" % (i, i)]
    v += ["    assign pmod = {7'd0, ^msb};", "endmodule", ""]
    os.makedirs(path, exist_ok=True)
    open(os.path.join(path, "top.v"), "w").write("\n".join(v))
    json.dump(clocks, open(os.path.join(path, "clocks.json"), "w"), indent=1)
    # The same, for char.tcl: "<row> <k> <region>" per clock, in bufg order.
    with open(os.path.join(path, "clocks.txt"), "w") as f:
        for c in clocks:
            f.write("%d %d %s\n" % (c["row"], c["k"], c["region"]))


def main():
    out, count = sys.argv[1], int(sys.argv[2])
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    first = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    rng = random.Random(seed)
    for i in range(first, first + count):
        specimen(rng, os.path.join(out, "specimen_%03d" % i))


if __name__ == "__main__":
    main()
