#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

if [[ -f /etc/profile.d/quartus.sh ]]; then
    source /etc/profile.d/quartus.sh
fi

"${S8_DIR}/scripts/run_sv2v_probe.sh"

cd "${S8_DIR}"
qsys-script \
    --search-path="${S8_DIR}/ip/s8_snitch_ctrl,$" \
    --script=scripts/create_qsys.tcl

qsys-generate "${QSYS_SYSTEM}.qsys" \
    --synthesis=VERILOG \
    --search-path="${S8_DIR}/ip/s8_snitch_ctrl,$" \
    --family="Cyclone V" \
    --part=5CSEMA5F31C6

LOG="${S8_DIR}/generated/quartus_map_preflight.log"
REPORT="${S8_DIR}/output_files/${PROJECT}.map.rpt"
mkdir -p "${GENERATED_DIR}"

set +e
quartus_map --analysis_and_elaboration "${PROJECT}" > "${LOG}" 2>&1
map_status=$?
set -e

if [[ "${map_status}" -eq 0 ]]; then
    echo "Quartus preflight passed"
    echo "Log: ${LOG}"
    if [[ -f "${REPORT}" ]]; then
        echo "Report: ${REPORT}"
    fi
    exit 0
fi

echo "Quartus preflight failed with exit code ${map_status}"
echo "First Quartus errors:"
awk '
    /^[[:space:]]*Error / {
        print
        count += 1
        if (count == 12) {
            exit
        }
    }
' "${LOG}"
echo "Full log: ${LOG}"
if [[ -f "${REPORT}" ]]; then
    echo "Report: ${REPORT}"
fi
exit "${map_status}"
