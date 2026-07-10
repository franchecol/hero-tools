#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s19_dir=$(cd -- "${script_dir}/.." && pwd)
source_netlist="${s19_dir}/build/snitch_mem_generic_netlist.v"
quartus_netlist="${s19_dir}/build/snitch_mem_generic_quartus.v"
expected=558f10a2df2b65d74f35532d985ad892e035d8873cd306b1f5c3de107807d882

"${script_dir}/build_sw.sh"

if [[ ! -f "${source_netlist}" ]]; then
    echo "Missing U2 Genus netlist. Run deploy_and_run_lab.sh and fetch_netlist.sh." >&2
    exit 1
fi

actual=$(sha256sum "${source_netlist}" | awk '{print $1}')
if [[ "${actual}" != "${expected}" ]]; then
    echo "Unexpected U2 generic netlist SHA-256: ${actual}" >&2
    exit 1
fi

python3 "${s19_dir}/../u0_genus_snitch_core/scripts/sanitize_genus_identifiers.py" \
    "${source_netlist}" \
    "${quartus_netlist}"

if [[ -f /etc/profile.d/quartus.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/quartus.sh
fi

cd "${s19_dir}/quartus"
quartus_sh --flow compile de1_s19_genus_snitch_data_ram
