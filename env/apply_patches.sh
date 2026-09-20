#!/usr/bin/env bash
# Apply the patches in patches/ to the gitignored clones (prjuray, prjuray-tools,
# abseil, nextpnr-xilinx), so a fresh checkout can be rebuilt from this repo alone.
#
# An earlier version of this script searched for the right (root, strip) by trying
# candidates until `git apply --check` succeeded. That is UNSAFE and it did in fact
# misfire: `git apply --check` SUCCEEDS on a wrong root whenever the patch's paths
# do not exist there, because creating new files is a legal patch. It duly decided
# that abseil-cstdint.patch and prjuray-tools-cstdint.patch belonged in
# prjuray/third_party/VexRiscv, which shares no file with either.
#
# So: no searching. The table below is explicit, and every patch is required to
# modify files that ALREADY EXIST at its root. That single precondition is what
# rules out the whole class of "applied somewhere plausible-looking".
#
# The patches are not uniform in style, so neither tool alone is enough and the
# table names the one to use:
#   patch(1) - for `diff -u` patches whose --- line is an absolute path into a
#              scratch directory. GNU patch prefers whichever of the two names
#              exists (it prints "Ignoring potentially dangerous file name" and
#              uses the +++ side, which is the behaviour we want); git apply just
#              fails on them.
#   git      - for prjuray-tools-cstdint.patch, which carries a SUBMODULE pointer
#              hunk for third_party/abseil-cpp. patch(1) refuses that with
#              "not a regular file" and then reports the whole patch as failed,
#              even though all 53 file hunks are fine. git understands it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT=$PWD

# patch-file : root directory (relative to repo root) : strip level : tool
TABLE=(
  "abseil-cstdint.patch                  : prjuray/third_party/prjuray-tools/third_party/abseil-cpp : 1 : patch"
  "prjuray-tools-cstdint.patch           : prjuray/third_party/prjuray-tools                        : 1 : git"
  "prjuray-pyyaml6.patch                 : prjuray                                                  : 0 : patch"
  "prjuray-002-tilegrid-xck26.patch      : .                                                        : 0 : patch"
  "prjuray-002-hpio-tile-type.patch      : .                                                        : 0 : patch"
  "prjuray-fasm-assembler-diagnostics.patch : .                                                     : 0 : patch"
  "prjuray-002-add-tdb-tolerate-unsolved.patch : .                                                  : 0 : patch"
  "prjuray-002-rclk-dsp-clkbuf-hang.patch : .                                                       : 0 : patch"
  "nextpnr-xilinx-usp-backtrace-cycle.patch : nextpnr-xilinx                                        : 0 : patch"
  "nextpnr-xilinx-usp-carry8-chain-root.patch : nextpnr-xilinx                                      : 0 : patch"
  "nextpnr-xilinx-usp-fasm.patch         : .                                                        : 0 : patch"
  "bbaexport-rapidwright-2026.patch      : .                                                        : 0 : patch"
)

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

# --self-test: the regression test for the bug that motivated this rewrite.
# VexRiscv shares no file with abseil or prjuray-tools, yet `git apply --check`
# accepts both patches there, because a patch may legally create files. The
# existence precondition must reject it. If this ever stops failing, the guard
# is gone.
if [ "${1:-}" = "--self-test" ]; then
  bad=$ROOT/prjuray/third_party/VexRiscv
  [ -d "$bad" ] || { echo "self-test: $bad not checked out"; exit 0; }
  rc=0
  for pf in abseil-cstdint.patch prjuray-tools-cstdint.patch; do
    pp=$ROOT/patches/$pf
    if git -C "$bad" apply --check -p1 "$pp" 2>/dev/null; then
      gitsays="ACCEPTS (this is the bug)"; else gitsays="rejects"; fi
    miss=0
    while read -r t; do
      [ -z "$t" ] || [ "$t" = dev/null ] && continue
      [ -e "$bad/$t" ] || miss=$((miss+1))
    done < <(sed -n 's/^+++ //p' "$pp" | sed 's/\t.*//' | cut -d/ -f2-)
    if [ "$miss" -gt 0 ]; then verdict="REJECTED ($miss targets absent)"; else verdict="ACCEPTED - GUARD BROKEN"; rc=1; fi
    printf '  %-32s git apply --check: %-24s our guard: %s\n' "$pf" "$gitsays" "$verdict"
  done
  echo; [ $rc = 0 ] && echo "  self-test PASSED" || echo "  self-test FAILED"
  exit $rc
fi
fail=0; applied=0; already=0

# The +++ paths a patch writes, with `strip` leading components removed.
targets() { sed -n 's/^+++ //p' "$1" | sed 's/\t.*//' | cut -d/ -f$(( $2 + 1 ))-; }

for row in "${TABLE[@]}"; do
  IFS=: read -r pf dir strip tool <<<"$row"
  pf=$(echo "$pf" | xargs); dir=$(echo "$dir" | xargs)
  strip=$(echo "$strip" | xargs); tool=$(echo "$tool" | xargs)
  patch_path=$ROOT/patches/$pf
  [ -f "$patch_path" ] || { printf '  MISSING  %-45s no such patch file\n' "$pf"; fail=1; continue; }
  [ -d "$ROOT/$dir" ] || { printf '  skip     %-45s %s not checked out\n' "$pf" "$dir"; continue; }

  # Precondition: this patch only MODIFIES, so every target must already be there.
  # /dev/null is how a patch spells "delete"; nothing here does that, but allow it.
  missing=""
  while read -r t; do
    [ -z "$t" ] && continue
    [ "$t" = "dev/null" ] && continue
    [ -e "$ROOT/$dir/$t" ] || missing="$missing $t"
  done < <(targets "$patch_path" "$strip")
  if [ -n "$missing" ]; then
    printf '  WRONG    %-45s %s lacks:%s\n' "$pf" "$dir" "$(echo $missing | cut -c1-70)"
    fail=1; continue
  fi

  if [ "$tool" = git ]; then
    reverse() { git -C "$ROOT/$dir" apply -R --check -p"$strip" "$patch_path"; }
    forward() { git -C "$ROOT/$dir" apply --check -p"$strip" "$patch_path"; }
    doit()    { git -C "$ROOT/$dir" apply       -p"$strip" "$patch_path"; }
  else
    reverse() { patch -d "$ROOT/$dir" -p"$strip" -R --dry-run --force --silent < "$patch_path"; }
    forward() { patch -d "$ROOT/$dir" -p"$strip" --forward --dry-run --silent < "$patch_path"; }
    doit()    { patch -d "$ROOT/$dir" -p"$strip" --forward --silent < "$patch_path"; }
  fi

  if reverse 2>/dev/null; then
    printf '  already  %-45s %s\n' "$pf" "$dir"; already=$((already+1)); continue
  fi
  if ! forward 2>/dev/null; then
    printf '  FAIL     %-45s does not apply cleanly in %s (-p%s, %s)\n' "$pf" "$dir" "$strip" "$tool"
    fail=1; continue
  fi
  if [ "$DRY" = 1 ]; then
    printf '  would    %-45s %s (-p%s)\n' "$pf" "$dir" "$strip"; applied=$((applied+1))
  else
    doit
    printf '  applied  %-45s %s (-p%s)\n' "$pf" "$dir" "$strip"; applied=$((applied+1))
  fi
done

# Two of fasm.cc's tables are #included from generated .inc files, and
# nextpnr-xilinx/ is gitignored, so on a fresh clone the patch lands on a tree
# where those files do not exist and the build fails at the #include. Generate
# them here rather than leaving it to a README step nobody reads. Both read
# prjuray-db and write into nextpnr-xilinx/xilinx/; neither writes to the
# read-only database.
if [ "$DRY" != 1 ] && [ $fail = 0 ] && [ -d "$ROOT/nextpnr-xilinx/xilinx" ]; then
  echo
  for gen in gen_usp_bufce_leaf gen_usp_hdio_optff; do
    if python3 "$ROOT/tools/$gen.py" >/dev/null 2>&1; then
      printf '  generated %s\n' "$gen.py"
    else
      printf '  FAILED    %s -- fasm.cc will not compile without its .inc\n' "$gen.py"
      fail=1
    fi
  done
fi

echo
echo "  $applied to apply, $already already applied, $([ $fail = 0 ] && echo 'no failures' || echo 'FAILURES - see above')"
exit $fail
