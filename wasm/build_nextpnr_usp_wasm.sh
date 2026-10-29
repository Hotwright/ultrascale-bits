#!/bin/bash
# Build nextpnr-himbaechel (xilinx uarch, usp-himbaechel branch) as a WASI
# WebAssembly command that places and routes for the K26 (xck26).
#
# The recipe and its prebuilt dependencies (wasi-sdk 34, Boost 1.81 for
# wasm32, Eigen, the host bba tool, the exception stubs, the WASI toolchain
# file) are 0-xilinx-bits/wasm-build's; see build_nextpnr_xilinx_wasm.sh
# there for why each choice is what it is. Only the source tree, the build
# directory and the chipdbs differ:
#   - the source is eda-tools/nextpnr on usp-himbaechel;
#   - xc7z010 is the only chipdb CMake builds (a Series-7 check);
#   - chipdb-xck26.bin is not built by CMake at all: it comes from the
#     RapidWright dump (gen/rapidwright/run_usp_dump.sh) and is copied into
#     the share directory, which the .wasm reads at run time as /share.
#
#   wasm/build_nextpnr_usp_wasm.sh            -> work/nextpnr-wasm/
#   wasm/run_nextpnr_wasm.sh <nextpnr args>   runs it under node (WASI)
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
NEXTPNR_SRC="${NEXTPNR_SRC:-/mnt/i/Hotwright/eda-tools/nextpnr}"
DEPS="${WASM_DEPS:-/mnt/i/Hotwright/0-xilinx-bits/wasm-build}"
BUILD="${WASM_BUILD:-$REPO/work/nextpnr-wasm}"
XCK26_DB="${XCK26_DB:-$REPO/work/usp-himbaechel-db/chipdb-xck26.bin}"

for f in "$DEPS/Toolchain-WASI.cmake" "$DEPS/wasi_throw_stubs.o" "$DEPS/boost-1.81.0/stage/lib/libboost_system.a" \
         "$DEPS/eigen-prefix/share/eigen3/cmake" "$DEPS/nextpnr-bba-build/bba-export.cmake" "$XCK26_DB"; do
    [ -e "$f" ] || { echo "missing $f (build the deps with 0-xilinx-bits/wasm-build/build_nextpnr_xilinx_wasm.sh)" >&2; exit 1; }
done

cmake -B "$BUILD" -S "$NEXTPNR_SRC" \
    -DCMAKE_TOOLCHAIN_FILE="$DEPS/Toolchain-WASI.cmake" \
    -DCMAKE_PREFIX_PATH="$DEPS/boost-1.81.0/stage/" \
    -DBOOST_ROOT="$DEPS/boost-1.81.0" \
    -DEigen3_DIR="$DEPS/eigen-prefix/share/eigen3/cmake" \
    -DBBA_IMPORT="$DEPS/nextpnr-bba-build/bba-export.cmake" \
    -DCMAKE_DISABLE_FIND_PACKAGE_Threads=ON \
    -DSTATIC_BUILD=ON -DBUILD_GUI=OFF -DBUILD_PYTHON=OFF -DBUILD_TESTS=OFF \
    -DEXTERNAL_CHIPDB=ON -DEXTERNAL_CHIPDB_ROOT=/share \
    -DARCH=himbaechel -DHIMBAECHEL_SPLIT=ON -DHIMBAECHEL_UARCH=xilinx \
    -DHIMBAECHEL_PRJXRAY_DB=/mnt/i/Hotwright/0-xilinx-bits/xray-db-local \
    -DHIMBAECHEL_XILINX_DEVICES="${DEVICES:-xc7z010}"
cmake --build "$BUILD" -j"$(nproc)"
mkdir -p "$BUILD/share/himbaechel/xilinx"
cp -f "$XCK26_DB" "$BUILD/share/himbaechel/xilinx/chipdb-xck26.bin"
ls -l "$BUILD"/nextpnr-himbaechel*.wasm "$BUILD/share/himbaechel/xilinx/"
