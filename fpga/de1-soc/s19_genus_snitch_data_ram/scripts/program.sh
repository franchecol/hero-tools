#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s19_dir=$(cd -- "${script_dir}/.." && pwd)
sof="${s19_dir}/quartus/output_files/de1_s19_genus_snitch_data_ram.sof"

if [[ -f /etc/profile.d/quartus.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/quartus.sh
fi

if [[ ! -f "${sof}" ]]; then
    echo "Missing ${sof}. Run scripts/build.sh first." >&2
    exit 1
fi

quartus_pgm -m JTAG -o "p;${sof}@2"
