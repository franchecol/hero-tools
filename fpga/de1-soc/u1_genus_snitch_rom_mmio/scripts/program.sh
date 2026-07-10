#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s18_dir=$(cd -- "${script_dir}/.." && pwd)
sof="${s18_dir}/quartus/output_files/de1_s18_genus_snitch_rom_mmio.sof"

if [[ ! -f "${sof}" ]]; then
    "${script_dir}/build.sh"
fi

if [[ -f /etc/profile.d/quartus.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/quartus.sh
fi

quartus_pgm -m JTAG -o "p;${sof}@2"
