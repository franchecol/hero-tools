#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
u4_dir=$(cd -- "${script_dir}/.." && pwd)

"${script_dir}/prepare_quartus_netlist.sh"
quartus_sh --flow compile "${u4_dir}/quartus/cluster_fit"

grep -E "Logic utilization|Total registers|Total block memory bits|M10K blocks|DSP blocks" \
    "${u4_dir}/quartus/cluster_fit.fit.rpt" || true
