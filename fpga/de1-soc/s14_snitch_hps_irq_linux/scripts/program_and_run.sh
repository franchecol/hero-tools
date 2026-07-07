#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S14_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
DE1_DIR=$(cd -- "${S14_DIR}/.." && pwd)
S13_DIR="${DE1_DIR}/s13_snitch_hps_irq_done"

if [[ "${BOARD_KERNEL:-console}" == "lxde" && -z "${PREPARE_LXDE_HEADLESS:-}" ]]; then
  export PREPARE_LXDE_HEADLESS=1
fi

"${S13_DIR}/scripts/program.sh"
"${SCRIPT_DIR}/send_and_run.sh"
