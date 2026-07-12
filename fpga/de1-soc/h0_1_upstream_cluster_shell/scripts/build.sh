#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h0_dir=$(cd -- "${script_dir}/.." && pwd)
u4_dir=$(cd -- "${h0_dir}/../u4_cyclone_memory_boundary" && pwd)

"${u4_dir}/scripts/prepare_quartus_netlist.sh"
log="${h0_dir}/quartus/cluster_shell.map.log"
if ! quartus_map "${h0_dir}/quartus/cluster_shell" >"${log}" 2>&1; then
    tail -100 "${log}" >&2
    exit 1
fi

summary="${h0_dir}/quartus/cluster_shell.map.summary"
grep -E "Analysis & Synthesis Status|Total registers|Total block memory bits" "${summary}"
