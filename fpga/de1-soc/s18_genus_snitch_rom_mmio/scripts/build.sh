#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s18_dir=$(cd -- "${script_dir}/.." && pwd)
s17_dir=$(cd -- "${s18_dir}/../s17_genus_snitch_core" && pwd)
source_netlist="${s17_dir}/build/snitch_core_generic_netlist.v"
quartus_netlist="${s17_dir}/build/snitch_core_generic_quartus.v"
expected=2fc7264bb63ffdcd86ba1bf275c2e55de44bda7d6058a732d0c897bff69cf37c

"${script_dir}/build_sw.sh"

if [[ ! -f "${source_netlist}" ]]; then
    echo "Missing S17 Genus netlist. Run S17 fetch_generic_netlist.sh first." >&2
    exit 1
fi

actual=$(sha256sum "${source_netlist}" | awk '{print $1}')
if [[ "${actual}" != "${expected}" ]]; then
    echo "Unexpected S17 generic netlist SHA-256: ${actual}" >&2
    exit 1
fi

python3 "${s17_dir}/scripts/sanitize_genus_identifiers.py" \
    "${source_netlist}" \
    "${quartus_netlist}"

if [[ -f /etc/profile.d/quartus.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/quartus.sh
fi

cd "${s18_dir}/quartus"
quartus_sh --flow compile de1_s18_genus_snitch_rom_mmio
