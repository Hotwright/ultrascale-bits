# KV260 J2 PMOD, bank 45, LVCMOS33. Pin assignments from the Kria-PYNQ base
# design; every one lands on an HDIO_{BOT,TOP}_RIGHT tile, which prjuray has
# segbits for.
set_property LOC H12 [get_ports pmod[0]]
set_property LOC E10 [get_ports pmod[1]]
set_property LOC D10 [get_ports pmod[2]]
set_property LOC C11 [get_ports pmod[3]]
set_property LOC B10 [get_ports pmod[4]]
set_property LOC E12 [get_ports pmod[5]]
set_property LOC D11 [get_ports pmod[6]]
set_property LOC B11 [get_ports pmod[7]]

# Clock. F11 is one of the four clock-capable (HDGC) bank-45 pins that is NOT
# already a PMOD signal - F10/G11/F11/F12 are free, D10/E10/D11/E12 are taken.
# An unconstrained clock input makes nextpnr place the IBUF arbitrarily and
# then hunt for a path to the global network across 9.1M nodes; that ran for
# 16 minutes of CPU on a 45-cell design. Giving it a real clock-capable pin
# bounds the search.
#
# the chipdb and the FASM writers end to end.
