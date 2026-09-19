#!/bin/bash
# Build a writable overlay of prjuray-db at prjuray/database.
#
# prjuray hardcodes URAY_DATABASE_DIR to ${URAY_DIR}/database, and its fuzzers
# write there. prjuray-db is the REFERENCE we validate against and must stay
# pristine, exactly as prjxray-db does on the 7-series side - where a missing
# stale-symlink guard once turned 325 reference files into symlinks before it
# was caught. The guards below are that lesson, applied before the fact.
#
# Layout: database/<family>/ is a real directory whose entries symlink into
# prjuray-db, so reading works and any write lands on the overlay side. Files a
# fuzzer must replace are unlinked first by the push step, never written
# through.
set -e

HERE="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REF="${HERE}/prjuray-db"
OVL="${HERE}/prjuray/database"
FAMILIES="zynqusp"

[ -d "$REF" ] || { echo "mk_uray_overlay.sh: no reference at $REF" >&2; exit 1; }

for fam in $FAMILIES; do
    # Clear a stale symlink FIRST. "mkdir -p" on a symlink-to-directory succeeds
    # silently, and every ln/cp below would then resolve through it and rewrite
    # the read-only reference in place. This is the exact guard whose absence
    # damaged prjxray-db.
    [ -L "${OVL}/${fam}" ] && rm -f "${OVL}/${fam}"
    mkdir -p "${OVL}/${fam}"
    for src in "${REF}/${fam}"/*; do
        [ -e "$src" ] || continue
        name="$( basename "$src" )"
        dst="${OVL}/${fam}/${name}"
        [ -e "$dst" ] || [ -L "$dst" ] && rm -rf "$dst"
        ln -s "$src" "$dst"
    done
    echo "  ${fam}: $( ls -1 "${OVL}/${fam}" | wc -l ) entries linked"
done

# Standing assertions, same as the 7-series overlay carries.
for fam in $FAMILIES; do
    real="$( readlink -f "${OVL}/${fam}" )"
    case "$real" in
        "$REF"/*) echo "mk_uray_overlay.sh: REFUSING - ${OVL}/${fam} resolves into the reference" >&2; exit 1 ;;
    esac
done
if [ -n "$( git -C "$REF" status --porcelain 2>/dev/null )" ]; then
    echo "mk_uray_overlay.sh: ERROR - prjuray-db is no longer clean" >&2
    git -C "$REF" status --porcelain >&2
    exit 1
fi
echo "  prjuray-db clean: ok"
