#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
u4_dir=$(cd -- "${script_dir}/.." && pwd)
input="${u4_dir}/generated/de1_u4_cluster_generic.v"
output="${u4_dir}/generated/de1_u4_cluster_quartus.v"

if [[ ! -f "${input}" ]]; then
    echo "Missing transferred Genus netlist: ${input}" >&2
    exit 1
fi

python "${script_dir}/inject_cyclone_srams.py" "${input}" "${output}"
printf 'Prepared %s\n' "${output}"
