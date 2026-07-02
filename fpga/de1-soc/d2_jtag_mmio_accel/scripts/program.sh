#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source /etc/profile.d/quartus.sh

sof="output_files/de1_d2_jtag_mmio_accel.sof"

if [[ ! -f "$sof" ]]; then
  echo "Missing $sof. Run ./scripts/build.sh first." >&2
  exit 1
fi

quartus_pgm -m JTAG -o "p;$sof@2"

