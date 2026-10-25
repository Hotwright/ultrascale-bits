#!/usr/bin/env python3
"""Turn the specimens into db-corrections add-feature lines.

Bits are configuration bits only: solve.config_bits drops the frame-ECC
halfwords, which xcframes2bit recomputes and which follow everything else in
the frame. With them gone, solve.py explains every set bit in every instance.

CMT_L, per track k (crossing always as HROUTE_0_k -> MUX_2TO1_<8k+2> -> HROUTE_1_k):
  WIRE.CLK_HROUTE_1_k.USED.V1     the bit CMT_RIGHT names so (x_149..151)
  PIP.CLK_HROUTE_1_k.CLK_CMT_MUX_2TO1_<8k+2>_CLK_OUT   the other two (mux select)
  WIRE.CLK_HDISTR_0_k.USED.V1     one bit, at CMT_RIGHT's position
RCLK_CLEM_CLKBUF_L, per track k:
  PIP.CLK_HROUTE_Rk.CLK_HROUTE_Lk.FWD   13_(46-2k) 13_(47-2k)
  WIRE.CLK_HROUTE_Lk.USED.V1            12_(46-2k)

    emit.py cmt_l|rclk_clem_clkbuf_l
"""
import collections, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import solve2

CMT_RIGHT_USED = os.path.join(solve2.solve.ROOT, "prjuray-db/zynqusp/segbits_cmt_right.db")


def cmt_l():
    used = {}
    for line in open(CMT_RIGHT_USED):
        m = re.match(r"CMT_RIGHT\.WIRE\.CLK_HROUTE_1_(\d+)\.USED\.V1 (\S+)$", line.strip())
        if m:
            used[int(m.group(1))] = m.group(2)
    xing, hd = collections.defaultdict(list), collections.defaultdict(list)
    for s, t, fs, bits in solve2.instances():
        names = {"%02d_%02d" % b for b in bits}
        for f in fs:
            m = re.match(r"XING(\d+)$", f)
            if m:
                xing[int(m.group(1))].append(names)
            m = re.match(r"HD(\d+)\.", f)
            if m:
                hd[int(m.group(1))].append(names)
    for k in range(24):
        bits = set.intersection(*xing[k])
        assert used[k] in bits, (k, used[k], bits)
        print("CMT_L.WIRE.CLK_HROUTE_1_%d.USED.V1 add-feature %s" % (k, used[k]))
        print("CMT_L.PIP.CLK_HROUTE_1_%d.CLK_CMT_MUX_2TO1_%d_CLK_OUT add-feature %s  # %d specimens"
              % (k, 8 * k + 2, " ".join(sorted(bits - {used[k]})), len(xing[k])))
        print("CMT_L.WIRE.CLK_HDISTR_0_%d.USED.V1 add-feature %s  # %d instances"
              % (k, " ".join(sorted(set.intersection(*hd[k]))), len(hd[k])))


def rclk_clem_clkbuf_l():
    for k in range(24):
        print("RCLK_CLEM_CLKBUF_L.PIP.CLK_HROUTE_R%d.CLK_HROUTE_L%d.FWD add-feature 13_%02d 13_%02d"
              % (k, k, 46 - 2 * k, 47 - 2 * k))
        print("RCLK_CLEM_CLKBUF_L.WIRE.CLK_HROUTE_L%d.USED.V1 add-feature 12_%02d" % (k, 46 - 2 * k))


if __name__ == "__main__":
    {"cmt_l": cmt_l, "rclk_clem_clkbuf_l": rclk_clem_clkbuf_l}[sys.argv[1]]()
