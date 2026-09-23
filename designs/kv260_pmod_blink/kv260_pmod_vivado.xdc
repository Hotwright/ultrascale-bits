# The same constraints as kv260_pmod.xdc, spelled for Vivado. Read that file
# for why these particular pins -- especially the DRC PLIO-9 rule that rules
# out the N side of a clock pair, and the fact that F12 is not brought out on
# the KV260 carrier at all.
#
# Two differences from the nextpnr file, either of which Vivado rejects:
#
#   * `[get_ports pmod[0]]` is Tcl, and `[0]` there is a command substitution.
#     The index has to be braced.
#   * a package pin goes in PACKAGE_PIN; LOC takes a site name.
#
# No create_clock, deliberately. nextpnr is given no timing constraint either,
# and the reference build is only useful while both tools see the same thing.
#
# Note this design cannot run on the board: a PMOD LED module is output only,
# so nothing drives G11. It exists to exercise the HDIO input path end to end.

set_property PACKAGE_PIN H12 [get_ports {pmod[0]}]
set_property PACKAGE_PIN E10 [get_ports {pmod[1]}]
set_property PACKAGE_PIN D10 [get_ports {pmod[2]}]
set_property PACKAGE_PIN C11 [get_ports {pmod[3]}]
set_property PACKAGE_PIN B10 [get_ports {pmod[4]}]
set_property PACKAGE_PIN E12 [get_ports {pmod[5]}]
set_property PACKAGE_PIN D11 [get_ports {pmod[6]}]
set_property PACKAGE_PIN B11 [get_ports {pmod[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {pmod[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod[7]}]

set_property PACKAGE_PIN G11 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
