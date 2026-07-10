#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s19_dir=$(cd -- "${script_dir}/.." && pwd)
lab_host=${LAB_HOST:-143.107.161.165}
lab_port=${LAB_PORT:-2223}
lab_user=${LAB_USER:-francotv}
remote="${lab_user}@${lab_host}"
expected=558f10a2df2b65d74f35532d985ad892e035d8873cd306b1f5c3de107807d882

mkdir -p "${s19_dir}/build"
scp -P "${lab_port}" \
    "${remote}:~/snitch_gatelevel_lab/s19/snitch_mem_generic_netlist.v" \
    "${s19_dir}/build/snitch_mem_generic_netlist.v"

actual=$(sha256sum "${s19_dir}/build/snitch_mem_generic_netlist.v" | awk '{print $1}')
if [[ "${actual}" != "${expected}" ]]; then
    echo "Unexpected generic netlist SHA-256: ${actual}" >&2
    exit 1
fi

echo "Verified generic netlist SHA-256: ${actual}"
