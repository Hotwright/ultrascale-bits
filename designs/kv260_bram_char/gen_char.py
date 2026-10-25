#!/usr/bin/env python3
"""Write char.v + char_vivado.xdc: one BRAM per tile, each differing from a
baseline in exactly one parameter, for characterising the UltraScale+ BRAM
configuration bits that prjuray-db does not have (data widths above all).

Every BRAM has every input driven by a register, the same way in every
variant, so pin routing and constant ties cancel in a diff against the
baseline. INIT_A/INIT_B/SRVAL_A/SRVAL_B are random everywhere: their bits are
in prjuray-db, and many random samples pin down the parameter-bit to
feature-bit order. INIT/INITP stay zero so the BLOCK_RAM frames stay quiet.

variants.json records, per tile, the site, the primitive and its parameters.
"""
import json
import random

random.seed(7)

BASE18 = dict(READ_WIDTH_A=18, WRITE_WIDTH_A=18, READ_WIDTH_B=18, WRITE_WIDTH_B=18,
              DOA_REG=0, DOB_REG=0, WRITE_MODE_A='"NO_CHANGE"', WRITE_MODE_B='"NO_CHANGE"')
BASE36 = dict(READ_WIDTH_A=36, WRITE_WIDTH_A=36, READ_WIDTH_B=36, WRITE_WIDTH_B=36,
              DOA_REG=0, DOB_REG=0, WRITE_MODE_A='"NO_CHANGE"', WRITE_MODE_B='"NO_CHANGE"')

variants = []  # (kind, half, label, overrides)
for half in ("L", "U"):
    variants.append(("RAMB18E2", half, "base", {}))
    variants.append(("RAMB18E2", half, "base2", {}))
    for p in ("READ_WIDTH_A", "WRITE_WIDTH_A", "READ_WIDTH_B", "WRITE_WIDTH_B"):
        for w in (1, 2, 4, 9):
            variants.append(("RAMB18E2", half, f"{p}={w}", {p: w}))
    variants.append(("RAMB18E2", half, "SDP36", {"READ_WIDTH_A": 36, "WRITE_WIDTH_B": 36,
                                                "READ_WIDTH_B": 0, "WRITE_WIDTH_A": 0}))
    variants.append(("RAMB18E2", half, "DOA_REG=1", {"DOA_REG": 1}))
    variants.append(("RAMB18E2", half, "DOB_REG=1", {"DOB_REG": 1}))
    for m in ("READ_FIRST", "WRITE_FIRST"):
        variants.append(("RAMB18E2", half, f"WRITE_MODE_A={m}", {"WRITE_MODE_A": f'"{m}"'}))
        variants.append(("RAMB18E2", half, f"WRITE_MODE_B={m}", {"WRITE_MODE_B": f'"{m}"'}))
    variants.append(("RAMB18E2", half, "RSTREGB_INV", {"IS_RSTREGB_INVERTED": "1'b1"}))
variants.append(("RAMB36E2", None, "base", {}))
variants.append(("RAMB36E2", None, "base2", {}))
for p in ("READ_WIDTH_A", "WRITE_WIDTH_A", "READ_WIDTH_B", "WRITE_WIDTH_B"):
    for w in (1, 2, 4, 9, 18):
        variants.append(("RAMB36E2", None, f"{p}={w}", {p: w}))
variants.append(("RAMB36E2", None, "SDP72", {"READ_WIDTH_A": 72, "WRITE_WIDTH_B": 72,
                                            "READ_WIDTH_B": 0, "WRITE_WIDTH_A": 0}))
variants.append(("RAMB36E2", None, "DOA_REG=1", {"DOA_REG": 1}))
variants.append(("RAMB36E2", None, "DOB_REG=1", {"DOB_REG": 1}))
for m in ("READ_FIRST", "WRITE_FIRST"):
    variants.append(("RAMB36E2", None, f"WRITE_MODE_A={m}", {"WRITE_MODE_A": f'"{m}"'}))
    variants.append(("RAMB36E2", None, f"WRITE_MODE_B={m}", {"WRITE_MODE_B": f'"{m}"'}))
variants.append(("RAMB36E2", None, "RSTREGB_INV", {"IS_RSTREGB_INVERTED": "1'b1"}))
# Both halves of one tile used, for comparison with a lone L / lone U.
variants.append(("RAMB18E2", "LU", "both", {}))

# Tiles: BRAM_X19Y{0,5..235} then BRAM_X33Y*, as RAMB36_X{c}Y{n}, RAMB18_X{c}Y{2n,2n+1}.
tiles = [(c, n) for c in (0, 1) for n in range(48)]
assert len(variants) <= len(tiles), len(variants)

lines, xdc, record = [], [], []
nbits = 0


def rnd(bits):
    return "%d'h%0*X" % (bits, (bits + 3) // 4, random.getrandbits(bits))


def inst(kind, name, site, params):
    global nbits
    is36 = kind == "RAMB36E2"
    aw, dw, pw, wa, wb = (15, 32, 4, 4, 8) if is36 else (14, 16, 2, 2, 4)
    vw = 36 if is36 else 18
    ps = dict(params)
    for p in ("INIT_A", "INIT_B", "SRVAL_A", "SRVAL_B"):
        ps[p] = rnd(vw)
    plist = ",\n        ".join(f".{k}({v})" for k, v in ps.items())
    o = nbits
    nbits += 1
    ports = [".CLKARDCLK(clk)", ".CLKBWRCLK(clk)",
             f".ENARDEN(s[{(o*7+1)%64}])", f".ENBWREN(s[{(o*7+2)%64}])",
             f".REGCEAREGCE(s[{(o*7+3)%64}])", f".REGCEB(s[{(o*7+4)%64}])",
             f".RSTRAMARSTRAM(s[{(o*7+5)%64}])", f".RSTRAMB(s[{(o*7+6)%64}])",
             f".RSTREGARSTREG(s[{(o*7+7)%64}])", f".RSTREGB(s[{(o*7+8)%64}])",
             f".ADDRARDADDR(s[{(o*3)%40}+:{aw}])", f".ADDRBWRADDR(s[{(o*3+5)%40}+:{aw}])",
             f".DINADIN(s[{(o*5)%30}+:{dw}])", f".DINBDIN(s[{(o*5+3)%30}+:{dw}])",
             f".DINPADINP(s[{(o*5+1)%30}+:{pw}])", f".DINPBDINP(s[{(o*5+2)%30}+:{pw}])",
             f".WEA({{{wa}{{s[{(o*11)%64}]}}}})", f".WEBWE({{{wb}{{s[{(o*11+1)%64}]}}}})",
             f".DOUTADOUT(da{name})", f".DOUTBDOUT(db{name})",
             f".DOUTPADOUTP(pa{name})", f".DOUTPBDOUTP(pb{name})"]
    pl = ",\n        ".join(ports)
    lines.append(f"    wire [{dw-1}:0] da{name}, db{name};\n    wire [{pw-1}:0] pa{name}, pb{name};")
    lines.append(f"    (* keep *) {kind} #(\n        {plist}\n    ) {name} (\n        {pl}\n    );")
    lines.append(f"    assign red[{o}] = ^{{da{name}, db{name}, pa{name}, pb{name}}};")
    xdc.append(f"set_property LOC {site} [get_cells {name}]")
    record.append(dict(name=name, kind=kind, site=site, params=ps))


for i, (kind, half, label, over) in enumerate(variants):
    c, n = tiles[i]
    tile = f"BRAM_X{19 if c == 0 else 33}Y{n*5}"
    base = dict(BASE36 if kind == "RAMB36E2" else BASE18)
    base.update(over)
    if kind == "RAMB36E2":
        inst(kind, f"v{i}", f"RAMB36_X{c}Y{n}", base)
        record[-1].update(tile=tile, label=label, half="36")
    else:
        for h in ("L", "U") if half == "LU" else (half,):
            site = f"RAMB18_X{c}Y{2*n + (0 if h == 'L' else 1)}"
            inst(kind, f"v{i}{h}", site, base)
            record[-1].update(tile=tile, label=label, half=h)

src = f"""// Generated by gen_char.py -- see there.
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    // A 64-bit LFSR, so every BRAM input is a different live signal.
    reg [63:0] s = 64'h1;
    always @(posedge clk) s <= {{s[62:0], s[63] ^ s[62] ^ s[60] ^ s[59]}};
    wire [{nbits-1}:0] red;
{chr(10).join(lines)}
    reg [7:0] q;
    always @(posedge clk) q <= {{8{{^red}}}} ^ red[7:0];
    assign pmod = q;
endmodule
"""
open("char.v", "w").write(src)
base_xdc = open("../kv260_bram_spec/kv260_spec_vivado.xdc").read().split("\n# BRAM sites")[0]
open("char_vivado.xdc", "w").write(base_xdc + "\n" + "\n".join(xdc) + "\n")
json.dump(record, open("variants.json", "w"), indent=1)
print(len(variants), "variants,", nbits, "BRAMs")
