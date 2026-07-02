#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

SIM_BIN="${SNITCH_TARGET}/bin/snitch_cluster.vlt"
ELF="${S1_DIR}/build/mmio.elf"
TRACE="${SNITCH_TARGET}/logs/trace_hart_00000.dasm"
MMIO_ADDR="${S1_MMIO_ADDR:-0x40000000}"
MMIO_VALUE="${S1_MMIO_VALUE:-0x0badcafe}"

if [[ ! -x "${SIM_BIN}" ]]; then
    echo "Missing simulator: ${SIM_BIN}" >&2
    echo "Run ./scripts/build_sim.sh first." >&2
    exit 1
fi

if [[ ! -f "${ELF}" ]]; then
    echo "Missing ELF: ${ELF}" >&2
    echo "Run ./scripts/build_sw_mmio.sh first." >&2
    exit 1
fi

cd "${SNITCH_TARGET}"
mkdir -p logs
rm -f "${TRACE}"
timeout "${S1_RUN_TIMEOUT:-30s}" "${SIM_BIN}" "${ELF}"

python3 "${S1_DIR}/scripts/check_mmio_trace.py" \
    "${TRACE}" \
    "${MMIO_ADDR}" \
    "${MMIO_VALUE}"

echo "S1 MMIO trace check passed"
