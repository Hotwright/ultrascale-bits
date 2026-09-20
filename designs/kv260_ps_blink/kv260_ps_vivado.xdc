# The same constraints as kv260_ps.xdc, spelled for Vivado.
#
# Two differences, both of which make Vivado reject the nextpnr file outright:
#
#   * `[get_ports pmod[0]]` is Tcl, and `[0]` there is a command substitution --
#     Vivado tries to run a command named `0`. The index has to be braced.
#   * a package pin goes in PACKAGE_PIN. LOC takes a site name (IOB_X0Y12),
#     and nextpnr is simply more permissive about which one it accepts.
#
# Keep the two files in step: the point of the reference build is that Vivado
# and nextpnr are constrained identically, so a difference in the resulting
# FASM means something.

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
