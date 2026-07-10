#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source /etc/profile.d/quartus.sh

project=de1_s10_snitch_hps_data_input
sof="output_files/${project}.sof"

if [[ ! -f "${sof}" ]]; then
  echo "Missing ${sof}; run ./scripts/build.sh first" >&2
  exit 1
fi

quartus_pgm -m JTAG -o "p;${sof}@2"
