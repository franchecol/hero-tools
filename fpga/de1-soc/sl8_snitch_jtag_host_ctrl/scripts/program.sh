#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

if [[ -f /etc/profile.d/quartus.sh ]]; then
    source /etc/profile.d/quartus.sh
fi

SOF="${S8_DIR}/output_files/${PROJECT}.sof"

if [[ ! -f "${SOF}" ]]; then
    echo "Missing ${SOF}. Run ./scripts/build.sh first." >&2
    exit 1
fi

quartus_pgm -m JTAG -o "p;${SOF}@2"
