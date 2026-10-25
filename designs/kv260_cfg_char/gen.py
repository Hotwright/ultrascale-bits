#!/usr/bin/env python3
"""Specimens for the CONFIG_SITE characterisation (ICAPE3 and friends).

The K26 has one CONFIG_SITE, so every variant is its own design: a PS-clocked
counter on the Pmod (the baseline), plus at most one config primitive with
one attribute changed. char.tcl builds each; diff.py compares raw frames
against the baseline, which gives the CFG_CONFIG frame window and the bits.

    gen.py <outdir>
"""
import os
import sys

HEAD = """module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    (* DONT_TOUCH = "TRUE" *) reg [31:0] ctr = 32'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;
    wire [31:0] x;
"""
TAIL = """    assign pmod = {^x, ctr[31:25]};
endmodule
"""

def prim(cell, params, ports, bel=None):
    p = ", ".join(".%s(%s)" % kv for kv in params.items())
    c = ", ".join(".%s(%s)" % kv for kv in ports.items())
    attr = '(* DONT_TOUCH = "TRUE"%s *) ' % (', BEL = "%s"' % bel if bel else "")
    return "    %s%s %s u (%s);\n" % (attr, cell, "#(%s)" % p if p else "", c)

ICAP = {"CLK": "clk", "CSIB": "ctr[3]", "RDWRB": "ctr[4]", "I": "ctr", "O": "x", "AVAIL": "", "PRDONE": "", "PRERROR": ""}
STARTUP = {"CFGCLK": "", "CFGMCLK": "x[0]", "EOS": "x[1]", "PREQ": "x[2]", "GSR": "1'b0", "GTS": "1'b0",
           "KEYCLEARB": "1'b1", "PACK": "1'b0", "USRCCLKO": "1'b0", "USRCCLKTS": "1'b1", "USRDONEO": "1'b1", "USRDONETS": "1'b1",
           "DO": "", "DI": "x[7:4]", "DTS": "4'b1111", "FCSBO": "1'b1", "FCSBTS": "1'b1"}
BSCAN = {"CAPTURE": "x[0]", "DRCK": "x[1]", "RESET": "x[2]", "RUNTEST": "x[3]", "SEL": "x[4]", "SHIFT": "x[5]",
         "TCK": "x[6]", "TDI": "x[7]", "TMS": "x[8]", "UPDATE": "x[9]", "TDO": "ctr[5]"}
DNA = {"CLK": "clk", "DIN": "ctr[6]", "READ": "ctr[7]", "SHIFT": "ctr[8]", "DOUT": "x[0]"}
USR = {"CFGCLK": "x[0]", "DATA": "x", "DATAVALID": ""}
FECC = {"CRCERROR": "x[0]", "ECCERRORSINGLE": "x[1]", "ECCERRORNOTSINGLE": "x[2]", "ENDOFFRAME": "x[3]",
        "ENDOFSCAN": "x[4]", "FAR": "x[31:5]", "FARSEL": "ctr[10:9]", "ICAPBOTCLK": "1'b0", "ICAPTOPCLK": "1'b0"}
EFUSE = {"EFUSEUSR": "x"}

def clean(ports):
    return {k: v for k, v in ports.items() if v}

VARIANTS = {
    "base": "",
    "base2": "",
    "icap": prim("ICAPE3", {}, clean(ICAP)),
    "icap_top": prim("ICAPE3", {}, clean(ICAP), "ICAP_TOP"),
    "icap_bot": prim("ICAPE3", {}, clean(ICAP), "ICAP_BOT"),
    "icap_autoswitch": prim("ICAPE3", {"ICAP_AUTO_SWITCH": '"ENABLE"'}, clean(ICAP)),
    "startup": prim("STARTUPE3", {}, clean(STARTUP)),
    "startup_prog_usr": prim("STARTUPE3", {"PROG_USR": '"TRUE"'}, clean(STARTUP)),
    "startup_usrcclko": prim("STARTUPE3", {}, clean(dict(STARTUP, USRCCLKO="ctr[2]", USRCCLKTS="1'b0"))),
    "startup_usrdoneo": prim("STARTUPE3", {}, clean(dict(STARTUP, USRDONEO="ctr[2]", USRDONETS="1'b0"))),
    "dna": prim("DNA_PORTE2", {}, clean(DNA)),
    "usr_access": prim("USR_ACCESSE2", {}, clean(USR)),
    "frame_ecc": prim("FRAME_ECCE4", {}, clean(FECC)),
    "efuse": prim("EFUSE_USR", {}, clean(EFUSE)),
}
for n in range(1, 5):
    VARIANTS["bscan%d" % n] = prim("BSCANE2", {"JTAG_CHAIN": str(n)}, clean(BSCAN))


def main():
    out = sys.argv[1]
    for name, body in VARIANTS.items():
        d = os.path.join(out, name)
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, "top.v"), "w").write(HEAD + body + TAIL)


if __name__ == "__main__":
    main()
