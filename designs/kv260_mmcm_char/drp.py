#!/usr/bin/env python3
"""MMCME4/PLLE4 DRP register fields from their parameters (XAPP888).

A port of AMD's mmcm_pll_drp_func_us_plus_{mmcm,pll}.vh (the clk_wiz IP's
DRP functions): counter high/low time, edge, no-count, phase mux, delay
time, fractional settings, and the lock and filter lookups. The lookup
tables are read from those headers at run time (DRP_VH_DIR); they are AMD's
and are not copied here.

fields(kind, props) returns {feature: 0/1} for one cell, features spelled
    <COUNTER>.<FIELD>[i]   COUNTER in CLKOUT0-6, CLKFBOUT, DIVCLK
    LKTABLE[i] (40 bits), TABLE[i] (10 bits)
Register layout, per counter (as on 7-series, XAPP888):
    REG1  LOW_TIME[5:0] HIGH_TIME[11:6] OUTPUT_ENABLE[12] PHASE_MUX[15:13]
          OUTPUT_ENABLE (reserved in XAPP888) is set for a connected output,
          for CLKFBOUT, and for CLKOUT6 when CLKOUT4_CASCADE (it then drives
          CLKOUT4's counter)
    REG2  DELAY_TIME[5:0] NO_COUNT[6] EDGE[7] MX[9:8] FRAC_WF_R[10]
          FRAC_EN[11] FRAC[14:12] REG2_RESERVED[15]
          CLKOUT4 REG2[9] (MX[1]) is CLKOUT4_CASCADE
    CLKOUT5/CLKOUT6 REG2[15:12] instead hold the falling-edge fraction of
    CLKOUT0/CLKFBOUT: FRAC_WF_F[12] PHASE_MUX_F[15:13] (two bits higher than
    7-series; kv260_mmcm_char, every fractional sample)
    DIVCLK  LOW_TIME[5:0] HIGH_TIME[11:6] NO_COUNT[12] EDGE[13]
"""
import os
import re

DRP_VH_DIR = os.environ.get(
    "DRP_VH_DIR",
    "/mnt/i/Hotwright/0-SBIR/RISCV-for-SBIR/AXI_Basics_3/AXI_Basics_3/axi_gpio_0_ex/"
    "axi_gpio_0_ex.gen/sources_1/ip/clk_wiz_0")
FRAC_PRECISION = 10
MASK32 = (1 << 32) - 1


def _tables(path):
    """{function name: [entries in source order]} for each lookup table."""
    src = open(path).read()
    out = {}
    for m in re.finditer(r"function\s*\[[^\]]*\]\s*(\w+)(.*?)endfunction", src, re.S):
        body = m.group(2)
        tabs = []
        for t in re.finditer(r"(\w+)\s*=\s*\{(.*?)\};", body, re.S):
            ents = [int(e.replace("_", ""), 2) for e in
                    re.findall(r"\d+'b([01_]+)", re.sub(r"//[^\n]*", "", t.group(2)))]
            if ents:
                tabs.append((t.group(1), ents))
        if tabs:
            out[m.group(1)] = dict(tabs)
    return out


_TAB = {}


def tables(kind):
    if kind not in _TAB:
        _TAB[kind] = _tables(os.path.join(DRP_VH_DIR, "mmcm_pll_drp_func_us_plus_%s.vh" % kind.lower()))
    return _TAB[kind]


# The headers' fixed-point registers are declared [32:1], so a part-select
# temp[k] is bit k-1 of the integer here.
def round_frac(decimal, precision):
    if (decimal >> (FRAC_PRECISION - precision - 1)) & 1:
        decimal += 1 << (FRAC_PRECISION - precision)
    return decimal & MASK32


def divider(divide, duty):
    """(edge, no_count, high, low); duty multiplied by 100,000."""
    duty_fix = ((duty << FRAC_PRECISION) // 100000) & MASK32
    if divide == 1:
        return 0, 1, 1, 1
    temp = round_frac((duty_fix * divide) & MASK32, 1)
    high = (temp >> FRAC_PRECISION) & 0x7F
    edge = (temp >> (FRAC_PRECISION - 1)) & 1
    if high == 0:
        high, edge = 1, 0
    if high == divide:
        high, edge = divide - 1, 1
    low = divide - high
    return edge, 0, high & 0x3F, low & 0x3F


def phase(divide, ph):
    """(mx, phase_mux, delay_time); ph in millidegrees."""
    if ph < 0:
        fixed = (((ph + 360000) << FRAC_PRECISION) // 1000) & MASK32
    else:
        fixed = ((ph << FRAC_PRECISION) // 1000) & MASK32
    cycles = ((fixed * divide) // 360) & MASK32
    temp = round_frac(cycles, 3)
    return 0, (temp >> (FRAC_PRECISION - 3)) & 7, (temp >> FRAC_PRECISION) & 0x3F


def count_calc(divide, ph, duty):
    edge, nc, high, low = divider(divide, duty)
    mx, pm, dt = phase(divide, ph)
    reg1 = low | high << 6 | pm << 13
    reg2 = dt | nc << 6 | edge << 7 | mx << 8
    # Vivado copies an integer CLKOUT0/CLKFBOUT's phase mux into the
    # falling-edge field of CLKOUT5/CLKOUT6 too (XAPP888 leaves it 0).
    return reg1, reg2, pm << 1


def frac_count_calc(divide, ph, frac):
    """divide: integer part; frac: the fraction x 1000 (multiple of 125)."""
    f = frac // 125
    even_high = divide >> 1
    even_low = even_high
    odd = divide - even_high - even_low
    odd_and_frac = 8 * odd + f
    lt = (even_high - (1 if odd_and_frac <= 9 else 0)) & 0xFF
    ht = (even_low - (1 if odd_and_frac <= 8 else 0)) & 0xFF
    pm_fall = ((odd & 0x7F) << 2) + (f >> 1)
    wf_fall = int((2 <= odd_and_frac <= 9) or (divide == 2 and f == 1))
    wf_rise = int(1 <= odd_and_frac <= 8)
    per_oct = 8 * divide + f
    ph_cyc = ((ph + 10) * per_oct // 360000) & MASK32
    pm_rise = 0 if (ph_cyc & 0xFF) == 0 else ((ph_cyc & 0xFF) - (ph_cyc & 0xF8)) & 0xFF
    dt = (((ph + 10) * per_oct // 8) // 360000) & 0xFF
    pm_rise_filt = pm_rise - 8 if pm_rise >= 8 else pm_rise
    pm_fall_frac = (pm_fall + pm_rise) & 0xFF
    pm_fall_filt = (pm_fall + pm_rise - (pm_fall_frac & 0xF8)) & 0xFF
    mx, _, _ = phase(divide, ph)
    reg1 = (lt & 0x3F) | (ht & 0x3F) << 6 | (pm_rise_filt & 7) << 13
    reg2 = (dt & 0x3F) | mx << 8 | wf_rise << 10 | 1 << 11 | f << 12
    transfer = wf_fall | (pm_fall_filt & 7) << 1
    return reg1, reg2, transfer


REG1 = [("LOW_TIME", 0, 6), ("HIGH_TIME", 6, 6), ("OUTPUT_ENABLE", 12, 1), ("PHASE_MUX", 13, 3)]
REG2 = [("DELAY_TIME", 0, 6), ("NO_COUNT", 6, 1), ("EDGE", 7, 1), ("MX", 8, 2), ("FRAC_WF_R", 10, 1),
        ("FRAC_EN", 11, 1), ("FRAC", 12, 3), ("REG2_RESERVED", 15, 1)]
REG2_SHARED = [("DELAY_TIME", 0, 6), ("NO_COUNT", 6, 1), ("EDGE", 7, 1), ("MX", 8, 2), ("REG2_RESERVED", 10, 2),
               ("FRAC_WF_F", 12, 1), ("PHASE_MUX_F", 13, 3)]
DIVCLK = [("LOW_TIME", 0, 6), ("HIGH_TIME", 6, 6), ("NO_COUNT", 12, 1), ("EDGE", 13, 1)]


def split(out, prefix, value, layout):
    for name, lsb, width in layout:
        for i in range(width):
            out["%s.%s[%d]" % (prefix, name, i)] = (value >> (lsb + i)) & 1


def num(props, key, default):
    v = props.get(key)
    return default if v is None else float(v)


def counter(props, name, divide_key):
    d = num(props, divide_key, 1.0)
    ph = int(round(num(props, name + "_PHASE", 0.0) * 1000))
    duty = int(round(num(props, name + "_DUTY_CYCLE", 0.5) * 100000))
    di = int(d)
    frac = int(round((d - di) * 1000))
    if frac:
        return frac_count_calc(di, ph, frac)
    return count_calc(di, ph, duty)


def fields(kind, props):
    """kind 'MMCM' or 'PLL'; props: parameter name -> value (strings)."""
    out = {}
    tab = tables(kind)
    if kind == "MMCM":
        mult = num(props, "CLKFBOUT_MULT_F", 5.0)
        outs = [("CLKOUT0", "CLKOUT0_DIVIDE_F")] + [("CLKOUT%d" % o, "CLKOUT%d_DIVIDE" % o) for o in range(1, 7)]
        outs.append(("CLKFBOUT", "CLKFBOUT_MULT_F"))
    else:
        mult = num(props, "CLKFBOUT_MULT", 5.0)
        outs = [("CLKOUT0", "CLKOUT0_DIVIDE"), ("CLKOUT1", "CLKOUT1_DIVIDE"), ("CLKFBOUT", "CLKFBOUT_MULT")]
    regs = {name: counter(props, name, key) for name, key in outs}
    if kind == "MMCM":
        # The falling-edge fraction of CLKOUT0 / CLKFBOUT lives in the
        # second register of CLKOUT5 / CLKOUT6.
        for frac_of, host in (("CLKOUT0", "CLKOUT5"), ("CLKFBOUT", "CLKOUT6")):
            r1, r2, _ = regs[host]
            regs[host] = (r1, (r2 & 0xFFF) | regs[frac_of][2] << 12, 0)
    cascade = kind == "MMCM" and props.get("CLKOUT4_CASCADE") == "TRUE"
    for name, (r1, r2, t) in list(regs.items()):
        oe = name == "CLKFBOUT" or props.get("PIN." + name, "1") == "1" or (name == "CLKOUT6" and cascade)
        r1 = r1 | oe << 12
        if name == "CLKOUT4" and cascade:
            r2 |= 1 << 9
        regs[name] = (r1, r2, t)
    for name, (r1, r2, _) in regs.items():
        split(out, name, r1, REG1)
        split(out, name, r2, REG2_SHARED if kind == "MMCM" and name in ("CLKOUT5", "CLKOUT6") else REG2)
    edge, nc, high, low = divider(int(num(props, "DIVCLK_DIVIDE", 1)), 50000)
    split(out, "DIVCLK", low | high << 6 | nc << 12 | edge << 13, DIVCLK)
    # A fractional multiplier indexes the lock and filter tables rounded to
    # the nearest integer, half up (Vivado: 12.5 -> 13, 20.375 -> 20).
    # XAPP888's Verilog truncates.
    m = int(mult + 0.5)
    # Tables are in source order, M=1 first (the Verilog part-select
    # lookup[(N-M)*w +: w] counts from the last entry).
    lock = tab["mmcm_pll_lock_lookup"]["lookup"]
    split(out, "LOCK", lock[m - 1], [("LKTABLE", 0, 40)])
    filt = tab["mmcm_pll_filter_lookup"]
    if kind == "MMCM":
        t = filt["lookup_low"] if props.get("BANDWIDTH", "OPTIMIZED") == "LOW" else filt["lookup_high"]
    else:
        t = filt["lookup"]
    split(out, "FILTER", t[m - 1], [("TABLE", 0, 10)])
    return out


if __name__ == "__main__":
    # Spot checks against hand-worked XAPP888 cases.
    assert divider(4, 50000) == (0, 0, 2, 2)
    assert divider(5, 50000) == (1, 0, 2, 3)   # 2.5 high: high 2, edge
    assert divider(1, 50000) == (0, 1, 1, 1)
    assert phase(8, 45000) == (0, 0, 1)        # 45 deg of /8 = one VCO cycle
    assert phase(8, 22500) == (0, 4, 0)        # half a VCO cycle
    f = fields("MMCM", {"CLKFBOUT_MULT_F": "10", "CLKOUT0_DIVIDE_F": "10", "DIVCLK_DIVIDE": "1"})
    assert sum(f["CLKOUT0.HIGH_TIME[%d]" % i] << i for i in range(6)) == 5
    print("ok", len(f), "MMCM feature bits;", len(fields("PLL", {"CLKFBOUT_MULT": "8"})), "PLL")


# Whole registers, for checking every bit (constants and reserved included)
# and for the writer. LOCK and FILTER follow the 7-series packing (XAPP888):
#   LOCK1 = LKTABLE[29:20]            LOCK2 = LKTABLE[34:30] << 10 | LKTABLE[9:0]
#   LOCK3 = LKTABLE[39:35] << 10 | LKTABLE[19:10]
#   FILT1 = TABLE[6] << 8 | TABLE[8:7] << 11 | TABLE[9] << 15
#   FILT2 = TABLE[0] << 4 | TABLE[2:1] << 7 | TABLE[4:3] << 11 | TABLE[5] << 15
def registers(kind, props):
    f = fields(kind, props)

    def val(prefix, layout):
        v = 0
        for name, lsb, width in layout:
            for i in range(width):
                v |= f.get("%s.%s[%d]" % (prefix, name, i), 0) << (lsb + i)
        return v

    def lk(lo, hi):
        return sum(f["LOCK.LKTABLE[%d]" % i] << (i - lo) for i in range(lo, hi + 1))

    def tb(i):
        return f["FILTER.TABLE[%d]" % i]

    regs = {}
    counters = ["CLKOUT%d" % o for o in range(7)] + ["CLKFBOUT"] if kind == "MMCM" else \
        ["CLKOUT0", "CLKOUT1", "CLKFBOUT"]
    for c in counters:
        regs[c + ".REG1"] = val(c, REG1)
        regs[c + ".REG2"] = val(c, REG2_SHARED if kind == "MMCM" and c in ("CLKOUT5", "CLKOUT6") else REG2)
    regs["DIVCLK"] = val("DIVCLK", DIVCLK)
    regs["LOCK1"] = lk(20, 29)
    regs["LOCK2"] = lk(30, 34) << 10 | lk(0, 9)
    # MMCM LOCK3 bit 15 is a reserved 1 (the xc7 writer's LOCKREG3_RESERVED);
    # the PLL's is 0.
    regs["LOCK3"] = (kind == "MMCM") << 15 | lk(35, 39) << 10 | lk(10, 19)
    # bit 3 is a reserved 1 (as the xc7 writer's FILTREG1_RESERVED = 0x8)
    regs["FILT1"] = 1 << 3 | tb(6) << 8 | tb(7) << 11 | tb(8) << 12 | tb(9) << 15
    regs["FILT2"] = tb(0) << 4 | tb(1) << 7 | tb(2) << 8 | tb(3) << 11 | tb(4) << 12 | tb(5) << 15
    return regs
