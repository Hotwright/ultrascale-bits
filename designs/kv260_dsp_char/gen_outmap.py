#!/usr/bin/env python3
"""A specimen that tests whether the DSP tile's IN_USE bits are per-row
output enables, as the URAM tile's turned out to be (kv260_uram_char
gen_outmap.py).

The DSP IN_USE bits sit where URAM's OUT_A_ROW bits do (minors 1-3, one per
INT row), and every random specimen used all of P, so they could not tell.
Here each DSP48E2 uses exactly one output pin, one DSP per site in column
X2, rows 0-63: P[0..47], CARRYOUT[0..3], XOROUT[0..7], PATTERNDETECT,
PATTERNBDETECT, OVERFLOW, UNDERFLOW. intent.json maps each site to its pin.

    gen_outmap.py <outdir>
"""
import json
import os
import sys

PINS = (["P[%d]" % i for i in range(48)] + ["CARRYOUT[%d]" % i for i in range(4)]
        + ["XOROUT[%d]" % i for i in range(8)]
        + ["PATTERNDETECT", "PATTERNBDETECT", "OVERFLOW", "UNDERFLOW"])
WIDTH = {"P": 48, "CARRYOUT": 4, "XOROUT": 8}

HEAD = """module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    (* DONT_TOUCH = "TRUE" *) reg [63:0] pool = 64'h0123456789abcdef;
    always @(posedge clk) pool <= {pool[62:0], pool[63] ^ pool[62] ^ pool[60] ^ pool[59]};
"""


def dsp(i, site, pin):
    if "[" in pin:
        bus, idx = pin.split("[")[0], int(pin.split("[")[1][:-1])
        decl = "    wire [%d:0] v%d;\n    wire o%d = v%d[%d];\n" % (WIDTH[bus] - 1, i, i, i, idx)
        conn = ".%s(v%d)" % (bus, i)
    else:
        decl = "    wire o%d;\n" % i
        conn = ".%s(o%d)" % (pin, i)
    params = '.USE_PATTERN_DETECT("PATDET"), ' if "PATTERN" in pin or "FLOW" in pin else ""
    params += '.USE_WIDEXOR("TRUE"), ' if "XOROUT" in pin else ""
    return decl + ("    (* DONT_TOUCH = \"TRUE\", LOC = \"%s\" *)\n"
                   "    DSP48E2 #(%s.AREG(1)) d%d (.CLK(clk), .A(pool[29:0]), .B(pool[47:30]),\n"
                   "        .C({pool[63:16], 48'd0} >> 16), .OPMODE(9'b000110101), .ALUMODE(4'b0000),\n"
                   "        .INMODE(5'b00000), .CARRYINSEL(3'b000), .CARRYIN(1'b0), %s);\n"
                   % (site, params, i, conn))


def main():
    out = sys.argv[1]
    d = os.path.join(out, "out_0")
    os.makedirs(d, exist_ok=True)
    body, intent = [], {}
    for i, pin in enumerate(PINS):
        site = "DSP48E2_X2Y%d" % i
        body.append(dsp(i, site, pin))
        intent["d%d" % i] = {"site": site, "pin": pin}
    xor = " ^ ".join("o%d" % i for i in range(len(PINS)))
    with open(os.path.join(d, "top.v"), "w") as f:
        f.write(HEAD + "".join(body) + "    assign pmod = {%s, pool[6:0]};\nendmodule\n" % xor)
    json.dump(intent, open(os.path.join(d, "intent.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
