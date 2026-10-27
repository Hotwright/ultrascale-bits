#!/usr/bin/env python3
"""Random URAM288 specimens for the bit solver (as kv260_dsp_char/gen.py).

Every specimen holds N URAM288s at random sites with random attributes.
Cascades stay off (CASCADE_ORDER NONE, REG_CAS FALSE, CAS_IN_* open): nextpnr
rejects them. Every control pin is driven by a fabric signal or tied 0 or 1,
at random, so the tie handling is characterised too; each data bus (ADDR,
DIN, BWE) is all signals, ties per bit, or tied whole to 0 or 1. char.tcl
builds each and dumps every URAM's final properties and pin connections.

    gen.py <outdir> <count> [seed] [first]
"""
import json
import os
import random
import sys

N = 12
SITES = 64
BOOL = ["FALSE", "TRUE"]
ENUMS = {}
for s in "AB":
    ENUMS.update({
        "BWE_MODE_" + s: ["PARITY_INTERLEAVED", "PARITY_INDEPENDENT"],
        "EN_ECC_RD_" + s: BOOL, "EN_ECC_WR_" + s: BOOL, "IREG_PRE_" + s: BOOL,
        "OREG_" + s: BOOL, "OREG_ECC_" + s: BOOL, "RST_MODE_" + s: ["SYNC", "ASYNC"],
        "USE_EXT_CE_" + s: BOOL,
    })
ENUMS["EN_AUTO_SLEEP_MODE"] = BOOL
INVS = ["CLK", "EN_A", "EN_B", "RDB_WR_A", "RDB_WR_B", "RST_A", "RST_B"]
CTRL = {}
for s in "AB":
    CTRL.update({"EN_" + s: 1, "RDB_WR_" + s: 1, "RST_" + s: 1, "INJECT_SBITERR_" + s: 1,
                 "INJECT_DBITERR_" + s: 1, "OREG_CE_" + s: 1, "OREG_ECC_CE_" + s: 1})
CTRL["SLEEP"] = 1
DATA = {}
for s in "AB":
    DATA.update({"ADDR_" + s: 23, "DIN_" + s: 72, "BWE_" + s: 9})
POOL = 64


def sig(rng):
    return "pool[%d]" % rng.randrange(POOL)


def vec(rng, w, mode=None):
    """A bus: each bit a pool signal or a constant (mode as in the DSP gen.py)."""
    bits = []
    for _ in range(w):
        r = rng.random()
        if mode in ("gnd", "vcc"):
            bits.append("1'b0" if mode == "gnd" else "1'b1")
        elif mode == "sig":
            bits.append(sig(rng))
        else:
            bits.append(sig(rng) if r < 0.4 else ("1'b1" if r < 0.7 else "1'b0"))
    return "{%s}" % ", ".join(reversed(bits))


def uram(rng, i, site):
    p = {k: '"%s"' % rng.choice(v) for k, v in ENUMS.items()}
    p["AUTO_SLEEP_LATENCY"] = str(rng.randrange(3, 16))
    p["AVG_CONS_INACTIVE_CYCLES"] = str(rng.randrange(10, 100001))
    for s in "AB":
        p["SELF_ADDR_" + s] = "11'h%03x" % rng.getrandbits(11)
        p["SELF_MASK_" + s] = "11'h%03x" % rng.getrandbits(11)
    for k in INVS:
        p["IS_%s_INVERTED" % k] = "1'b%d" % rng.randrange(2)
    ports = {"CLK": "clk"}
    for k, w in DATA.items():
        ports[k] = vec(rng, w, rng.choice(["sig", "sig", "bits", "gnd", "vcc"]))
    for k, w in CTRL.items():
        ports[k] = vec(rng, w, "bits")
    ports["DOUT_A"] = "qa%d" % i
    ports["DOUT_B"] = "qb%d" % i
    params = ", ".join(".%s(%s)" % kv for kv in sorted(p.items()))
    conns = ", ".join(".%s(%s)" % kv for kv in ports.items())
    return ("    wire [71:0] qa%d, qb%d;\n    (* DONT_TOUCH = \"TRUE\", LOC = \"%s\" *)\n"
            "    URAM288 #(%s)\n        u%d (%s);\n" % (i, i, site, params, i, conns)), p


HEAD = """module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    (* DONT_TOUCH = "TRUE" *) reg [63:0] pool = 64'h0123456789abcdef;
    always @(posedge clk) pool <= {pool[62:0], pool[63] ^ pool[62] ^ pool[60] ^ pool[59]};
"""


def specimen(rng, path):
    os.makedirs(path, exist_ok=True)
    sites = rng.sample(["URAM288_X0Y%d" % r for r in range(SITES)], N)
    body, intent = [], {}
    for i, s in enumerate(sites):
        v, p = uram(rng, i, s)
        body.append(v)
        intent["u%d" % i] = {"site": s, "params": p}
    xor = " ^ ".join("(^qa%d) ^ (^qb%d)" % (i, i) for i in range(N))
    with open(os.path.join(path, "top.v"), "w") as f:
        f.write(HEAD + "".join(body) + "    assign pmod = {%s, pool[6:0]};\nendmodule\n" % xor)
    json.dump(intent, open(os.path.join(path, "intent.json"), "w"), indent=1)
    with open(os.path.join(path, "loc.txt"), "w") as f:
        f.write("\n".join(sites) + "\n")


def main():
    out, count = sys.argv[1], int(sys.argv[2])
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    first = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    for k in range(first, first + count):
        specimen(random.Random(seed * 100003 + k), os.path.join(out, "specimen_%03d" % k))


if __name__ == "__main__":
    main()
