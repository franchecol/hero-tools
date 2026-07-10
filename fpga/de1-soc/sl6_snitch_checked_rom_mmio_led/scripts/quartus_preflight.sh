#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

if [[ -f /etc/profile.d/quartus.sh ]]; then
    source /etc/profile.d/quartus.sh
fi

"${S6_DIR}/scripts/export_quartus_project.sh"

cd "${GENERATED_DIR}"
LOG="${GENERATED_DIR}/quartus_map_preflight.log"
REPORT="${GENERATED_DIR}/output_files/${PROJECT}.map.rpt"

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
