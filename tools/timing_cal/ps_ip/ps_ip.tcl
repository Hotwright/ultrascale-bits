# Vivado clock uncertainty of PL_CLK0 with the PS configured by its IP
# (zynq_ultra_ps_e, PL0 from the IOPLL at 100 MHz, as on the KV260). top.v has
# rising- and falling-edge FFs so both rise->rise and fall->rise are reported.
# Run from a copy of this directory under /mnt/i: vivado -mode batch -source ps_ip.tcl
set part xck26-sfvc784-2LV-c
create_project -force p proj -part $part
create_bd_design ps
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e ps8]
set_property -dict [list CONFIG.PSU__FPGA_PL0_ENABLE 1 \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL IOPLL \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ 100 \
  CONFIG.PSU__USE__M_AXI_GP0 0 CONFIG.PSU__USE__M_AXI_GP1 0 CONFIG.PSU__USE__M_AXI_GP2 0] $ps
make_bd_pins_external [get_bd_pins ps8/pl_clk0]
set_property name pl_clk0 [get_bd_ports pl_clk0_0]
validate_bd_design
save_bd_design
set_property synth_checkpoint_mode None [get_files ps.bd]
generate_target all [get_files ps.bd]
add_files [make_wrapper -files [get_files ps.bd] -top]
add_files top.v
set_property top top [current_fileset]
update_compile_order -fileset sources_1
puts "PL0 config: [get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL $ps] [get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ $ps] MHz"
synth_design -top top -part $part
set_property IOSTANDARD LVCMOS33 [get_ports led*]
set_property PACKAGE_PIN H12 [get_ports {led[0]}]
set_property PACKAGE_PIN E10 [get_ports {led[1]}]
set_property PACKAGE_PIN D10 [get_ports {led[2]}]
set_property PACKAGE_PIN C11 [get_ports {led[3]}]
opt_design
place_design
route_design
report_clocks -file clocks.rpt
report_timing -max_paths 4 -nworst 1 -group [get_clocks] -file paths.rpt
report_timing -from [get_cells n_reg*] -to [get_cells c_reg*] -max_paths 1 -file fall_rise.rpt
report_timing -from [get_cells c_reg*] -to [get_cells c_reg*] -max_paths 1 -file rise_rise.rpt
