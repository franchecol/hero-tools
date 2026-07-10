#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s17_dir=$(cd -- "${script_dir}/.." && pwd)

lab_host=${LAB_HOST:-143.107.161.165}
lab_port=${LAB_PORT:-2223}
lab_user=${LAB_USER:-francotv}
remote_file='~/snitch_gatelevel_lab/s17/snitch_core_generic_netlist.v'
local_file="${s17_dir}/build/snitch_core_generic_netlist.v"
expected=2fc7264bb63ffdcd86ba1bf275c2e55de44bda7d6058a732d0c897bff69cf37c

mkdir -p "${s17_dir}/build"
scp -P "${lab_port}" \
    "${lab_user}@${lab_host}:${remote_file}" \
    "${local_file}"

actual=$(sha256sum "${local_file}" | awk '{print $1}')
if [[ "${actual}" != "${expected}" ]]; then
    echo "Unexpected generic netlist SHA-256: ${actual}" >&2
    exit 1
fi

echo "Verified generic netlist SHA-256: ${actual}"
