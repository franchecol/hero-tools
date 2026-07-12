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
log="${u5_dir}/quartus/cluster_fit.flow.log"
if ! quartus_sh --flow compile "${u5_dir}/quartus/cluster_fit" >"${log}" 2>&1; then
    tail -100 "${log}" >&2
    exit 1
fi

fit_summary="${u5_dir}/quartus/cluster_fit.fit.summary"
sta_summary="${u5_dir}/quartus/cluster_fit.sta.summary"

grep -E "Fitter Status|Logic utilization|Total registers|Total block memory bits|Total RAM Blocks|Total DSP Blocks" \
    "${fit_summary}"
grep -E "Type  :|Slack :|TNS   :" "${sta_summary}"

worst_setup=$(awk '/Type  : Slow 1100mV 85C Model Setup/{getline; print $3; exit}' "${sta_summary}")
if awk -v slack="${worst_setup}" 'BEGIN { exit !(slack < 0) }'; then
    echo "Physical fit passed, but the 50 MHz setup constraint failed (${worst_setup} ns)."
    echo "See the Timing Analyzer Fmax summary before selecting the operating clock."
fi
