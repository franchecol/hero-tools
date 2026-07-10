#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s17_dir=$(cd -- "${script_dir}/.." && pwd)
sof="${s17_dir}/quartus/output_files/de1_s17_genus_snitch_core.sof"

if [[ ! -f "${sof}" ]]; then
    "${script_dir}/build_quartus.sh"
fi

if [[ -f /etc/profile.d/quartus.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/quartus.sh
fi

quartus_pgm -m JTAG -o "p;${sof}@2"
