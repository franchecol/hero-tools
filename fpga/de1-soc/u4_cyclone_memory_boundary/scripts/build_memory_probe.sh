#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
u4_dir=$(cd -- "${script_dir}/.." && pwd)

quartus_sh --flow compile "${u4_dir}/quartus/memory_inference_probe"

fit_report="${u4_dir}/quartus/memory_inference_probe.fit.rpt"
map_report="${u4_dir}/quartus/memory_inference_probe.map.rpt"

grep -E "Total block memory bits|M10K|Total logic elements|Total registers" \
    "${fit_report}" "${map_report}" || true
