#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

mkdir -p "${GENERATED_DIR}"

"${S5_DIR}/scripts/run_sv2v_probe.sh"

cp "${S5_DIR}/quartus/${PROJECT}.qpf" "${GENERATED_DIR}/${PROJECT}.qpf"
sed "s|@S5_DIR@|${S5_DIR}|g" \
    "${S5_DIR}/quartus/base.qsf" \
    > "${GENERATED_DIR}/${PROJECT}.qsf"

echo "Generated ${GENERATED_DIR}/${PROJECT}.qpf"
echo "Generated ${GENERATED_DIR}/${PROJECT}.qsf"
echo "Quartus input: ${GENERATED_DIR}/snitch_generated_rom_mmio_led.v"
