#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S13_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
DE1_DIR=$(cd -- "${S13_DIR}/.." && pwd)

cd "${S13_DIR}"
source /etc/profile.d/quartus.sh

project=de1_s13_snitch_hps_irq_done
sof="output_files/${project}.sof"

if [[ ! -f "${sof}" ]]; then
  echo "Missing ${sof}; run ./scripts/build.sh first" >&2
  exit 1
fi

if [[ "${PREPARE_LXDE_HEADLESS:-0}" == "1" ]]; then
  "${DE1_DIR}/scripts/prepare_lxde_headless.sh"
fi

quartus_pgm -m JTAG -o "p;${sof}@2"
