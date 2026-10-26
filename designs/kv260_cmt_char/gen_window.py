#!/usr/bin/env python3
"""Specimens for the CMT_L characterisation (clock buffers, MMCM, PLL).

Every specimen is the kv260_cfg_char baseline (a PS-clocked counter on the
Pmod) plus clocking primitives fed from the PS clock or from fabric logic.
char_window.tcl builds each with the Windows Vivado (characterisation only) and dumps
where every clock primitive landed and the non-INT pips of its nets.

    gen_window.py <outdir>
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

# A second counter clocked by <clk>, folded into x[k].
def counter(k, clk):
    return """    (* DONT_TOUCH = "TRUE" *) reg [15:0] c%d = 16'd0;
    always @(posedge %s) c%d <= c%d + 1'b1;
    assign x[%d] = c%d[15];
""" % (k, clk, k, k, k, k)

MMCM = """    wire fb, mo0, lk;
    (* DONT_TOUCH = "TRUE" *) MMCME4_ADV #(%s) mmcm_i (.CLKIN1(clk), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .CLKFBIN(fb), .CLKFBOUT(fb), .CLKOUT0(mo0), .LOCKED(lk), .RST(1'b0), .PWRDWN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .CDDCREQ(1'b0));
    wire mclk;
    BUFGCE mb_i (.I(mo0), .CE(1'b1), .O(mclk));
    assign x[1] = lk;
""" 
MMCM_DEF = ".CLKIN1_PERIOD(10.0), .CLKFBOUT_MULT_F(10.0), .CLKOUT0_DIVIDE_F(10.0)"

PLL = """    wire pfb, po0, plk;
    (* DONT_TOUCH = "TRUE" *) PLLE4_ADV #(%s) pll_i (.CLKIN(clk), .CLKFBIN(pfb), .CLKFBOUT(pfb),
        .CLKOUT0(po0), .LOCKED(plk), .RST(1'b0), .PWRDWN(1'b0), .CLKOUTPHYEN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0));
    wire pclk;
    BUFGCE pb_i (.I(po0), .CE(1'b1), .O(pclk));
    assign x[2] = plk;
"""
PLL_DEF = ".CLKIN_PERIOD(10.0), .CLKFBOUT_MULT(8), .CLKOUT0_DIVIDE(8)"

# A fabric signal through a clock buffer, clocking its own counter.
BUFGCE = """    wire bclk;
    (* DONT_TOUCH = "TRUE" *) BUFGCE %s bg_i (.I(ctr[3]), .CE(ctr[20]), .O(bclk));
"""

VARIANTS = {
    "base": "",
    "base2": "",
    "mmcm": MMCM % MMCM_DEF + counter(3, "mclk"),
    "pll": PLL % PLL_DEF + counter(4, "pclk"),
    "bufgce": BUFGCE % "" + counter(5, "bclk"),
}


def main():
    out = sys.argv[1]
    for name, body in VARIANTS.items():
        d = os.path.join(out, name)
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, "top.v"), "w").write(HEAD + body + TAIL)


if __name__ == "__main__":
    main()
