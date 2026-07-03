#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source /etc/profile.d/quartus.sh

sof="output_files/de1_d3_hps_mmio_accel.sof"
if [[ ! -f "${sof}" ]]; then
  echo "Missing ${sof}; run ./scripts/build.sh first." >&2
  exit 1
fi

quartus_pgm -m JTAG -o "p;${sof}@2"
