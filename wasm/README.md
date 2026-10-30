# K26 place-and-route and bitstream tools as WebAssembly

Built with the wasi-sdk recipe, prebuilt dependencies and toolchain files of
`0-xilinx-bits/wasm-build` (Series-7); only what differs is here.

- `build_nextpnr_usp_wasm.sh`: nextpnr-himbaechel (xilinx uarch) from
  `eda-tools/nextpnr` on `usp-himbaechel` -> `work/nextpnr-wasm/`. One
  device-agnostic `.wasm` (2.7 MB). The xck26 chipdb (35.8 MB, from the
  RapidWright dump) is copied beside it; CMake builds xc7z010's as a Series-7
  check.
- `build_xcframes2bit_wasm.sh`: prjuray's `xcframes2bit` (frames -> .bit) ->
  `work/prjuray-tools-wasm/tools/xcframes2bit` (0.7 MB). Its vendored abseil
  needs WASI signal emulation plus `wasi_sigmask_shim.h`.
- `gen_xc7_chipdbs.sh`: the fifteen Series-7 chipdbs hotc ships, regenerated
  with this tree -> `work/chipdb7/`. The usp work extended `constids.inc`,
  which every chipdb embeds, so the old tree's chipdbs assert
  (`idstring.cc:46`) in this binary. Same databases as before
  (0-xilinx-bits `xray-db-local` for xc7s25/s50/z010/a50t, openXC7
  prjxray-db for the rest).
- `run_wasi.mjs`: runs a WASI module under node's own WASI (`--share <dir>`
  mounts /share). Fine for xcframes2bit; node segfaults inside nextpnr (the
  Series-7 build too), so nextpnr is tested the way the browser runs it: a jco
  component behind `@yowasp/runtime`, packaged as in
  `hotc/web/nextpnr-xilinx-wasm` (`npm run all`), chipdb passed as an input
  file with `--chipdb`.

Verified 2026-10-29: kv260_ps_axi_test placed and routed by the jco-packaged
WASM nextpnr (95 s, the PS8 boundary pass included), assembled, loaded on the
board: test.sh PASS 41/41 and bursttest PASS under Linux. The WASM
xcframes2bit writes the same configuration data as the native tool, byte for
byte from the sync word on (only the .bit header's name/date differ).

Series-7 is unchanged by the switch (2026-10-29): on all sixteen parts in
hotc's `nextpnr-xilinx-wasm` tests (fifteen fabrics plus the aliased dies),
this `.wasm` with the regenerated chipdbs writes FASM byte-identical to the
previously shipped `.wasm` and chipdbs.

FASM -> frames runs in the browser too: hotc `web/fasm2frames-pyodide`
(`runFasm2FramesUsp`) runs `tools/check_fasm_vs_uraydb.py --filter` and
prjuray's `fasm2bit.fasm_to_frames` under Pyodide against a packed prjuray
zynqusp database, and hotc `web/xcframes2bit-wasm` wraps this
`xcframes2bit`. Both give output byte-identical to the native chain.
