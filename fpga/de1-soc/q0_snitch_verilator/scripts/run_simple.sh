#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

SIM_BIN="${SNITCH_TARGET}/bin/snitch_cluster.vlt"
ELF="${SNITCH_TARGET}/sw/tests/build/simple.elf"

if [[ ! -x "${SIM_BIN}" ]]; then
    echo "Missing simulator: ${SIM_BIN}" >&2
    echo "Run ./scripts/build_sim.sh first." >&2
    exit 1
fi

if [[ ! -f "${ELF}" ]]; then
    echo "Missing ELF: ${ELF}" >&2
    echo "Run ./scripts/build_sw_simple.sh first." >&2
    exit 1
fi

cd "${SNITCH_TARGET}"
mkdir -p logs
"${SIM_BIN}" "${ELF}"

