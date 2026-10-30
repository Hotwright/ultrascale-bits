# Calibrating nextpnr's UltraScale+ timing against Vivado

These are the scripts behind CELL_SCALE / ROUTE_SCALE in nextpnr's
`himbaechel/uarch/xilinx/gen/usp_timing.py` (see SCOPE-K26.md, "Timing model").
Run Vivado from /mnt/i (the Windows install; see the env notes).

1. `tmg.tcl <rtl|yosys> <win-dir>`: Vivado builds axi.v (rtl) or a yosys
   netlist saved as `top.edf` (yosys). It writes a timing summary, the 300
   worst paths with cell detail (`*.paths.rpt`), a path list, and every
   connection's delay with tile grid points (`*.arcs.txt`; GRID_POINT_X/Y is
   nextpnr's X/Y).
2. `nodes.tcl <win-dir>`: from yosys.dcp, the node list of every single-load
   net with Vivado's delay (`nodes1.txt`).
3. `Price.java nodes1.txt priced.txt`: prices each of those routes with
   RapidWright's estimator (U-turn mode, as the dump uses), for the
   Vivado = k x model fit. Needs RAPIDWRIGHT_PATH.
4. `arcs.py`: nextpnr `--post-route` script, writing every connection's routed
   delay; `cmp.py <vivado arcs.txt> <arcs.csv>` compares delay against distance.
