#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

if [[ -f /etc/profile.d/quartus.sh ]]; then
    source /etc/profile.d/quartus.sh
fi

"${S6_DIR}/scripts/export_quartus_project.sh"

cd "${GENERATED_DIR}"
LOG="${GENERATED_DIR}/quartus_compile.log"
SOF="${GENERATED_DIR}/output_files/${PROJECT}.sof"

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
