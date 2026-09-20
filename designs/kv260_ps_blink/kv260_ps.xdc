# KV260 J2 PMOD, bank 45, LVCMOS33. Pin assignments from the Kria-PYNQ base
# design; every one lands on an HDIO_{BOT,TOP}_RIGHT tile, which prjuray has
# segbits for.
#
# Spelled for nextpnr-xilinx, whose XDC reader is not Tcl: it takes the token
# after get_ports verbatim, so `pmod[0]` is right here and `{pmod[0]}` would
# not match. It also reads the placement from LOC rather than PACKAGE_PIN.
# Vivado wants the opposite of both, which is why the reference build has its
# own file -- see kv260_ps_vivado.xdc.
#
# There is deliberately NO clock constraint. This design takes PL_CLK0 from
# the PS through an explicit BUFG_PS, so no pin is involved. (An earlier
# version of this comment described choosing a clock-capable HDGC pin; that
# belongs to the pin-clocked variant in ../kv260_pmod_blink and was left here
# by mistake.)
#
# IOSTANDARD is stated rather than left to default. fasm.cc does default it to
# LVCMOS33, which happens to be correct for a 3.3V PMOD, but a default is a
# poor thing to rely on for the one property that decides the output voltage.

set_property LOC H12 [get_ports pmod[0]]
set_property LOC E10 [get_ports pmod[1]]
set_property LOC D10 [get_ports pmod[2]]
set_property LOC C11 [get_ports pmod[3]]
set_property LOC B10 [get_ports pmod[4]]
set_property LOC E12 [get_ports pmod[5]]
set_property LOC D11 [get_ports pmod[6]]
set_property LOC B11 [get_ports pmod[7]]

set_property IOSTANDARD LVCMOS33 [get_ports pmod[0]]
set_property IOSTANDARD LVCMOS33 [get_ports pmod[1]]
set_property IOSTANDARD LVCMOS33 [get_ports pmod[2]]
set_property IOSTANDARD LVCMOS33 [get_ports pmod[3]]
set_property IOSTANDARD LVCMOS33 [get_ports pmod[4]]
set_property IOSTANDARD LVCMOS33 [get_ports pmod[5]]
set_property IOSTANDARD LVCMOS33 [get_ports pmod[6]]
set_property IOSTANDARD LVCMOS33 [get_ports pmod[7]]
