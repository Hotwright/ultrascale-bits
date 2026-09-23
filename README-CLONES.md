# Reproducing the upstream checkouts

`prjuray/`, `prjuray-db/` and `nextpnr-xilinx/` are not tracked here — they are
upstream clones with their own history. Recreate them exactly:

    git clone https://github.com/f4pga/prjuray.git    && git -C prjuray    checkout c550b03
    git clone https://github.com/f4pga/prjuray-db.git && git -C prjuray-db checkout affbc5e
    git clone https://github.com/gatecat/nextpnr-xilinx.git \
        && git -C nextpnr-xilinx checkout 8f178fc

`nextpnr-xilinx` is the older standalone fork, not the himbaechel nextpnr in
`eda-tools/`. It is the only backend with UltraScale+ support. Note that its
UltraScale+ path generates bitstreams via RapidWright + Vivado; the
FASM/Project X-Ray route is 7-series only. See SCOPE-K26.md. Its four
submodules (`tests`, `3rdparty/fpga-interchange-schema`,
`xilinx/external/prjxray-db`, `xilinx/external/nextpnr-xilinx-meta`) are
uninitialized in the checkout recorded here.

`prjuray-tools` does not build on GCC 13 — 50 files relied on `<cstdint>`
arriving transitively. Apply the fixes before building:

    git -C prjuray/third_party/prjuray-tools submodule update --init --recursive
    git -C prjuray/third_party/prjuray-tools apply \
        ../../../patches/prjuray-tools-cstdint.patch
    git -C prjuray/third_party/prjuray-tools/third_party/abseil-cpp apply \
        ../../../../../patches/abseil-cstdint.patch

Then `mk_uray_overlay.sh` builds the writable overlay, and `env/uray_env.sh`
sets the environment (it bypasses prjuray's exact-`v2019.2` Vivado gate).

## nextpnr-xilinx's RapidWright exporter

`xilinx/java/bbaexport.java` was written against RapidWright ~2020 and does not
compile or run against 2026.1.0. `patches/bbaexport-rapidwright-2026.patch`
carries the port. Apply it, then build and run with `run_bbaexport.sh`, which
runs the class directly rather than from a jar (family.cmake builds a jar whose
manifest holds the whole RapidWright classpath, and a JAR manifest line cannot
exceed 72 bytes).

The port is six API fixes plus four null-guards. The guards matter: RapidWright
2026 returns null where the old API did not, and each guard counts what it
dropped so a pervasive failure cannot masquerade as a rare one. The run prints

    port summary: <n> PIPs with unresolvable nodes, <n> BEL pins with no site
    wire, <n> sites with no INT tile, <n> null PIP endpoints during node
    enumeration

Check those numbers against device size before trusting the chipdb - a silently
degraded routing graph shows up much later as an unroutable design.

## nextpnr-xilinx patches for XCK26

`patches/nextpnr-xilinx-usp-clock-bfs.patch` against `xilinx/arch.cc`. Three
things, only the first of which is a clean fix:

1. **Prune the global constant network from the dedicated-clock BFS.**
   `bbaexport` builds one VCC node and one GND node per device, each tied to
   every tile (`PSEUDO_GND: 1/112250`). Stepping into either makes the search
   frontier the whole die - traced on XCK26, popping `DSP_X12Y150/VCC_WIRE14`
   took the queue from 9 to 457 in a single expansion. A clock is never routed
   through the constant network, so this removes nothing legal. Also prunes
   `NODE_PINBOUNCE`: the existing `ID_PINBOUNCE` entry is the 7-series spelling
   and never matches an UltraScale+ device.

2. **Instrumentation**, behind environment variables, because without it there
   is no way to tell a slow search from a wedged one:
   `NEXTPNR_CLK_BFS_TRACE=1`, `NEXTPNR_CLK_BFS_EVERY=<n>` (trace every n pops;
   note `EVERY=1` calls `nameOfWire()` per pop and is itself slow enough to
   dominate the measurement - do not draw timing conclusions from it),
   `NEXTPNR_CLK_BFS_BUDGET=<pips>`, `NEXTPNR_CLK_BFS_MS=<ms>`.

3. **`NEXTPNR_SKIP_GCLK=1`** - leave clock nets to the general router.

**Outstanding bug.** Even with (1), the BFS wedges on XCK26 inside a single
`getPipsUphill()` iteration, at around pop 321 after ~320 healthy pops through
real clock resources. Neither the millisecond deadline (checked at the top of
the while loop) nor the pip budget (checked in the inner loop) can observe it,
which localises it to `UphillPipIterator::operator++` not terminating. Until
that is fixed, US+ runs need `NEXTPNR_SKIP_GCLK=1`, which **gives up the
dedicated global clock tree** - acceptable for a slow blinker, not for anything
skew-sensitive.
