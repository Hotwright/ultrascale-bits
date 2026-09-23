# Build a reference bitstream for the SAME design with Vivado, so prjuray's
# bit2fasm.py can say what features a correct result contains.
#
# This is validation of the open flow, not Vivado in the design loop. It is the
# test tools/check_fasm_vs_uraydb.py structurally cannot do: that one proves
# emitted features are a SUBSET of what prjuray knows, and is therefore blind
# to a feature we fail to write. Comparing against a Vivado build is the only
# way to see an omission. prjxray's own tests work the same way.
#
# Note we do NOT ask Vivado to avoid the carry chain, even though build.sh runs
# yosys with -nocarry. A Vivado build that USES CARRY8 is the cheapest way to
# learn how CARRY8.CI.CIN is encoded, which prjuray's 017-cle-precyinit emits
# as a tag but never solved. tools/diff_fasm_classes.py tolerates the resulting
# packing difference by design.
#
# Env: REF_SRC (verilog), REF_XDC, REF_TOP (default "top"), REF_OUT (directory),
#      URAY_PART.
set part $::env(URAY_PART)
set src  $::env(REF_SRC)
set xdc  $::env(REF_XDC)
set top  [expr {[info exists ::env(REF_TOP)] ? $::env(REF_TOP) : "top"}]
set out  $::env(REF_OUT)

file mkdir $out
create_project -force -part $part ref_$top $out/proj
add_files -norecurse $src
add_files -fileset constrs_1 -norecurse $xdc
set_property top $top [current_fileset]

# -flatten_hierarchy none keeps cell names close to the source, which makes the
# per-instance sections of the diff readable when a class turns out to differ.
synth_design -top $top -flatten_hierarchy none
write_checkpoint -force $out/post_synth.dcp

place_design
route_design
report_utilization -file $out/utilization.rpt
report_route_status -file $out/route_status.rpt
write_checkpoint -force $out/ref.dcp

# A design that leaves most of the die unconfigured trips UNCONSTRAINED-pin
# and unplaced-cell DRCs that are warnings for our purpose: we want the bits
# Vivado would write, not a sign-off-clean build.
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
write_bitstream -force $out/ref.bit
puts "reference build written to $out/ref.bit"
