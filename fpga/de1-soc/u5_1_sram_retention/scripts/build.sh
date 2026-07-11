#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
u5_dir=$(cd -- "${script_dir}/.." && pwd)
u4_dir=$(cd -- "${u5_dir}/../u4_cyclone_memory_boundary" && pwd)

if [[ ! -f "${u4_dir}/generated/de1_u4_cluster_generic.v" ]]; then
    echo "Missing U4 Genus netlist: ${u4_dir}/generated/de1_u4_cluster_generic.v" >&2
    exit 1
fi

"${u4_dir}/scripts/prepare_quartus_netlist.sh"
log="${u5_dir}/quartus/sram_retention.map.log"
if ! quartus_map "${u5_dir}/quartus/sram_retention" >"${log}" 2>&1; then
    tail -80 "${log}" >&2
    exit 1
fi

report="${u5_dir}/quartus/sram_retention.map.rpt"
summary="${u5_dir}/quartus/sram_retention.map.summary"

grep -E "Analysis & Synthesis Status|Total registers|Total block memory bits" "${summary}"

memory_count=$(grep -c "ALTSYNCRAM.*; M10K block" "${report}" || true)
if [[ "${memory_count}" -ne 8 ]]; then
    echo "Expected 8 retained SRAM instances, found ${memory_count}" >&2
    exit 1
fi

memory_bits=$(sed -n 's/^Total block memory bits : \([0-9,]*\)$/\1/p' "${summary}")
if [[ "${memory_bits}" != "169,728" ]]; then
    echo "Expected 169,728 retained block-memory bits, found ${memory_bits:-none}" >&2
    exit 1
fi

printf 'Retained all %s upstream SRAM banks in %s block-memory bits.\n' \
    "${memory_count}" "${memory_bits}"
