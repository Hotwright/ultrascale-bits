#!/usr/bin/env python3
"""Specimens that map each URAM288 output pin to its per-row enable bit.

Vivado sets bits in minors 1-3 (port A) and 6-8 (port B) of the URAM tile,
one per INT row, only for rows whose outputs are used (kv260_uram_test
reference): the random specimens used every output, so they could not tell
the rows apart. Here every URAM uses exactly one output pin, one URAM per
site, over three specimens:

  out_0  DOUT_A[0..63]
  out_1  DOUT_A[64..71], DOUT_B[0..55]
  out_2  DOUT_B[56..71], SBITERR_A/B, DBITERR_A/B, RDACCESS_A/B

intent.json maps each site to its pin.

    gen_outmap.py <outdir>
"""
import json
import os
import sys

PINS = (["DOUT_A[%d]" % i for i in range(72)] + ["DOUT_B[%d]" % i for i in range(72)]
        + ["SBITERR_A", "SBITERR_B", "DBITERR_A", "DBITERR_B", "RDACCESS_A", "RDACCESS_B"])

HEAD = """module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    (* DONT_TOUCH = "TRUE" *) reg [63:0] pool = 64'h0123456789abcdef;
    always @(posedge clk) pool <= {pool[62:0], pool[63] ^ pool[62] ^ pool[60] ^ pool[59]};
"""


def uram(i, site, pin):
    bus, idx = (pin.split("[")[0], int(pin.split("[")[1][:-1])) if "[" in pin else (pin, None)
    if idx is None:
        conn = ".%s(o%d)" % (bus, i)
        decl = "    wire o%d;\n" % i
    else:
        w = 72
        conn = ".%s(v%d)" % (bus, i)
        decl = "    wire [%d:0] v%d;\n    wire o%d = v%d[%d];\n" % (w - 1, i, i, i, idx)
    ecc = 'EN_ECC_RD_A("TRUE"), .EN_ECC_RD_B("TRUE")' if "BITERR" in pin else 'EN_ECC_RD_A("FALSE")'
    return decl + ("    (* DONT_TOUCH = \"TRUE\", LOC = \"%s\" *)\n"
                   "    URAM288 #(.%s) u%d (.CLK(clk), .ADDR_A({11'd0, pool[11:0]}), .ADDR_B({11'd0, pool[23:12]}),\n"
                   "        .DIN_A({pool[63:0], pool[7:0]}), .DIN_B({pool[7:0], pool[63:0]}), .EN_A(pool[30]),\n"
                   "        .EN_B(pool[31]), .RDB_WR_A(pool[32]), .RDB_WR_B(pool[33]), .BWE_A(9'h1ff), .BWE_B(9'h1ff),\n"
                   "        .RST_A(1'b0), .RST_B(1'b0), .SLEEP(1'b0), .OREG_CE_A(1'b1), .OREG_CE_B(1'b1),\n"
                   "        .OREG_ECC_CE_A(1'b1), .OREG_ECC_CE_B(1'b1), .INJECT_SBITERR_A(1'b0),\n"
                   "        .INJECT_DBITERR_A(1'b0), .INJECT_SBITERR_B(1'b0), .INJECT_DBITERR_B(1'b0), %s);\n"
                   % (site, ecc, i, conn))


def main():
    out = sys.argv[1]
    for k in range(3):
        pins = PINS[64 * k:64 * (k + 1)]
        d = os.path.join(out, "out_%d" % k)
        os.makedirs(d, exist_ok=True)
        body, intent = [], {}
        for i, pin in enumerate(pins):
            site = "URAM288_X0Y%d" % i
            body.append(uram(i, site, pin))
            intent["u%d" % i] = {"site": site, "pin": pin}
        xor = " ^ ".join("o%d" % i for i in range(len(pins)))
        with open(os.path.join(d, "top.v"), "w") as f:
            f.write(HEAD + "".join(body) + "    assign pmod = {%s, pool[6:0]};\nendmodule\n" % xor)
        json.dump(intent, open(os.path.join(d, "intent.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
