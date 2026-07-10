#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f /etc/profile.d/quartus.sh ]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/quartus.sh
fi

sof="output_files/de1_s16_gatelevel_import.sof"

if [ ! -f "$sof" ]; then
    ./scripts/build.sh
fi

quartus_pgm -m JTAG -o "p;${sof}@2"
