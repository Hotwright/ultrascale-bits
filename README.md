# 0-ultrascale-bits

Scoping an open bitstream flow for the **Kria K26** (`XCK26-SFVC784-2LV-C`, Zynq
UltraScale+ MPSoC). Companion to `0-xilinx-bits`, which does the same job for
7-series parts — and which does **not** reach this device.

**Status: scoping only.** `prjuray-tools` builds; no fuzzer has been run, no
bitstream has been produced. Everything established so far, with the evidence,
is in [SCOPE-K26.md](SCOPE-K26.md). This file is the entry point to it.

## Findings

* **The K26 is the ZU5EV die.** `xck26-sfvc784-2lv-c` and `xczu5ev-sfvc784-1-e`
  have identical tile signatures (112,250 tiles / 9,090,733 nodes); the census
  records differ in device name, speed grade and IDCODE only. Characterise
  against the catalogue part.
* **Use PL IDCODE `0x04a49093`.** Zynq US+ has two JTAG TAPs. Reading
  `IDCODE_REGISTER` out of the BSDL — the method that worked on 7-series — gives
  the **PS** value `0x04724093` and is silently wrong for bitstream config. The
  IDCODE is also the one thing that does *not* transfer from the ZU5EV alias.
* **There is no FASM path for UltraScale+.** `nextpnr-xilinx` splits by family:
  FASM + Project X-Ray on 7-series, RapidWright + Vivado on US+. The only route
  to a real bitstream is
  `yosys → nextpnr-xilinx → json2dcp → .dcp → Vivado → .bit`.
* **prjuray's family segbits cover 99.1% of K26 tile instances.** The gaps are
  the entire left IO column (`HPIO_L`, banks 64–66), all `URAM_*` types, and
  assorted config/bridge tiles — structural absences on the ZU3EG die prjuray
  shipped, not unfinished fuzzing.
* **An output-only HDIO blinky is fully bitted today.** Banks 43/44/45 land on
  `HDIO_*` tiles that are covered, and both clock routes (`BUFGCE_HDIO` from an
  HDGC pin, PS8 `pl_clk0`) are solved. Taking a signal *in* through those banks
  depends on an unverified `OUTPUTS_ENABLED` analogue in `INT_INTF_R_PCIE4`.
* **Top open risk is chipdb size.** RapidWright's exporter does not dedupe
  nodes, and this part has 9.1M of them against xc7s25's 997k. Unmeasured.

## Layout

| path | |
| --- | --- |
| `SCOPE-K26.md` | the findings and the evidence behind them |
| `README-CLONES.md` | how to recreate the three upstream clones, pinned |
| `mk_uray_overlay.sh` | writable `prjuray/database` overlay symlinked into `prjuray-db`, which stays pristine |
| `env/uray_env.sh` | prjuray environment that bypasses the `v2019.2` Vivado gate |
| `patches/` | `<cstdint>` fixes prjuray-tools needs on GCC 13 (50 files) |

`prjuray/`, `prjuray-db/` and `nextpnr-xilinx/` are upstream clones and are not
tracked here — see `README-CLONES.md`.

## Setup

1. Clone and patch the upstreams exactly as `README-CLONES.md` records.
2. Build `prjuray-tools` per prjuray's own instructions, with the patches
   applied. `uray_env.sh` expects the binaries at
   `prjuray/third_party/prjuray-tools/build/tools`.
3. `./mk_uray_overlay.sh` — builds the overlay and refuses to run if
   `prjuray-db` is dirty.
4. `source env/uray_env.sh <config>`.

Three things will bite a fresh checkout:

* **Vivado and RapidWright come from outside this repo** — from a
  [`xilinx-bits`](https://github.com/Hotwright/xilinx-bits) checkout next to
  this one (`rw-fuzzers/env/vivado.sh` and `RapidWright/`). Without it,
  `env/uray_env.sh` falls back to `vivado` on `PATH`; set `XILINX_BITS_DIR`,
  `URAY_VIVADO` or `RAPIDWRIGHT_PATH` to point elsewhere.
* **The default config `zynq_usp_5ev` does not exist yet.** prjuray ships
  `zynq_usp_3eg` and `zynq_usp_7ev`; neither is this die. Pass one of those or
  write the 5EV settings file first.
* **prjuray pins Vivado 2019.2 and the gate is bypassed.** The 7-series side of
  this tree has already seen a fuzzer silently solve nothing under a newer
  Vivado while exiting 0. Cross-check every result against the shipped ZU3EG
  database before trusting it.

`SCOPE-K26.md` was written against the full Hotwright tree and cites sibling
checkouts (`eda-tools/`, `projects/Kria/`, RapidWright) that are not vendored
here.

## Next step

Measure risk 2 before anything else: export `xczu5ev-sfvc784-1-e` with
RapidWright's `rapidwright_bbaexport`, and see how large the `.bba` is and
whether `bbasm` completes in 31 GB. One command and a wait, and it decides
whether this flow is buildable on this machine at all. If it is, write
`prjuray/settings/zynq_usp_5ev.sh` — the data for it is already derived in
`SCOPE-K26.md` — and run the per-part tilegrid fuzzer.
