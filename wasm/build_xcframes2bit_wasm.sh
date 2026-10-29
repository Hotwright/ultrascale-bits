#!/bin/bash
# Build prjuray's xcframes2bit (frames -> UltraScale+ .bit) as a WASI
# WebAssembly command, with the recipe and toolchain file of
# 0-xilinx-bits/wasm-build/build_xc7frames2bit_wasm.sh (prjuray-tools is
# prjxray's tools tree; read that script for the flags). One addition: the
# abseil prjuray vendors masks signals in thread_identity.cc, so this build
# needs <signal.h> (-D_WASI_EMULATED_SIGNAL, -lwasi-emulated-signal) and
# no-op sigfillset/pthread_sigmask (wasi_sigmask_shim.h, force-included),
# in a copy of the toolchain file.
#   wasm/build_xcframes2bit_wasm.sh   -> work/prjuray-tools-wasm/tools/xcframes2bit
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
DEPS="${WASM_DEPS:-/mnt/i/Hotwright/0-xilinx-bits/wasm-build}"
SRC="$REPO/prjuray/third_party/prjuray-tools"
BUILD="${WASM_BUILD:-$REPO/work/prjuray-tools-wasm}"
[ -f "$DEPS/Toolchain-WASI-prjxray.cmake" ] || { echo "no $DEPS/Toolchain-WASI-prjxray.cmake (run build_xc7frames2bit_wasm.sh configure there)" >&2; exit 1; }
mkdir -p "$BUILD"
TC="$BUILD/Toolchain-WASI-prjuray.cmake"
shim="$(printf '%s' "$HERE/wasi_sigmask_shim.h" | sed 's/[\/&]/\\&/g')"
sed -e "s/-DGLOB_TILDE=0\"/-DGLOB_TILDE=0 -D_WASI_EMULATED_SIGNAL -include $shim\"/" \
    -e 's/-lwasi-emulated-mman"/-lwasi-emulated-mman -lwasi-emulated-signal"/' \
    "$DEPS/Toolchain-WASI-prjxray.cmake" > "$TC"
grep -q EMULATED_SIGNAL "$TC" && grep -q emulated-signal "$TC" || { echo "toolchain edit failed" >&2; exit 1; }
cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_TOOLCHAIN_FILE="$TC" \
    -DCMAKE_BUILD_TYPE=Release -DPRJXRAY_BUILD_TESTING=OFF -DBUILD_TESTING=OFF \
    -DGFLAGS_BUILD_TESTING=OFF -DGFLAGS_BUILD_SHARED_LIBS=OFF \
    -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF
cmake --build "$BUILD" --target xcframes2bit -j"$(nproc)"
ls -l "$BUILD/tools/xcframes2bit"*
