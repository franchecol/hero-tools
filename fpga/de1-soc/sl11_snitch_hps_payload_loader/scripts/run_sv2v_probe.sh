#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

"${S11_DIR}/scripts/build_payload.sh"

SV2V_LOG="${GENERATED_DIR}/sv2v_s11.log"
YOSYS_LOG="${GENERATED_DIR}/yosys_s11.log"
OUT_V="${GENERATED_DIR}/snitch_host_payload_core.v"
FILTERED_SNITCH="${GENERATED_DIR}/snitch_synthesis_probe.sv"

awk '
    /pragma translate_off/ { skip = 1; next }
    /pragma translate_on/  { skip = 0; next }
    !skip { print }
' "${SNITCH_ROOT}/hw/snitch/src/snitch.sv" > "${FILTERED_SNITCH}"

SOURCES=(
    "${REPO_ROOT}/fpga/de1-soc/sl3_snitch_core_only_probe/rtl/snitch_core_shims.sv"
    "${SNITCH_ROOT}/hw/snitch/src/snitch_pma_pkg.sv"
    "${SNITCH_ROOT}/hw/snitch/src/riscv_instr.sv"
    "${SNITCH_ROOT}/hw/snitch/src/snitch_pkg.sv"
    "${COMMON_CELLS_ROOT}/src/fifo_v3.sv"
    "${SNITCH_ROOT}/hw/snitch/src/snitch_regfile_ff.sv"
    "${SNITCH_ROOT}/hw/snitch/src/snitch_lsu.sv"
    "${SNITCH_ROOT}/hw/snitch/src/snitch_l0_tlb.sv"
    "${FILTERED_SNITCH}"
    "${S11_DIR}/rtl/s11_snitch_host_payload_core.sv"
)

set +e
"${SV2V}" \
    -DVERILATOR \
    -DSYNTHESIS \
    -I"${COMMON_CELLS_ROOT}/include" \
    -I"${GENERATED_DIR}" \
    --write="${OUT_V}" \
    "${SOURCES[@]}" \
    > "${SV2V_LOG}" 2>&1
sv2v_status=$?
set -e

if [[ "${sv2v_status}" -ne 0 ]]; then
    echo "sv2v SL11 failed with exit code ${sv2v_status}"
    echo "First sv2v messages:"
    sed -n '1,40p' "${SV2V_LOG}"
    echo "Full log: ${SV2V_LOG}"
    exit "${sv2v_status}"
fi

echo "sv2v SL11 passed"
echo "Output: ${OUT_V}"
echo "Log: ${SV2V_LOG}"

set +e
"${YOSYS}" -q -p "read_verilog ${OUT_V}; hierarchy -top s11_snitch_host_payload_core; proc; check" \
    > "${YOSYS_LOG}" 2>&1
yosys_status=$?
set -e

if [[ "${yosys_status}" -ne 0 ]]; then
    echo "yosys SL11 failed with exit code ${yosys_status}"
    echo "First yosys messages:"
    sed -n '1,80p' "${YOSYS_LOG}"
    echo "Full log: ${YOSYS_LOG}"
    exit "${yosys_status}"
fi

echo "yosys SL11 passed"
echo "Log: ${YOSYS_LOG}"
