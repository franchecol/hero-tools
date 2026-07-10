#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s17_dir=$(cd -- "${script_dir}/.." && pwd)
netlist="${s17_dir}/build/snitch_core_generic_netlist.v"
quartus_netlist="${s17_dir}/build/snitch_core_generic_quartus.v"

if [[ ! -f "${netlist}" ]]; then
    echo "Missing Genus generic netlist: ${netlist}" >&2
    exit 1
fi

expected=2fc7264bb63ffdcd86ba1bf275c2e55de44bda7d6058a732d0c897bff69cf37c
actual=$(sha256sum "${netlist}" | awk '{print $1}')
if [[ "${actual}" != "${expected}" ]]; then
    echo "Unexpected generic netlist SHA-256: ${actual}" >&2
    exit 1
fi

python3 "${script_dir}/sanitize_genus_identifiers.py" \
    "${netlist}" \
    "${quartus_netlist}"

if [[ -f /etc/profile.d/quartus.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/quartus.sh
fi

cd "${s17_dir}/quartus"
quartus_sh --flow compile de1_s17_genus_snitch_core
