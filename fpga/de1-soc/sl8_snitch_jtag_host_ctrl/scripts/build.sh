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

LOG="${S8_DIR}/generated/quartus_compile.log"
SOF="${S8_DIR}/output_files/${PROJECT}.sof"
mkdir -p "${GENERATED_DIR}"

set +e
quartus_sh --flow compile "${PROJECT}" > "${LOG}" 2>&1
compile_status=$?
set -e

if [[ "${compile_status}" -eq 0 ]]; then
    echo "Quartus full compile passed"
    echo "Log: ${LOG}"
    if [[ -f "${SOF}" ]]; then
        echo "SOF: ${SOF}"
    fi
    exit 0
fi

echo "Quartus full compile failed with exit code ${compile_status}"
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
exit "${compile_status}"
