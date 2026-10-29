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

Still native: FASM -> frames (prjuray's `fasm2frames`, Python; the browser
would run it under Pyodide with the prjuray database, as hotc does for
prjxray).
