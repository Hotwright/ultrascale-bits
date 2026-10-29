#!/usr/bin/env bash
# Build ARM (A53) software for the KV260 with zig cc: no Vivado, Vitis or
# cross gcc. zig carries clang, lld and musl for aarch64.
#
#   sw/build.sh linux     <out> <src.c...>   static aarch64 Linux binary (run as root
#                                            on the board for /dev/mem)
#   sw/build.sh baremetal <out.elf> <src.c...>  program in OCM, MMU off; run it with
#                                            env/kv260_run_bm.sh (JTAG), or boot
#                                            <out>.bin from U-Boot (baremetal/README.md)
#
# zig: $ZIG if set, else `zig` on PATH, else `python3 -m ziglang`
# (pip install ziglang).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mode="${1:?usage: sw/build.sh linux|baremetal <out> <src.c...>}"
out="${2:?no output named}"
shift 2
[ $# -gt 0 ] || { echo "no sources" >&2; exit 1; }

if [ -n "${ZIG:-}" ]; then read -r -a zig <<<"$ZIG"
elif command -v zig >/dev/null; then zig=(zig)
elif python3 -c 'import ziglang' 2>/dev/null; then zig=(python3 -m ziglang)
else echo "no zig: pip install ziglang, or set ZIG" >&2; exit 1; fi

case "$mode" in
linux)
    "${zig[@]}" cc -target aarch64-linux-musl -O2 -static -s -o "$out" "$@"
    ;;
baremetal)
    lib="$here/baremetal/lib"
    # -mstrict-align: with the MMU off every access is Device memory, where
    # an unaligned access faults.
    "${zig[@]}" cc -target aarch64-freestanding-none -mcpu=cortex_a53 -O2 -g \
        -ffreestanding -fno-builtin -mstrict-align -nostdlib \
        -I"$lib" -T "$lib/link.ld" -Wl,--build-id=none \
        -o "$out" "$lib/start.S" "$lib/bm.c" "$@"
    "${zig[@]}" objcopy -O binary "$out" "${out%.elf}.bin"
    ;;
*) echo "unknown mode $mode" >&2; exit 1 ;;
esac
echo "built $out"
