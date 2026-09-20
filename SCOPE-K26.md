# Scoping an open flow for the Kria K26 (XCK26-SFVC784-2LV-C)

> **This began as scoping and is no longer that.** Sections up to "Tooling
> status" are the original survey, kept because their measurements still hold.
> **For where the work actually stands, jump to
> [STATUS 2026-09-19](#status-2026-09-19-the-fasm-path-now-exists-and-we-built-it).**
> Short version: yosys → nextpnr-xilinx → FASM runs on the XCK26 with no vendor
> tool, and 977 of the 978 features it emits are known to prjuray-db.
> `part.yaml` is done; `tilegrid.json` is the remaining blocker.

## What to run, in order

Everything below the first line is staged and tested as far as it can be
without `tilegrid.json`. Run it in this order; each step says why it exists.

| | command | what it settles |
| --- | --- | --- |
| 1 | `./env/run_uray_fuzzers.sh 002` | produces `tilegrid.json`. ~3.5 h at `URAY_JOBS=4`. Count **`design.bit`** for progress -- `design.bits` lags it by the whole bitread step. |
| 1b | `./env/add_missing_tilegrid_fuzzers.sh` | restores the four sub-fuzzers disabled on the wrong criterion. **`rclk_pss_alto` is the one that matters** -- it is the only thing that addresses `RCLK_INTF_LEFT_TERM_ALTO`, where `PL_CLK` enters the fabric |
| 2 | `./env/finish_tilegrid.sh` | audits whether every tile type the designs use has an address, fills the ones 002 structurally cannot produce, then smoke-tests the round trip by decoding a specimen the fuzzer built and checking the features land in the tiles its `params.csv` names |
| 3 | `./env/reference_build.sh` | the one Vivado run. Answers `required ⊆ emitted` by class diff, and says whether Vivado sets bits in the three clock-spine tiles |
| 4 | `./designs/make_bitstream.sh` | FASM → `.bit` → `.bit.bin`, and round-trips our own bitstream back to FASM to check the assembler and disassembler agree |
| 5 | `sudo fpgautil -b blink_ps.bit.bin -f Full` | on the board. Check `/sys/kernel/debug/clk/clk_summary` for `pl0` first -- `fpgautil` does not touch clocks |

Step 1b can be skipped only if `rclk_pss_alto/build_*/segbits_tilegrid.tdb`
already exists -- it is being built alongside step 1 in this session, and the
script detects that and moves on.

Only step 5 has never been exercised in any form.

The original question was "what would a real flow actually need", and the short
answer was that **none of `0-xilinx-bits` reaches this part**, but the pieces
for a different flow do exist and are in better shape than expected.

## The part

Vivado files XCK26 under `zynquplus` — Zynq **UltraScale+** MPSoC, not 7-series.
It is treated as a device in its own right (`device xck26`), not as an alias of
a catalogue ZU part.

| | XCK26 | xc7s25, for scale |
| --- | --- | --- |
| tiles | 112,250 | 10,710 |
| nodes | 9,090,733 | 996,857 |
| PL IDCODE | `0x04a49093` | `0x037c4093` |

### The IDCODE has two values, and the obvious one is the wrong one

Reading `IDCODE_REGISTER` out of the BSDL is how xc7s25's and xc7z007s's IDCODEs
were derived. **That method silently gives the wrong answer here.** For
`xck26_sfvc784.bsd` it yields `0x04724093`, while Vivado's part property is
`0x04a49093`. Both are real; they are different TAPs.

Zynq UltraScale+ has two JTAG TAPs, and the BSDL says so in its instruction
list:

    "IDCODE         (001001001001),"  -- PS IDCODE, DEVICE_ID reg
    "IDCODE_PL      (100100100101),"  -- PRIVATE, PL IDCODE, DEVICE_ID reg

`IDCODE_REGISTER` describes the **PS** TAP. Bitstream configuration checks the
**PL** IDCODE. They share the manufacturer field and differ in family and array
size. On 7-series there is one TAP, so the two coincide and the BSDL method is
safe — which is exactly why this is worth writing down.

**Use `0x04a49093`.**

## What prjuray gives us

`prjuray` is the UltraScale/UltraScale+ sibling of prjxray, same authors, same
shape. Cloned to `prjuray/` and `prjuray-db/`.

* Settings ship for two parts: `xczu3eg-sfvc784-1-e` and `xczu7ev-ffvc1156-2-i`.
  Note the first is **the same package as the K26**, SFVC784.
* `prjuray-db/zynqusp/` has complete-looking data for ZU3EG only:
  `tilegrid.json` (15 MB), `tileconn.json` (84 MB — the wire graph),
  `part.yaml`, `package_pins.csv`, 158 tile types, 41 site types.
* **56 `segbits_*.db` files sit at the family level**, not per part — the same
  structure prjxray uses. That is the important one: bit definitions per tile
  type are shared across the family, so they plausibly transfer to any zynqusp
  die without refuzzing.

If that holds, what a new die needs from prjuray is the *per-part* layer only —
`tilegrid`, `tileconn`, `part.yaml`, `package_pins` — i.e. fuzzers `001`, `002`,
`004`, `005`, not the whole catalogue.

**The structure says it should hold.** Segbit entries are keyed on tile-type
relative bit coordinates and carry no part or die identity:

    CLEL_L.ABCDFF.CEUSED.V0 !14_07
    CLEL_L.ABCDFF.CLKINV.V0 !08_19

No part or die name appears in any of the 56 files, `tile_types/` (158 entries)
is family-level as well, and `origin_info` records which *fuzzer* solved a bit,
not which part. That is precisely prjxray's split: family-level tile-type bit
definitions, plus a per-die `tilegrid` mapping tile instances to frame
addresses.

**And the 7-series side supplies direct evidence for exactly this claim.** When
074 was run from scratch on xc7s25 and its family files pushed, **all 151 files
that also exist upstream came out identical in content** — upstream's having
been measured on the xc7s50 die, under a Vivado eight years older. Family-level
tile-type data demonstrably transfers across dies within a family. There is no
reason zynqusp should differ, though it is still worth confirming on the first
solver fuzzer rather than assumed.

### The ZU3EG data does not cover the K26

The package matching (both SFVC784) raised the hope that prjuray's shipped part
was the same silicon. It is not — censused with the same tile-signature pass
used on the 7-series dies:

| part | PL IDCODE | tiles | nodes |
| --- | --- | --- | --- |
| `xck26-sfvc784-2lv-c` | `0x04a49093` | 112,250 | 9,090,733 |
| `xczu3eg-sfvc784-1-e` | `0x04a42093` | 66,385 | 5,281,651 |

Same package, different die — roughly 1.7x the fabric. So the per-part layer
(`tilegrid`, `tileconn`, `part.yaml`, `package_pins`) has to be produced for the
K26 regardless; only the family-level segbits stand a chance of transferring.

### The K26 *is* the ZU5EV die — and that is the useful finding

Censused with the same full-tile-signature comparison that established
xc7z007s -> xc7z010. `xck26-sfvc784-2lv-c` and the catalogue part
`xczu5ev-sfvc784-1-e` are the same silicon:

| part | PL IDCODE | tiles | nodes | tile signature |
| --- | --- | --- | --- | --- |
| `xck26-sfvc784-2lv-c` | `0x04a49093` | 112,250 | 9,090,733 | `87c8393fe05b` |
| `xczu5ev-sfvc784-1-e` | `0x04a46093` | 112,250 | 9,090,733 | `87c8393fe05b` |
| `xczu3eg-sfvc784-1-e` | `0x04a42093` | 66,385 | 5,281,651 | `3aacb2e03bc8` |
| `xczu7ev-ffvc1156-2-i` | `0x04a5a093` | 165,682 | 16,281,755 | `6d719b069eb4` |

The census records differ in **three fields only**: device name, speed grade
(`-2LV` against `-1`) and IDCODE. Everything describing the fabric is identical.

Two consequences:

* Characterisation can target `xczu5ev-sfvc784-1-e`, an ordinary catalogue part,
  rather than the Kria-specific `xck26`. Vendor tooling, prjuray settings and
  RapidWright all deal with catalogue parts more predictably, and the result
  transfers to the K26 unchanged.
* **The IDCODE does not transfer, and that is a trap with precedent.** This is
  the xc7z007s/xc7z010 situation exactly: a bitstream built through the alias
  carries the aliased die's IDCODE and the real device rejects it. Whatever
  plays the part.yaml role here must carry `0x04a49093` for a K26, not ZU5EV's
  `0x04a46093`.

Neither of prjuray's two shipped settings is this die: ZU3EG is 0.6x it and
ZU7EV is 1.5x it. A `zynq_usp_5ev.sh` would have to be written, by analogy with
the two that exist.

## What nextpnr does NOT give us

`himbaechel/uarch/xilinx` is 7-series in practice. It mentions UltraScale tile
types (`CLEL_L`, `CLEL_R`, `CLEM`, `CLEM_R`, `BUFCE_BUFCE`, `HPIO_VREF`) but in
**six identifier uses in one file**, with no bel or pip modelling behind them —
vestigial, from the port of gatecat's standalone arch. And
`gen/xilinx_gen.py` has **zero** awareness of prjuray: its only database
argument is `--xray`, a prjxray family directory.

So the xc7s25 chipdb path does not extend to the K26. The viable backend is the
older **`nextpnr-xilinx` fork**, which does support UltraScale+ — but via
**RapidWright**, not prjuray:

    java -jar rapidwright_bbaexport.jar <device> xilinx/constids.inc xilinx/<device>.bba

Its README warns these databases run to **several gigabytes** on large devices,
and that nodes are not deduplicated (only bels, tile wires and pips). At 9.1M
nodes, XCK26 is a large device.

## What RapidWright gives us, and it is the good news

RapidWright is already in this tree, and it knows XCK26 **by name**:
`src/com/xilinx/rapidwright/util/DataVersions.java` lists `xck26-db-dat` and
`xck26_db`, and there is a timing test referencing `xck26`. The local checkout
has 7-series device data only (artix7, kintex7, spartan7, zynq), but
UltraScale+ device files download on demand.

So the routing graph — the part prjuray does *not* supply — is available for
this exact part, from a tool already installed.

## Risk 1, measured: how much of the K26 the ZU3EG data actually covers

This was called the decisive question below, and it is now answered rather than
estimated. Two measurements, both against the census of `xck26-sfvc784-2lv-c`.

**By tile instance the family data is nearly complete; by tile type it is not:**

| | |
| --- | --- |
| tile types on the XCK26 | 195 |
| tile types in `prjuray-db/zynqusp/tile_types/` | 158 |
| XCK26 types with **no** `tile_type_*.json` | **88** (957 tile instances) |
| coverage by tile *instance* | **111,293 / 112,250 = 99.1%** |
| tile-type stems with a `segbits_*.db` | 27 |

That 99.1% measures **structure** — whether a `tile_type_*.json` exists. The
*solved bits* are the 27 `segbits_*` stems, a much narrower set. The two happen
to coincide for everything a CLB+HDIO design touches, which is the point below,
but they are not the same number and the structural one must not be read as bit
coverage.

The 0.9% is not spread thinly — it is three specific structures, and which one
you need decides everything:

* **The whole left IO column.** `HPIO_L` x8, plus `HPIO_L_RBRK`, `HPIO_L_TERM_B/T`,
  `RCLK_HPIO_L` x4, `INT_INTF_L_IO` x176 and `XIPHY_BYTE_L` x16. prjuray-db
  carries **`HPIO_RIGHT` only** — the ZU3EG die has no left HPIO column, so this
  is a structural absence, not an unfinished fuzz.
* **All six `URAM_*` types** (`URAM_URAM_FT` x12, `_DELAY_FT`, `_RBRK_FT`,
  `_TERM_B/T_FT`, `RCLK_RCLK_URAM_INTF_L_FT`). The ZU5EV has 64 URAM288 blocks;
  the ZU3EG has none at all. prjuray's data structurally *cannot* cover this.
  This is the exact analogue of the `MONITOR_*_FUJI2` gap found on xc7s25.
* Assorted config/clocking/bridge tiles (`INT_IBRK_FSR2IO` x240,
  `INT_INTF_R_TERM_GT` x240, `INT_INTF_L_CMT` x64, `RCLK_CLEL_L_R` x12, …).

**Everything a blinky touches is on the covered side.** All 13 `CLE*` types are
covered, including the bulk `CLEM` x6480 and `CLEL_R` x6240. And the IO splits
cleanly by bank:

| banks | tile type | user IO pins | in prjuray-db? |
| --- | --- | --- | --- |
| 43, 44, 45 | `HDIO_BOT_RIGHT` / `HDIO_TOP_RIGHT` | 70 | **yes** — 828 + 812 segbits |
| 64, 65, 66 | `HPIO_L` | 119 | **no** — nothing at all |

The KV260 routes its PMOD entirely to **bank 45**, LVCMOS33, pins
`H12 E10 D10 C11 B10 E12 D11 B11`. Every one of them lands on an `HDIO_*` tile
this data covers, and four of them (`E10 D10 E12 D11`, the `HDGC` pins) are
clock-capable feeding `BUFGCE_HDIO`, which `segbits_rclk_hdio.db` solves in full
(512 lines, `RCLK_HDIO.BUFGCE_HDIO_X{0,1}Y{0,1}`). The PS8 route is also partly
bitted (`segbits_int_intf_left_term_pss.db` 50 lines,
`segbits_rclk_intf_left_term_alto.db` 456), so a `pl_clk0` clock is not ruled
out either.

Both clock routes are bitted, which is better than expected:

* **External clock in through an HDGC pin** → `BUFGCE_HDIO`, fully solved.
* **PS8 `pl_clk0`** → `segbits_rclk_intf_left_term_alto.db` carries **384
  `CLK_BUFG_PS_*_CLK_IN`/`_CLK_OUT` lines**, so the PS-to-PL clock buffer is
  bitted too. That still needs a PS8 cell in whatever backend is used, but the
  bitstream side is not the obstacle.

### One real hole on the path into the pad

Checking the pad tile alone is not enough — the column between `INT` and the
pad has to carry the signal. At the PMOD tile's row the order is:

    col 192  INT                  col 193  INT_INTF_R_PCIE4   col 194  HDIO_TOP_RIGHT

A pip needs a configuration bit only if its destination has more than one
possible source; a fan-in of one is unconditional wiring with nothing to select.
By that test:

| tile | pips | real muxes (fan-in > 1) | segbits |
| --- | --- | --- | --- |
| `INT` | 3774 | 722 | yes |
| `INT_INTF_R_PCIE4` | 176 | **48** | **no** |
| `HDIO_TOP_RIGHT` | 188 | **0** | yes (828 — all site config, no routing) |

So the pad tile is clean: its 188 pips are all fan-in 1, and its 828 segbits are
IOB configuration (IOSTANDARD, DRIVE, SLEW…), not routing. But
`INT_INTF_R_PCIE4` has 48 genuine 2:1 muxes and **no segbits file at all**.

What they select is specific:

    IMUXOUT0  <- { IMUX0,  DELAYWIRE_PCIE   }
    IMUXOUT1  <- { IMUX1,  DELAYWIRE_PCIE_11 }
    ...  48 of these, one per IMUX input

— the normal INT IMUX against a PCIe delay wire. prjuray names exactly this
class of feature where it *has* fuzzed it, in the PSS analogue:
`INT_INTF_LEFT_TERM_PSS.PIP.DELAYWIRE_XIPHY_10.IMUX_FT0_3`. So these are real,
bitted features on this silicon; they are simply unfuzzed for the `*_PCIE4`
variants.

It was never fuzzed, rather than fuzzed and found bitless. prjuray has 20
fuzzers and the PSS segbits come from `070-ps8-int`, which is PS8-specific;
there is no `0xx-pcie4-int` analogue. PCIE4 appears only in
`002-tilegrid/intf_r_pcie4_hdio/`, which establishes frame addresses, not bits.

**The risk splits cleanly by signal direction**, and that is what makes it
tractable. Classifying the same 176 pips by destination:

| direction | destinations | fan-in | needs a bit? |
| --- | --- | --- | --- |
| pad → fabric (`LOGIC_OUTS`) | 32 | **all 1** | **no** — unconditional wiring |
| fabric → pad (`IMUX` → `IMUXOUT`) | 48 | 2 | yes, and unfuzzed |
| internal (`DELAYWIRE_PCIE`) | 48 | 1 | no |

So the *input* direction through this interface is hard-wired — nothing to
configure, nothing that can be wrong. The 48 unbitted muxes are all in the
output direction, and they select the PCIe delay wire *over* the normal IMUX.
Since the FASM feature asserts the override (`…PIP.DELAYWIRE_XIPHY_10.IMUX_FT0_3`
in the PSS analogue), a design that does not want the delay wire emits nothing
and all-zero is the correct encoding.

**The one genuinely open item is `OUTPUTS_ENABLED`.** In the PSS tile it is a
real bitted feature, and `070-ps8-int/dump_features.tcl` shows how it is
derived: the fuzzer sets `OUTPUTS_ENABLED.1` on any tile where a `LOGIC_OUTS`
pip is used, `.0` otherwise. It is therefore a tile-level enable for the
**pad→fabric** direction, not a pip selection. If `INT_INTF_R_PCIE4` carries an
equivalent and it is never set, every *input* through banks 43/44/45 is dead —
including an external clock arriving on an HDGC pin — and nothing in the
database would say so.

**So, precisely:**

* An **output-only** blinky (drive an LED, clocked from PS8 `pl_clk0`) touches
  none of the unknowns. Every bit it needs exists today.
* A design taking anything **in** through banks 43/44/45 — a button, or a clock
  on an HDGC pin — depends on whether that `OUTPUTS_ENABLED` analogue exists.
  One specimen settles it: route one input through the interface, diff the
  frames, see whether a bit moves.
* An **HP-bank** design, or anything using **UltraRAM**, needs real fuzzing.

One more thing worth recording, because it changes the cost of the HP case.
`HPIO_L` on the ZU5EV is **structurally identical** to prjuray's `HPIO_RIGHT`:

    BIAS x1  HPIOBDIFFINBUF x12  HPIOBDIFFOUTBUF x12
    HPIOB_M x12  HPIOB_S x12  HPIOB_SNGL x2  HPIO_VREF_SITE x1

— same seven site types, same counts, in both. That makes transfer *conceivable*
where the URAM gap makes it impossible. It does **not** make it safe: segbits are
bit offsets within a tile's frames, and a mirrored column can lay them out
differently. prjxray keeps `liob33` and `riob33` as separate segbits files on
7-series for exactly this reason. Treat HPIO_L as "one fuzz run, not one
`cp`" — but a fuzz run with a known-good target to validate against.

## Tooling status

`prjuray-tools` now builds. It did not out of the box: GCC 13 stopped pulling
`<cstdint>` in transitively, and neither prjuray's own sources nor its vendored
abseil-cpp include it. 50 files needed the one-line fix (49 in prjuray, 1 in
`third_party/abseil-cpp/absl/strings/internal/str_format/extension.h`). All
targets build now, including the ones that matter here — `bitread`,
`xcframes2bit`, `xcpatch`, `xcu_frame_address_decoder`, `gen_part_base_yaml`,
`segmatch`, `bits2rbt`.

That patch is **inside a git submodule and not committed** — a
`git submodule update` will wipe it and the next session will hit `tools exit=2`
with no record of why. It is saved as `patches/prjuray-tools-cstdint.patch` (540
lines) and `patches/abseil-cstdint.patch` (12 lines); re-apply with `git apply`
in the respective checkout.

Note also that prjuray gates on Vivado `v2019.2` exactly, and silently sets
`URAY_DIR=/bad/vivado/version` otherwise. `env/uray_env.sh` bypasses that. The
bypass is documented there, with the warning that prjxray's `cfg` fuzzer broke
in precisely this way on a newer Vivado and solved nothing while exiting 0.

## CORRECTION: there is no FASM path for UltraScale+

An earlier draft of this document drew the flow as
`yosys -> nextpnr-xilinx -> FASM -> prjuray -> .bit`. **That path does not
exist.** Established by reading the `nextpnr-xilinx` fork itself, now cloned at
`nextpnr-xilinx/`. Its README states the split outright:

> - UltraScale+ with RapidWright database generation, bitstream generation
>   using RapidWight and Vivado
> - [7-series] using FASM and Project Xray (no Vivado anywhere in the flow)

The shipped `xilinx/examples/zcu104` (a ZU7EV, the closest thing to a K26 in
the tree) confirms it — its `blinky.sh` is:

    yosys -> nextpnr-xilinx -> rapidwright_json2dcp.jar -> .dcp -> vivado -> .bit

So the "no Vivado anywhere" property is a **7-series-only** property of this
toolchain, not a property of nextpnr.

`--fasm` is not *gated* on 7-series — `UspCommandHandler::customBitstream`
calls `ctx->writeFasm()` unconditionally — but `fasm.cc` (1641 lines) contains
no family branching at all and hardcodes 7-series names: `IOB33` x5, `IOI3` x4,
`CLBLM` x3, `SLICEL_X0/X1`, `SLICEM_X0`. On an UltraScale+ chipdb those
branches simply never match, so it would emit FASM with the IO and parts of the
slice handling silently missing. That is the worst failure mode: output that
looks plausible and is wrong.

**Consequence for the K26.** Two different projects, and they should not be
confused:

* **Open synthesis + open place & route, Vivado for bitstream assembly only.**
  Supported upstream, trodden by the zcu104 example, and the only path to a
  bitstream on a real K26 in reasonable time. nextpnr does the real work;
  Vivado is reduced to a DCP-to-bitstream converter.
* **A genuinely vendor-free US+ bitstream.** Needs *three* things, not one:
  a US+ IO/slice path written into `fasm.cc`; the per-part tilegrid for the
  ZU5EV die (prjuray-db ships `part.yaml` for **only two ZU3EG parts** —
  confirmed by listing it); and the segbits gaps in this document. That is a
  project, not a patch.

The measured coverage results below still stand and still matter — they are
what a vendor-free path would be built on — but they are no longer on the
critical path to a first working bitstream.

## The shape of a flow, and where the risk is

    yosys --synth_xilinx--> nextpnr-xilinx --json2dcp--> .dcp --vivado--> .bit
                                   ^
                       RapidWright XCK26 chipdb
                       (exists, downloadable)

    (the FASM/prjuray arm of this diagram is 7-series only - see the
     correction above)

Re-ordered now that risk 1 has been measured. It was the decisive one; it is no
longer the blocking one.

1. ~~**Do the family segbits transfer?**~~ **Answered: for a CLB+HDIO blinky,
   yes — 99.1% by tile instance, and every tile such a design touches is
   covered.** The gaps are the left IO column, UltraRAM, and some config/GT
   bridge tiles. Scope your first design away from those and this is not a
   blocker. The per-part layer (`tilegrid`, `tileconn`, `part.yaml`,
   `package_pins`) still has to be generated for the ZU5EV die regardless.
2. **Chipdb size and RAM — now the top risk.** 9.1M nodes against xc7s25's 997k,
   and RapidWright's exporter does not dedupe nodes. This machine has 31 GB.
   A multi-gigabyte chipdb may not build here at all, and would be hostile to
   the WASM packaging besides. Nothing has been measured here yet; it should be
   the next thing measured.
3. **`nextpnr-xilinx` is a separate, older fork.** Not himbaechel, not the
   checkout in `eda-tools/`. Adopting it means maintaining two nextpnrs, or
   porting its UltraScale+ support forward — neither is small.
4. **The PL is not enough.** A K26 needs its PS brought up — FSBL, PMU firmware,
   BOOT.BIN — before the fabric is usable. 7-series parts need none of that.
   `projects/Kria/` already has the vendor boot artifacts, so this is a known
   quantity, but it is not part of an "open flow" in the way the 7-series work is.

## STATUS 2026-09-19: the FASM path now exists, and we built it

Everything above stands as written, including the correction that *upstream*
`nextpnr-xilinx` has no FASM path for UltraScale+. It does now, in this tree.

`designs/kv260_pmod_blink/build.sh` runs the whole flow with **no vendor tool
anywhere**:

    blink.v -> yosys (synth_xilinx -family xcup -nocarry)
            -> nextpnr-xilinx (chipdb xck26.bin, from RapidWright)
            -> blink.fasm  (prjuray feature syntax)
            -> tools/check_fasm_vs_uraydb.py

and finishes in well under a minute.

### Acceptance: 977 of 978 emitted features are known to prjuray-db

`tools/check_fasm_vs_uraydb.py` checks every feature the FASM emits against
prjuray-db's segbits, per tile type. It matters because prjuray's assembler does
**not** ignore a feature it has never heard of: `utils/fasm_assembler.py`
collects every one and then raises

    FasmLookupError: Segment DB <tile type>, key <feature> not found ...

so one stray name makes `fasm2bit.py` refuse the whole file, and there is no
flag to relax it. (An earlier version of this section said such a feature
"assembles to nothing, silently". That was wrong, and wrong in the optimistic
direction -- it is a hard error, which is the better behaviour but a harder
constraint.)

`--filter` writes a copy with the unknown features removed and names each one.
Both `build.sh` scripts run it. On the PS design it drops exactly 11:

* 8 `INT_INTF_R_PCIE4.PIP.IMUXOUT16.IMUX16`. Safe: the fan-in analysis above
  shows the pad-to-fabric direction of that tile is unconditional wiring, fan-in
  1, with nothing to configure.
* 3 `WIRE.CLK_HDISTR_*.USED.V1`, in `RCLK_RCLK_XIPHY_INNER_FT`,
  `RCLK_INTF_LEFT_TERM_ALTO` and `RCLK_CLEM_CLKBUF_L`. All three sit on the
  clock spine at Y149, between the PS clock buffer and the leaf buffer that
  feeds the flip-flops. If the distribution track needs a per-tile enable in
  each, dropping one means the clock never arrives and the LEDs never blink.

  **This has now been measured.** `tools/explain_missing_feature.py` asks the
  question that matters: is a feature missing because the fuzzer looked and
  found nothing, or because it never looked? The two call for opposite
  responses.

  **The discriminating check is not "does the tile type have a segbits file".**
  That was the first answer here and it was wrong. segmaker drops a tag that
  never varies, so "fuzzed and found no bit" and "never drove this wire" leave
  an identical, empty trace. The check that separates them is whether the tile
  type has *any* feature at all -- a pip, anything -- naming a `CLK_HDISTR`
  wire, and whether the tile type has those wires to begin with
  (`prjuray-db/zynqusp/tile_types/tile_type_*.json`).

  | tile type | HDISTR wires | any HDISTR feature | HDISTR `.USED.` | reading |
  | --- | ---: | ---: | ---: | --- |
  | `RCLK_INT_L` | 24 | **768** | **0** | exercised hard, no enable exists |
  | `RCLK_HDIO` | 24 | 96 | 48 | enable per wire (24x2) |
  | `RCLK_DSP_INTF_CLKBUF_L` | 48 | 144 | 96 | enable per wire |
  | `RCLK_XIPHY_OUTER_RIGHT` | 48 | 48 | 48 | enable per wire |
  | `CMT_RIGHT` | 24 | 48 | 48 | enable per wire |
  | `RCLK_CLEM_L`, `_R`, `RCLK_CLEL_L_L`, `RCLK_DSP_INTF_L` | 24 | **0** | 0 | never exercised -- unknown |
  | `RCLK_INTF_LEFT_TERM_ALTO` | 24 | **0** | 0 | never exercised -- unknown |
  | `RCLK_CLEM_CLKBUF_L` | -- | no tile_type json | -- | absent from the ZU3EG |
  | `RCLK_RCLK_XIPHY_INNER_FT` | -- | no tile_type json | -- | absent from the ZU3EG |

  `RCLK_INT_L` is the positive control and the one clean negative: 768 HDISTR
  features and not one enable bit, so a track crossing `RCLK_INT_L` needs no
  per-tile enable. Every tile type that *taps or sources* a clock -- HDIO, the
  CLKBUF tiles, XIPHY, CMT -- has an enable for every HDISTR wire it carries.

  An earlier version of this section called `RCLK_INTF_LEFT_TERM_ALTO` a
  solved negative and therefore **safe**. That was wrong, and wrong in the
  expensive direction: it has the 24 HDISTR wires and the fuzzers produced
  **zero** features on any of them. It is unknown, not safe. What its segbits
  do contain is 360 `PIP.CLK_BUFG_PS_*_CLK_IN` features and 48 `CLK_HROUTE`
  enables -- `071-ps8-bufg` fuzzed exactly the PS-to-fabric path through this
  tile, and the path it found leaves `BUFG_PS` onto **HROUTE**.

  **Our FASM agrees with that, which is the reassuring part.** The whole clock
  path in `blink_ps.fasm` is characterised end to end:

      RCLK_INTF_LEFT_TERM_ALTO  PS_TO_PL_CLK0 -> CLK_BUFG_PS_0_CLK_IN
                                CLK_BUFG_PS_0_CLK_OUT -> CLK_HROUTE0   (+USED)
      RCLK_DSP_INTF_L           CLK_HROUTE_CORE_OPT0 -> CLK_CMT_MUX_3TO1_0
                                -> CLK_VDISTR_BOT0                     (+USED)
      RCLK_HDIO                 CLK_HROUTE_L0, CLK_HDISTR_FT0_0        (+USED)
      RCLK_INT_L                CLK_HDISTR_FT0_0 -> CLK_LEAF_SITES_3_CLK_IN
                                BUFCE_LEAF_X0Y2.IN_USE

  Every one of those is known to prjuray-db. The three dropped features are
  `USED` marks on the HDISTR node where it crosses three *other* tiles in the
  same row. `RCLK_HDIO` proves the mark is needed where a bit exists for it.

  So the position is: two of the three (`RCLK_CLEM_CLKBUF_L`,
  `RCLK_RCLK_XIPHY_INNER_FT`) are tile types the ZU3EG does not have at all,
  their characterised siblings all carry the enable, and they are **probably
  real bits we fail to set**. The third is on a different wire
  (`CLK_HDISTR_FT1_0`) from the live path in a tile whose HDISTR was never
  touched, and is simply **unknown**.

  **A checkable prediction, made before `002` finished.** The three tiles are
  not in the same situation, and the basicdb grid already says which:

  | tile instance | grid | sites | needs |
  | --- | --- | ---: | --- |
  | `RCLK_INTF_LEFT_TERM_ALTO_X0Y149` | (159,93) | **24** | **`rclk_pss_alto`, which was wrongly disabled** -- see below |
  | `RCLK_CLEM_CLKBUF_L_X15Y149` | (226,93) | 0 | a derived address; `RCLK_INT_L` (32 sites) sits at dx=1 right and `RCLK_DSP_INTF_L` at dx=2 left, so the span is short and should pin |
  | `RCLK_RCLK_XIPHY_INNER_FT_X16Y149` | (278,93) | 0 | a derived address; nearest addressable anchor is dx=3 right across `RCLK_INTF_L_IBRK_IO_L`, so this one may stay free |

  Two distinct failures hide behind one symptom. What `LEFT_TERM_ALTO` lacks
  is a *segbit* for the HDISTR enable, which no amount of address derivation
  supplies -- but it turns out to lack an address too, for a third reason
  again.

  **Four of 002's sub-fuzzers were disabled on the wrong criterion, and one of
  them matters.** The justification recorded in
  `patches/prjuray-002-tilegrid-xck26.patch` was that the tile types they are
  *named after* have zero instances on this die. That reasoning does not apply
  to them: each scans for a **site type** and configures whichever tile holds
  it, and none mentions its namesake tile type anywhere. The XCK26 simply has
  the left-hand variants where the ZU3EG had the right-hand ones.

  | sub-fuzzer | site it looks for | where that site lives on the XCK26 | confirmed |
  | --- | --- | --- | --- |
  | `rclk_pss_alto` | `BUFG_PS` | 96 in `RCLK_INTF_LEFT_TERM_ALTO` (4 tiles) | **yes** |
  | `cmt_right` | `BUFCE_ROW` | 96 in `CMT_L` (4) | **yes** |
  | `bitslice_tiles` | `BITSLICE_RX_TX` | 208 in `XIPHY_BYTE_L` (16) | **yes** |
  | `hpio_right` | `HPIOB_M`/`_S` | 164 in `HPIO_L` (8) | not tested |

  "Confirmed" means its `top.py` was run against this die's basicdb and its
  `params.csv` came out naming exactly those tiles -- for `rclk_pss_alto`, the
  four `RCLK_INTF_LEFT_TERM_ALTO` instances including `X0Y149`, the one this
  design's clock goes through. No inference involved.

  `hpio_right` was not tested only because its `top.py` reads
  `general_purpose_io_sites.txt`, which its own Makefile generates during the
  build; running `top.py` standalone skips that step. `hdio_top_right` and
  `hdio_bot_right` use the same mechanism and are enabled and working, so
  there is no reason to expect it to fail.

  **`rclk_pss_alto` is not optional.** `RCLK_INTF_LEFT_TERM_ALTO` is where
  `PL_CLK` enters the fabric -- our FASM's
  `PIP.CLK_BUFG_PS_0_CLK_IN.PS_TO_PL_CLK0` is in it -- and with no base
  address `fasm2bit` cannot place a single bit there.

  **This does not produce a silently dead bitstream** -- an earlier version of
  this section said it would, and that was wrong in the alarming direction.
  `tile_segbits.py` does `bits_map[block_type]`, which for a tile with
  `bits: {}` raises `KeyError`, and `fasm_assembler.py` turns every `KeyError`
  there into `FasmLookupError("Segment DB <type>, key <feature> not found")`.
  `fasm2bit` therefore refuses the whole file and writes no bitstream at all.

  The cost is the misdiagnosis, not the silence: it blames a missing **segbit**
  for what is really a missing **base address**, and those need opposite fixes
  -- a characterisation run versus a propagation rule. Chasing the first when
  you need the second is what this would actually have cost.

  The other three sub-fuzzers cost tile types this design does not use, but
  they are wrong for the database all the same.

  `env/add_missing_tilegrid_fuzzers.sh` repairs it after 002 finishes: it
  builds each `.tdb` on its own first and adds it to the dependency list only
  once it exists, because `tilegrid.json` depends on *every* listed `.tdb`, so
  adding one that cannot succeed means make never reaches the final target
  however it fails. That is the same trap the original removal was avoiding --
  the removal was right to worry and wrong about which ones qualify.

  **Settle it with one Vivado run, not 405.** The reference build
  (`env/reference_build.sh`) produces a bitstream for the same design;
  `bit2fasm.py --verbose` then reports unknown bits per tile. If Vivado sets
  bits in `RCLK_CLEM_CLKBUF_L` and `RCLK_RCLK_XIPHY_INNER_FT` at Y149, that is
  proof in a single run, and it shows which wire Vivado uses at
  `LEFT_TERM_ALTO` as well. Only if that says the bits are real is
  `060-rclk-seed` (~405 specimens, hours) needed to *solve* them -- and there
  may be a cheaper fix, since if Vivado reaches the leaf over a fully
  characterised path, nextpnr can be steered onto it by forbidding the
  unfuzzed pips, with no new characterisation at all.

| tile type | known | unknown | % |
| --- | ---: | ---: | ---: |
| CLEL_R | 86 | 0 | 100.0 |
| CLEM | 197 | 0 | 100.0 |
| HDIO_BOT_RIGHT | 5 | 0 | 100.0 |
| HDIO_TOP_RIGHT | 22 | 0 | 100.0 |
| INT | 648 | 0 | 100.0 |
| RCLK_DSP_INTF_L | 8 | 0 | 100.0 |
| RCLK_HDIO | 6 | 0 | 100.0 |
| RCLK_INT_L | 4 | 0 | 100.0 |
| RCLK_INTF_LEFT_TERM_ALTO | 1 | 1 | 50.0 |
| **TOTAL** | **977** | **1** | **99.9** |

plus 13 features in three tile types that have no segbits file at all
(`INT_INTF_R_PCIE4`, `RCLK_RCLK_XIPHY_INNER_FT`, `RCLK_CLEM_CLKBUF_L`).

**Read the direction of that test carefully.** It proves *emitted ⊆ known*. It
cannot prove *required ⊆ emitted* — a feature we fail to write is invisible to
it. It caught four real encoding faults today; it will not catch an omission.

### prjuray/tools/dump_features.tcl is the specification

That Tcl turns a Vivado-routed design into the feature list the fuzzers solve
against, so it **is** prjuray's FASM model. The segbits only record which of
those features were successfully solved. Three separate attempts to infer the
model from the segbits alone each produced a rule that the next example
falsified. Reading the Tcl settled every one of them in minutes.

### Four bugs in nextpnr-xilinx, all in `patches/`

1. **`findSourceSinkLocations` never terminated.** Its BFS parents each wire by
   whichever wire discovered it, which is a forest only if the root can never be
   re-parented — and nothing ever inserts the root into `backtrace`, so a
   bidirectional pip leading back to it closes a 2-cycle. Same shape in
   `routeVcc` and both `routeClock` BFS loops. UltraScale+ has such pips (this
   is the same device property prjuray spells `.FWD`/`.REV`); 7-series
   apparently does not, which is why this sat latent upstream.

   **Five earlier diagnoses of this were wrong, and every one was inferred from
   where the log stopped.** `Routing global clocks... routing clock '$iopadmap$clk'`
   was simply the last line printed before a silent function; `routeClock` had
   always completed. One `gdb` stack sample settled it. `ptrace_scope=1` forbids
   attaching to a running process, so **gdb has to be the parent**: launch under
   `gdb -batch -ex run --args ... &`, then `kill -INT` the gdb pid — commands
   placed after `run` execute at the stop.

2. **Chain-root CARRY8 sent its carry-in to CIN.** CIN is the dedicated input
   from the CARRY8 below, so only a cell with a predecessor may use it. The
   chain root sets `cluster = its own name`, which is not `ClusterId()`, so the
   original test took the chained path and asked the router to reach SLICE/CIN
   from the global GND node. A root's carry-in belongs on AX.

3. **`fasm.cc` UltraScale+ writers** — CLE, IO, clocking, route-throughs and
   the bidirectional-pip suffix. None of the 7-series writers could be reused,
   because every difference changes the feature *name*.

4. **`bbaexport.java` for RapidWright 2026** (six API fixes, four null guards).

### Two traps worth remembering

* **`getSiteLocInTile()` is not prjuray's site index.** `bbaexport` computes
  `rel_x`/`rel_y` per site *type*, and an HDIO tile interleaves `HDIOB_M` and
  `HDIOB_S`, so each type restarts at zero and the two collide: eight distinct
  pads first came out as `IOB_X0Y{0,2,4,6}`, every name used twice. prjuray
  counts over every site sharing a name *prefix*.
* **A route-thru pip carries no site in the chipdb** — `pip.site`, the wire's
  site and the bel-pin count are all -1/0 — and the wire number is not the site
  number (`BUFCE_LEAF_X0Y2` is `CLK_LEAF_SITES_3`). Hence the generated table
  `tools/gen_usp_bufce_leaf.py`.

## Open, in priority order

1. **No `part.yaml` or `tilegrid.json` for the XCK26**, so
   `prjuray/utils/fasm2bit.py` cannot run at all and there is still no `.bit`.
   prjuray-db ships part directories for two ZU3EG parts only. `001-part-yaml`
   is one Vivado run — `gen_part_base_yaml` off a per-frame-CRC bitstream.
   `002-tilegrid` has 20 sub-fuzzers and is the long pole. **This is
   characterisation, run once per die, not Vivado in the design loop.**

2. **`CARRY8.CI.CIN` is absent from prjuray-db.** `017-cle-precyinit` emits the
   tag — its `tag_groups.txt` lists `PRECYINIT_BOT` as a four-way group
   C0/C1/AX/CIN — but only `CI.{AX,V0,V1}` were solved. A chained CARRY8 would
   therefore assemble with both carry-in bits clear, which *is* `CI.V0`,
   constant zero: the chain is cut silently rather than failing. `build.sh`
   defaults to `-nocarry` for that reason and nextpnr warns once per chained
   CARRY8. Settling it needs one Vivado specimen on `xczu3eg-sfvc784-1-e`,
   whose `part.yaml` prjuray-db already has.

3. Genuine prjuray-db coverage gaps, listed above.

4. BRAM, DSP and the PLL/MMCM are not ported in `fasm.cc`. They are deliberately
   left unwritten rather than emitting 7-series features, so a design using them
   loses its configuration instead of getting a wrong one.

5. **The test that does not exist yet: required ⊆ emitted.** Build the same
   design in Vivado once, run prjuray's own `bit2fasm.py` on the result, and
   diff the *feature classes per tile type* against ours -- not bytes, since
   placement differs and LUT INIT is pin-permuted at write time. This is
   validation of the open flow, not Vivado in the design loop, and it is what
   prjxray's own tests do. One run settles five things at once: whether our
   INIT bit order is right (the checker only compares names), any feature kind
   Vivado writes that we never do, what Vivado ties PS8's 4,613 fabric inputs
   to, which distribution track the clock really takes through the three
   unfuzzed RCLK tile types, and -- building the CARRY=1 variant -- the
   encoding of `CARRY8.CI.CIN`, by reading bits 10_18 and 14_01 in a non-root
   CLEM. Before any of it, smoke-test the chain: `bit2fasm.py` on
   `001-part-yaml`'s own `design.bit`. If part.yaml + tilegrid + segbits cannot
   round-trip a Vivado bitstream on this die, nothing downstream is
   trustworthy.

6. `.bit.bin` packaging is done and verified byte-for-byte against bootgen
   (`tools/bit2binfile.py`), but **nothing has been loaded onto the board yet**.
   When it is: `fpgautil` does not touch clocks, so check
   `/sys/kernel/debug/clk/clk_summary` for `pl0` on the board first, or the
   counter will not run and the wrong layer gets debugged.
