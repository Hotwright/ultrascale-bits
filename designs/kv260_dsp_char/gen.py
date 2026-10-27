#!/usr/bin/env python3
"""Random specimens for the DSP48E2 characterisation.

Each specimen places N DSP48E2s on random distinct sites (loc.txt) with
random attributes (the prjuray utils/spec/dsp.py list plus USE_MULT,
A_INPUT/B_INPUT, ACASCREG/BCASCREG and the 48-bit MASK/PATTERN/RND).
Every control pin is driven by a fabric signal or tied 0 or 1, at random,
so the tie handling is characterised too. Data pins come from a shared
pool of PS-clocked flops; each P is XOR-reduced into the Pmod. char.tcl
builds each and dumps every DSP's final properties and pin connections.

    gen.py <outdir> <count> [seed [first index]]
"""
import json
import os
import random
import sys

N = 32
COLS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]    # DSP48E2_X<c>
ROWS = 96                                           # DSP48E2_X<c>Y0..95

ENUMS = {
    "AMULTSEL": ["A", "AD"], "BMULTSEL": ["B", "AD"], "PREADDINSEL": ["A", "B"],
    "A_INPUT": ["DIRECT", "CASCADE"], "B_INPUT": ["DIRECT", "CASCADE"],
    "AUTORESET_PATDET": ["NO_RESET", "RESET_MATCH", "RESET_NOT_MATCH"],
    "AUTORESET_PRIORITY": ["RESET", "CEP"],
    "SEL_MASK": ["MASK", "C", "ROUNDING_MODE1", "ROUNDING_MODE2"],
    "SEL_PATTERN": ["PATTERN", "C"], "USE_PATTERN_DETECT": ["NO_PATDET", "PATDET"],
    "USE_MULT": ["NONE", "MULTIPLY", "DYNAMIC"], "USE_SIMD": ["ONE48", "TWO24", "FOUR12"],
    "USE_WIDEXOR": ["FALSE", "TRUE"], "XORSIMD": ["XOR24_48_96", "XOR12"],
}
REGS1 = ["ADREG", "ALUMODEREG", "CARRYINREG", "CARRYINSELREG", "CREG", "DREG", "INMODEREG", "MREG", "OPMODEREG",
         "PREG"]
INVS = {"ALUMODE": 4, "CARRYIN": 1, "CLK": 1, "INMODE": 5, "OPMODE": 9, "RSTA": 1, "RSTALLCARRYIN": 1,
        "RSTALUMODE": 1, "RSTB": 1, "RSTC": 1, "RSTCTRL": 1, "RSTD": 1, "RSTINMODE": 1, "RSTM": 1, "RSTP": 1}
CTRL = {"ALUMODE": 4, "INMODE": 5, "OPMODE": 9, "CARRYINSEL": 3, "CARRYIN": 1,
        "CEA1": 1, "CEA2": 1, "CEAD": 1, "CEALUMODE": 1, "CEB1": 1, "CEB2": 1, "CEC": 1, "CECARRYIN": 1,
        "CECTRL": 1, "CED": 1, "CEINMODE": 1, "CEM": 1, "CEP": 1,
        "RSTA": 1, "RSTALLCARRYIN": 1, "RSTALUMODE": 1, "RSTB": 1, "RSTC": 1, "RSTCTRL": 1, "RSTD": 1,
        "RSTINMODE": 1, "RSTM": 1, "RSTP": 1}
DATA = {"A": 30, "B": 18, "C": 48, "D": 27}
POOL = 64


def sig(rng):
    return "pool[%d]" % rng.randrange(POOL)


def vec(rng, w, tie_ok=True):
    """A bus: every bit a pool signal, or (for control buses) a constant per bit."""
    bits = []
    for _ in range(w):
        r = rng.random()
        bits.append(sig(rng) if not tie_ok or r < 0.5 else ("1'b1" if r < 0.75 else "1'b0"))
    return "{%s}" % ", ".join(reversed(bits))


def dsp(rng, i, site):
    p = {}
    for k, vals in ENUMS.items():
        p[k] = '"%s"' % rng.choice(vals)
    for k in REGS1:
        p[k] = str(rng.randrange(2))
    areg, breg = rng.randrange(3), rng.randrange(3)
    p["AREG"], p["BREG"] = str(areg), str(breg)
    # ACASCREG must be AREG, or 1 when AREG is 2 (likewise B).
    p["ACASCREG"] = str(rng.choice([areg, 1]) if areg == 2 else areg)
    p["BCASCREG"] = str(rng.choice([breg, 1]) if breg == 2 else breg)
    for k, w in INVS.items():
        p["IS_%s_INVERTED" % k] = "%d'b%s" % (w, "".join(rng.choice("01") for _ in range(w)))
    for k in ("MASK", "PATTERN", "RND"):
        p[k] = "48'h%012x" % rng.getrandbits(48)
    ports = {"CLK": "clk"}
    for k, w in DATA.items():
        ports[k] = vec(rng, w, tie_ok=False)
    for k, w in CTRL.items():
        ports[k] = vec(rng, w)
    ports["P"] = "p%d" % i
    params = ", ".join(".%s(%s)" % kv for kv in sorted(p.items()))
    conns = ", ".join(".%s(%s)" % kv for kv in ports.items())
    return ("    wire [47:0] p%d;\n    (* DONT_TOUCH = \"TRUE\", LOC = \"%s\" *)\n"
            "    DSP48E2 #(%s)\n        d%d (%s);\n" % (i, site, params, i, conns)), p


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
    sites = rng.sample(["DSP48E2_X%dY%d" % (c, r) for c in COLS for r in range(ROWS)], N)
    body, intent = [], {}
    for i, s in enumerate(sites):
        v, p = dsp(rng, i, s)
        body.append(v)
        intent["d%d" % i] = {"site": s, "params": p}
    xor = " ^ ".join("(^p%d)" % i for i in range(N))
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
