#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

mkdir -p "${GENERATED_DIR}"

"${S3_DIR}/scripts/run_sv2v_probe.sh"

cp "${S3_DIR}/quartus/${PROJECT}.qpf" "${GENERATED_DIR}/${PROJECT}.qpf"
sed "s|@S3_DIR@|${S3_DIR}|g" \
    "${S3_DIR}/quartus/base.qsf" \
    > "${GENERATED_DIR}/${PROJECT}.qsf"

echo "Generated ${GENERATED_DIR}/${PROJECT}.qpf"
echo "Generated ${GENERATED_DIR}/${PROJECT}.qsf"
echo "Quartus input: ${GENERATED_DIR}/snitch_core_probe.v"
