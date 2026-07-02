#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

mkdir -p "${GENERATED_DIR}"

SV2V_LOG="${GENERATED_DIR}/sv2v_core_probe.log"
YOSYS_LOG="${GENERATED_DIR}/yosys_core_probe.log"
OUT_V="${GENERATED_DIR}/snitch_core_probe.v"
FILTERED_SNITCH="${GENERATED_DIR}/snitch_synthesis_probe.sv"

# The upstream core contains simulation-only debug regions guarded by
# "pragma translate_off/on". sv2v keeps those regions, and Yosys then parses
# tasks such as $bitstoshortreal that are irrelevant for synthesis. Keep
# upstream untouched and feed a filtered local copy to this probe.
awk '
    /pragma translate_off/ { skip = 1; next }
    /pragma translate_on/  { skip = 0; next }
    !skip { print }
' "${SNITCH_ROOT}/hw/snitch/src/snitch.sv" > "${FILTERED_SNITCH}"

SOURCES=(
    "${S3_DIR}/rtl/snitch_core_shims.sv"
    "${SNITCH_ROOT}/hw/snitch/src/snitch_pma_pkg.sv"
    "${SNITCH_ROOT}/hw/snitch/src/riscv_instr.sv"
    "${SNITCH_ROOT}/hw/snitch/src/snitch_pkg.sv"
    "${COMMON_CELLS_ROOT}/src/fifo_v3.sv"
    "${SNITCH_ROOT}/hw/snitch/src/snitch_regfile_ff.sv"
    "${SNITCH_ROOT}/hw/snitch/src/snitch_lsu.sv"
    "${SNITCH_ROOT}/hw/snitch/src/snitch_l0_tlb.sv"
    "${FILTERED_SNITCH}"
    "${S3_DIR}/rtl/de1_s3_snitch_core_probe.sv"
)

set +e
"${SV2V}" \
    -DVERILATOR \
    -DSYNTHESIS \
    -I"${COMMON_CELLS_ROOT}/include" \
    --write="${OUT_V}" \
    "${SOURCES[@]}" \
    > "${SV2V_LOG}" 2>&1
sv2v_status=$?
set -e

if [[ "${sv2v_status}" -ne 0 ]]; then
    echo "sv2v core-only probe failed with exit code ${sv2v_status}"
    echo "First sv2v messages:"
    sed -n '1,40p' "${SV2V_LOG}"
    echo "Full log: ${SV2V_LOG}"
    exit "${sv2v_status}"
fi

echo "sv2v core-only probe passed"
echo "Output: ${OUT_V}"
echo "Log: ${SV2V_LOG}"

set +e
"${YOSYS}" -q -p "read_verilog ${OUT_V}; hierarchy -top de1_s3_snitch_core_probe; proc; check" \
    > "${YOSYS_LOG}" 2>&1
yosys_status=$?
set -e

if [[ "${yosys_status}" -ne 0 ]]; then
    echo "yosys parse/check failed with exit code ${yosys_status}"
    echo "First yosys messages:"
    sed -n '1,80p' "${YOSYS_LOG}"
    echo "Full log: ${YOSYS_LOG}"
    exit "${yosys_status}"
fi

echo "yosys parse/check passed"
echo "Log: ${YOSYS_LOG}"
