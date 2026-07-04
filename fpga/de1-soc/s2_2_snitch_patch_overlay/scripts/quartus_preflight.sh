#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

if [[ -f /etc/profile.d/quartus.sh ]]; then
    source /etc/profile.d/quartus.sh
fi

"${EXP_DIR}/scripts/export_patched_project.sh"

cd "${GENERATED_DIR}"
LOG="${GENERATED_DIR}/quartus_map_preflight.log"
REPORT="${GENERATED_DIR}/output_files/${PROJECT}.map.rpt"

set +e
quartus_map --analysis_and_elaboration "${PROJECT}" > "${LOG}" 2>&1
status=$?
set -e

if [[ "${status}" -eq 0 ]]; then
    echo "Quartus patched preflight passed"
    echo "Log: ${LOG}"
    exit 0
fi

echo "Quartus patched preflight failed with exit code ${status}"
echo "First Quartus errors:"
awk '
    /^[[:space:]]*Error / {
        print
        count += 1
        if (count == 16) {
            exit
        }
    }
' "${LOG}"
echo "Full log: ${LOG}"
if [[ -f "${REPORT}" ]]; then
    echo "Report: ${REPORT}"
fi
exit "${status}"

