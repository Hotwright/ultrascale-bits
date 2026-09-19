# Reproducing the upstream checkouts

`prjuray/` and `prjuray-db/` are not tracked here — they are upstream clones
with their own history. Recreate them exactly:

    git clone https://github.com/f4pga/prjuray.git    && git -C prjuray    checkout c550b03
    git clone https://github.com/f4pga/prjuray-db.git && git -C prjuray-db checkout affbc5e
    git clone --depth 1 https://github.com/gatecat/nextpnr-xilinx.git

`nextpnr-xilinx` is the older standalone fork, not the himbaechel nextpnr in
`eda-tools/`. It is the only backend with UltraScale+ support. Note that its
UltraScale+ path generates bitstreams via RapidWright + Vivado; the
FASM/Project X-Ray route is 7-series only. See SCOPE-K26.md.

`prjuray-tools` does not build on GCC 13 — 50 files relied on `<cstdint>`
arriving transitively. Apply the fixes before building:

    git -C prjuray/third_party/prjuray-tools submodule update --init --recursive
    git -C prjuray/third_party/prjuray-tools apply \
        ../../../patches/prjuray-tools-cstdint.patch
    git -C prjuray/third_party/prjuray-tools/third_party/abseil-cpp apply \
        ../../../../../patches/abseil-cstdint.patch

Then `mk_uray_overlay.sh` builds the writable overlay, and `env/uray_env.sh`
sets the environment (it bypasses prjuray's exact-`v2019.2` Vivado gate).
