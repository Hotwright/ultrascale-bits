#!/bin/bash
# Bring up a prjuray environment against the Vivado actually installed here.
#
# prjuray's own utils/environment.sh refuses to run on anything but Vivado
# v2019.2:
#
#     if [ $(${URAY_VIVADO} -h |grep Vivado |cut -d\  -f 2) != "v2019.2" ] ; then
#         echo "Requires Vivado 2019.2 to have Zynq US+ support."
#         export URAY_DIR="/bad/vivado/version"
#         return
#     fi
#
# Note what it does on failure: rather than erroring, it poisons URAY_DIR and
# returns, so every later path silently points at /bad/vivado/version. That is
# a deliberate booby-trap for a sourced script, and it means a wrong-version run
# fails in confusing ways far from the cause.
#
# The stated reason - "to have Zynq US+ support" - is a 2020 statement about the
# FLOOR, not the ceiling. Vivado 2026.1.1 has Zynq US+ support; 2019.2 was
# simply the version that first did and the one the authors pinned.
#
# That does NOT make running on 2026.1.1 safe, and the 7-series side of this
# tree is the cautionary tale: prjxray pins 2017.2, and on a modern Vivado its
# `cfg` sub-fuzzer silently solves nothing because the DRC it depends on now
# rejects the design. Seven years of drift between prjuray's pin and what is
# installed here is more, not less, than that. Treat every fuzzer result as
# suspect until cross-checked against the shipped ZU3EG database.
#
# usage: source env/uray_env.sh <config>      e.g. zynq_usp_5ev
set -u

URAY_ENV_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export URAY_ROOT="$( dirname "$URAY_ENV_DIR" )"
export URAY_DIR="${URAY_ROOT}/prjuray"

URAY_CONFIG="${1:-zynq_usp_5ev}"
URAY_SETTINGS="${URAY_DIR}/settings/${URAY_CONFIG}.sh"
if [ ! -f "$URAY_SETTINGS" ]; then
    echo "uray_env.sh: no such config '${URAY_CONFIG}'" >&2
    echo "  available: $( cd "${URAY_DIR}/settings" && ls *.sh | sed 's/\.sh$//' | tr '\n' ' ' )" >&2
    return 1 2>/dev/null || exit 1
fi

# Take the settings' own exports WITHOUT sourcing the file, so prjuray's
# environment.sh - and its version gate - never runs.
eval "$( grep '^export URAY_' "$URAY_SETTINGS" )"

# Everything environment.sh would have set, set here against this checkout.
export URAY_UTILS_DIR="${URAY_DIR}/utils"
export URAY_DATABASE_DIR="${URAY_DIR}/database"
export URAY_TOOLS_DIR="${URAY_DIR}/third_party/prjuray-tools/build/tools"
export URAY_FUZZERS_DIR="${URAY_DIR}/fuzzers"
export URAY_FAMILY_DIR="${URAY_DATABASE_DIR}/${URAY_DATABASE}"
export URAY_TCL_REFORMAT="${URAY_UTILS_DIR}/tcl-reformat.sh"
export URAY_CORRELATE="${URAY_TOOLS_DIR}/correlate_segdata"
export URAY_SEGMATCH="${URAY_TOOLS_DIR}/segmatch"
# Everything below is copied verbatim from prjuray/utils/environment.sh, which
# this file exists to bypass (it hard-gates on Vivado v2019.2 and otherwise
# silently sets URAY_DIR=/bad/vivado/version). Copying means it can drift, and
# it did: URAY_BITREAD was defined bare here, so 002-tilegrid ran
#   bitread -F ... -o design.bits -z -y design.bit
# with no part file and died on "Part file not found or invalid" after a full
# Vivado run. Upstream passes the part file and the architecture. Keep this list
# in step -- `comm -23` of the two files' `^export` names shows any drift.
export URAY_PART_YAML="${URAY_DATABASE_DIR}/${URAY_DATABASE}/${URAY_PART}/part.yaml"
export URAY_BITREAD="${URAY_TOOLS_DIR}/bitread -E --part_file ${URAY_PART_YAML} --architecture ${URAY_ARCH}"
export URAY_DBFIXUP="python3 ${URAY_UTILS_DIR}/dbfixup.py"
export URAY_MASKMERGE="bash ${URAY_UTILS_DIR}/maskmerge.sh"
export URAY_SEGPRINT="python3 ${URAY_UTILS_DIR}/segprint.py"
export URAY_BITTOOL="${URAY_TOOLS_DIR}/bittool"
export URAY_BLOCKWIDTH="python3 ${URAY_UTILS_DIR}/blockwidth.py"
export URAY_PARSEDB="python3 ${URAY_UTILS_DIR}/parsedb.py"
export URAY_MERGEDB="${URAY_UTILS_DIR}/mergedb.sh"
export URAY_GENHEADER="${URAY_UTILS_DIR}/genheader.sh"

# Reuse the 7-series tree's Vivado launcher: same install, and it already
# handles the Windows-drive-but-Linux-build detail. That tree is a sibling
# checkout, found by name next to this one (xilinx-bits, or 0-xilinx-bits);
# XILINX_BITS_DIR overrides the search, URAY_VIVADO overrides the launcher.
if [ -z "${XILINX_BITS_DIR:-}" ]; then
    for d in "$( dirname "$URAY_ROOT" )"/xilinx-bits "$( dirname "$URAY_ROOT" )"/0-xilinx-bits; do
        [ -d "$d" ] && { XILINX_BITS_DIR="$d"; break; }
    done
fi
if [ -z "${URAY_VIVADO:-}" ]; then
    if [ -n "${XILINX_BITS_DIR:-}" ] && [ -x "${XILINX_BITS_DIR}/rw-fuzzers/env/vivado.sh" ]; then
        URAY_VIVADO="${XILINX_BITS_DIR}/rw-fuzzers/env/vivado.sh"
    else
        URAY_VIVADO="$( command -v vivado || true )"
    fi
fi
if [ -z "$URAY_VIVADO" ]; then
    echo "uray_env.sh: no Vivado - set URAY_VIVADO, or check out xilinx-bits next to this repo" >&2
    return 1 2>/dev/null || exit 1
fi
export URAY_VIVADO
export URAY_VIVADO_SETTINGS="${URAY_VIVADO_SETTINGS:-}"

if [ -e "${URAY_DIR}/env/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "${URAY_DIR}/env/bin/activate"
fi
export PYTHONPATH="${URAY_DIR}:${PYTHONPATH:-}"

cat >&2 <<EOF
uray_env: config=${URAY_CONFIG} part=${URAY_PART} family=${URAY_DATABASE}
uray_env: database=${URAY_FAMILY_DIR}
uray_env: vivado=$( "${URAY_VIVADO}" -h 2>/dev/null | grep -m1 Vivado || echo '(not queried)' )
uray_env: NOTE prjuray pins v2019.2; its gate is bypassed here. Cross-check
uray_env:      results against the shipped ZU3EG database before trusting them.
EOF
